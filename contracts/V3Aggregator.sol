//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

import "./IUnboundStrategy.sol";

import "hardhat/console.sol";

// TODO: Add Reentrancy guard
// TODO: Add Pausable functionality
// TODO: Remove liquidity partially
// TODO: Store unused balances and give percentage from it for specific strategy
// TODO: Implement fees for strategy owner

contract V3Aggregator is IUniswapV3MintCallback, IUniswapV3SwapCallback {
    using SafeMath for uint256;
    using SafeCast for uint256;

    // events
    event AddLiquidity(
        address indexed strategy,
        uint256 amount0,
        uint256 amount1
    );

    event RemoveLiquidity(
        address indexed strategy,
        uint256 amount0,
        uint256 amount1
    );

    event MintShare(
        address indexed strategy,
        address indexed user,
        uint256 amount
    );

    event BurnShare(
        address indexed strategy,
        address indexed user,
        uint256 amount
    );

    event FeesClaimed(
        address indexed pool,
        address indexed strategy,
        uint256 amount0,
        uint256 amount1
    );

    event Rebalance(
        address indexed strategy,
        address indexed caller,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    );

    // store total stake points
    uint256 public totalShare;

    mapping(address => mapping(address => uint256)) public shares;

    // mapping of strategies with their total share
    mapping(address => uint256) totalShares;

    struct MintCallbackData {
        address payer;
        address pool;
    }

    struct SwapCallbackData {
        address pool;
        bool zeroToOne;
    }

    struct Strategy {
        uint256 amount0;
        uint256 amount1;
        uint256 secondaryAmount0;
        uint256 secondaryAmount1;
        int24 tickLower;
        int24 tickUpper;
        int24 secondaryTickLower;
        int24 secondaryTickUpper;
        bool swap;
        bool hold;
    }

    mapping(address => Strategy) public strategies;

    // mapping of blacklisted strategies
    mapping(address => bool) public blacklisted;

    struct UnusedAmounts {
        uint256 amount0;
        uint256 amount1;
    }
    // hold
    mapping(address => UnusedAmounts) public unused;

    // to update protocol fees
    address public feeSetter;

    // to receive the fees
    address public feeTo;

    // protocol fees, 1e8 is 100%
    uint256 public PROTOCOL_FEE;

    constructor(address _feeSetter) {
        feeSetter = _feeSetter;
        feeTo = address(0);
    }

    /// @notice Add liquidity to specific strategy
    /// @param _strategy Address of the strategy
    /// @param _amount0 Desired token0 amount
    /// @param _amount1 Desired token1 amount
    /// @param _amount0Min Minimum amoount for to be added for token0
    /// @param _amount1Min Minimum amoount for to be added for token1
    function addLiquidity(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _amount0Min,
        uint256 _amount1Min
    )
        external
        returns (
            uint256 share,
            uint256 amount0,
            uint256 amount1
        )
    {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());

        uint128 liquidityBefore =
            getCurrentLiquidity(
                address(pool),
                strategy.tickLower(),
                strategy.tickUpper()
            );

        uint128 liquidity =
            getLiquidityForAmounts(
                address(pool),
                strategy.tickLower(),
                strategy.tickUpper(),
                _amount0,
                _amount1
            );

        (amount0, amount1) = mintLiquidity(
            address(pool),
            strategy.tickLower(),
            strategy.tickUpper(),
            _amount0,
            _amount1,
            msg.sender
        );

        uint128 liquidityAfter =
            getCurrentLiquidity(
                address(pool),
                strategy.tickLower(),
                strategy.tickUpper()
            );

        // calculate shares
        // TODO: Replace liquidity with liquidityBefore
        share = uint256(liquidityAfter)
            .sub(liquidity)
            .mul(totalShare)
            .div(liquidity)
            .add(1000);

        if (feeTo != address(0)) {
            uint256 fee = share.mul(PROTOCOL_FEE).div(1e6);
            // issue fee
            issueShare(_strategy, fee, feeTo);
            // issue shares
            issueShare(_strategy, share.sub(fee), msg.sender);
        } else {
            // update shares w.r.t. strategy
            issueShare(_strategy, share, msg.sender);
        }

        // price slippage check
        require(
            amount0 >= _amount0Min && amount1 >= _amount1Min,
            "Aggregator: Slippage"
        );

        updateStrategy(_strategy, amount0, amount1, 0, 0);

        emit AddLiquidity(_strategy, amount0, amount1);
    }

    /// @notice Removes liquidity from the pool
    /// @param _strategy Address of the strategy
    /// @param _shares Share user wants to burn
    /// @param _amount0Min Minimum amount0 user should receive
    /// @param _amount1Min Minimum amount1 user should receive
    function removeLiquidity(
        address _strategy,
        uint256 _shares,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external returns (uint256 amount0, uint256 amount1) {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        require(shares[_strategy][msg.sender] >= _shares, "insuffcient shares");
        
        // 0. Removes liquidity from range order
        // 1. Removes liquidity from limit order
        // 2. Removes liquidity from unused liquidity

        // ccalculate current
        uint128 currentLiquidity =
            getCurrentLiquidity(
                address(pool),
                strategy.tickLower(),
                strategy.tickUpper()
            );

        // calculate current liquidity
        uint128 liquidity =
            _shares
                .mul(currentLiquidity)
                .div(totalShares[_strategy])
                .toUint128();

        // burn liquidity, remove from range order
        pool.burn(strategy.tickLower(), strategy.tickUpper(), liquidity);

        // collect tokens
        (uint128 collect0, uint128 collect1) =
            pool.collect(
                address(this),
                strategy.tickLower(),
                strategy.tickUpper(),
                type(uint128).max,
                type(uint128).max
            );

        // calculate unused amounts using share price
        (amount0, amount1) = getUnusedAmounts(_strategy);

        if (amount0 > 0) {
            amount0 = amount0.mul(_shares).div(totalShares[_strategy]);
        } else if (amount1 > 0) {
            amount1 = amount1.mul(_shares).div(totalShares[_strategy]);
        }

        // add collected values from the pool to unused values
        amount0 = amount0.add(collect0);
        amount1 = amount1.add(collect1);

        // check price slippage on burned liquidity
        require(
            _amount0Min <= amount0 && _amount1Min <= amount1,
            "Aggregator: Slippage"
        );

        // burn shares of the user
        burnShare(_strategy, _shares);

        // transfer the tokens back
        if (amount0 > 0) {
            IERC20(pool.token0()).transfer(msg.sender, amount0);
        }
        if (amount1 > 0) {
            IERC20(pool.token1()).transfer(msg.sender, amount1);
        }

        emit RemoveLiquidity(_strategy, amount0, amount1);
    }

    /// @notice Rebalances the pool to new ranges
    /// @param _strategy Address of the strategy
    // TODO: Put the remaining liquidity in limit order
    // TODO: Add an option to remove and hold the liquidity
    function rebalance(address _strategy)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        Strategy storage oldStrategy = strategies[_strategy];

        uint256 newAmount0;
        uint256 newAmount1;

        // add blacklisting check
        require(!blacklisted[_strategy], "blacklisted");

        uint128 liquidity;

        // if hold is activated in strategy, strategy will burn the funds and hold
        if (strategy.hold()) {
            // burn liquidity
            (amount0, amount1, liquidity) = burnAllLiquidity(_strategy);
            // store the values contract is holding
            increaseUnusedAmounts(_strategy, amount0, amount1);
        } else if (oldStrategy.hold) {
            // if hold has been enabled in previous update, deploy the hold
            // amount in the current ranges
            (amount0, amount1) = getUnusedAmounts(_strategy);

            liquidity = getLiquidityForAmounts(
                address(pool),
                strategy.tickLower(),
                strategy.tickUpper(),
                amount0,
                amount1
            );

            // redploy the liquidity
            (newAmount0, newAmount1) = redeploy(
                _strategy,
                amount0,
                amount1,
                liquidity
            );

            // decrease unused amounts
            decreaseUnusedAmounts(_strategy, newAmount0, newAmount1);
        } else {
            // remove all the liquidity
            (amount0, amount1, liquidity) = burnAllLiquidity(_strategy);

            // redploy the liquidity
            (newAmount0, newAmount1) = redeploy(
                _strategy,
                amount0,
                amount1,
                liquidity
            );

            // calculate unused amounts
            amount0 = amount0 > newAmount0
                ? amount0 - newAmount0
                : newAmount0 - amount0;
            amount1 = amount1 > newAmount1
                ? amount1 - newAmount1
                : newAmount1 - amount1;

            // increase amounts
            updateUnusedAmounts(_strategy, amount0, amount1);
        }
    }

    // TODO: Add Swap functionality
    /// @notice Redeploys the liquidity
    /// @param _amount0 Amount of token0
    /// @param _amount1 Amount of token1
    /// @param _oldLiquidity Value of the liquidity previously added
    function redeploy(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1,
        uint128 _oldLiquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        Strategy storage newStrategy = strategies[_strategy];

        uint256 secondaryAmount0;
        uint256 secondaryAmount1;

        if (strategy.swapAmount() > 0) {
            // swap tokens
            swap(
                address(pool),
                strategy.zeroToOne(),
                strategy.swapAmount(),
                strategy.allowedSlippage()
            );

            // mint liquidity after swap
            (amount0, amount1) = mintLiquidity(
                address(pool),
                strategy.tickLower(),
                strategy.tickUpper(),
                _amount0,
                _amount1,
                address(this)
            );
            // update strategy
            updateStrategy(_strategy, amount0, amount1, 0, 0);
        } else {
            // mint liquidity in range order
            (amount0, amount1) = mintLiquidity(
                address(pool),
                strategy.tickLower(),
                strategy.tickUpper(),
                _amount0,
                _amount1,
                address(this)
            );

            // mint remaining liquidity in limit order
            if (
                strategy.secondaryTickLower() != 0 &&
                strategy.secondaryTickUpper() != 0
            ) {
                uint128 secondaryLiquidity =
                    getLiquidityForAmounts(
                        address(pool),
                        strategy.secondaryTickLower(),
                        strategy.secondaryTickUpper(),
                        _amount0 - amount0,
                        _amount1 - amount1
                    );
                if (secondaryLiquidity > 0) {
                    secondaryAmount0 = _amount0 - amount0;
                    secondaryAmount1 = _amount1 - amount1;

                    mintLiquidity(
                        address(pool),
                        strategy.secondaryTickLower(),
                        strategy.secondaryTickUpper(),
                        secondaryAmount0,
                        secondaryAmount1,
                        address(this)
                    );
                }
            }

            // update strategy
            updateStrategy(
                _strategy,
                amount0,
                amount1,
                secondaryAmount0,
                secondaryAmount1
            );
        }

        // emit event
        emit Rebalance(
            _strategy,
            msg.sender,
            amount0,
            amount1,
            strategy.tickLower(),
            strategy.tickUpper()
        );
    }

    /// @notice Mints liquidity from V3 Pool
    /// @param _pool Address of the pool
    /// @param _tickLower Lower tick
    /// @param _tickUpper Upper tick
    /// @param _amount0 Amount of token0
    /// @param _amount1 Amount of token1
    /// @param _payer Address which is adding the liquidity
    function mintLiquidity(
        address _pool,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0,
        uint256 _amount1,
        address _payer
    ) internal returns (uint256 amount0, uint256 amount1) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        uint128 liquidity =
            getLiquidityForAmounts(
                address(pool),
                _tickLower,
                _tickUpper,
                _amount0,
                _amount1
            );
        // add liquidity to Uniswap pool
        (amount0, amount1) = pool.mint(
            address(this),
            _tickLower,
            _tickUpper,
            liquidity,
            abi.encode(MintCallbackData({payer: _payer, pool: address(pool)}))
        );
    }

    /// @notice Burns liquidity in the given range
    /// @param _pool Address of the pool
    /// @param _strategy Address of the strategy
    /// @param _tickLower Lower Tick
    /// @param _tickUpper Upper Tick
    /// @param _amount0 Amount 0 to burn
    /// @param _amount1 Amount to burn
    function burnLiquidity(
        address _pool,
        address _strategy,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0,
        uint256 _amount1
    )
        internal
        returns (
            uint256 collect0,
            uint256 collect1,
            uint128 liquidity
        )
    {

        // calculate current liquidity
        // liquidity = getCurrentLiquidity(_pool, _tickLower, _tickUpper);
        liquidity = getLiquidityForAmounts(
            _pool,
            _tickLower,
            _tickUpper,
            _amount0,
            _amount1
        );
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        uint256 owed0;
        uint256 owed1;

        // burn liquidity
        if (liquidity > 0) {
            (owed0, owed1) = pool.burn(_tickLower, _tickUpper, liquidity);
        }

        // collect fees
        (collect0, collect1) = pool.collect(
            address(this),
            _tickLower,
            _tickUpper,
            type(uint128).max,
            type(uint128).max
        );

        emit FeesClaimed(
            _strategy,
            _pool,
            uint256(collect0) - owed0,
            uint256(collect1) - owed1
        );
    }

    /// @notice Burns all the liquidity and collects fees
    /// @param _strategy Address of the strategy
    function burnAllLiquidity(address _strategy)
        internal
        returns (
            uint256 amount0,
            uint256 amount1,
            uint128 liquidity
        )
    {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        Strategy storage oldStrategy = strategies[_strategy];

        // Burn liquidity for range order
        (uint256 rangeAmount0, uint256 rangeAmount1, uint128 rangeLiquidity) =
            burnLiquidity(
                address(pool),
                address(strategy),
                oldStrategy.tickLower,
                oldStrategy.tickUpper,
                oldStrategy.amount0,
                oldStrategy.amount1
            );

        uint256 limitAmount0;
        uint256 limitAmount1;
        uint128 limitLiquidity;

        // Burn liquidity for limit order
        if (
            oldStrategy.secondaryTickLower != 0 &&
            oldStrategy.secondaryTickUpper != 0
        ) {
            (limitAmount0, limitAmount1, limitLiquidity) = burnLiquidity(
                address(pool),
                address(strategy),
                oldStrategy.secondaryTickLower,
                oldStrategy.secondaryTickUpper,
                oldStrategy.secondaryAmount0,
                oldStrategy.secondaryAmount1
            );
        }

        liquidity = rangeLiquidity + limitLiquidity;
        amount0 = rangeAmount0 + limitAmount0;
        amount1 = rangeAmount1 + limitAmount1;
    }

    function swap(
        address _pool,
        bool _zeroToOne,
        int256 _amount,
        uint160 _allowedSlippage
    ) internal returns (int256 amount0, int256 amount1) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        // TODO: Support partial slippage
        uint160 sqrtPriceLimitX96 =
            _zeroToOne
                ? sqrtRatioX96 - (sqrtRatioX96 * _allowedSlippage) / 100
                : sqrtRatioX96 + (sqrtRatioX96 * _allowedSlippage) / 100;

        (amount0, amount1) = pool.swap(
            address(this),
            _zeroToOne,
            _amount,
            sqrtPriceLimitX96,
            abi.encode(
                SwapCallbackData({pool: address(pool), zeroToOne: _zeroToOne})
            )
        );
    }

    /// @dev Callback for Uniswap V3 pool.
    function uniswapV3SwapCallback(
        int256 amount0,
        int256 amount1,
        bytes calldata data
    ) external override {
        SwapCallbackData memory decoded = abi.decode(data, (SwapCallbackData));

        uint256 amt0 = uint256(amount0);
        uint256 amt1 = uint256(amount1 * -1);

        // check if the callback is received from Uniswap V3 Pool
        require(msg.sender == address(decoded.pool));

        IUniswapV3Pool pool = IUniswapV3Pool(decoded.pool);

        if (decoded.zeroToOne) {
            TransferHelper.safeTransfer(
                pool.token0(),
                msg.sender,
                uint256(amount0)
            );
        } else {
            TransferHelper.safeTransfer(
                pool.token0(),
                msg.sender,
                uint256(amount1)
            );
        }
    }

    /// @dev Callback for Uniswap V3 pool.
    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));

        // check if the callback is received from Uniswap V3 Pool
        require(msg.sender == address(decoded.pool));

        IUniswapV3Pool pool = IUniswapV3Pool(decoded.pool);

        if (decoded.payer == address(this)) {
            // transfer tokens already in the contract
            if (amount0 > 0) {
                TransferHelper.safeTransfer(pool.token0(), msg.sender, amount0);
            }
            if (amount1 > 0) {
                TransferHelper.safeTransfer(pool.token1(), msg.sender, amount1);
            }
        } else {
            // take and transfer tokens to Uniswap V3 pool from the user
            if (amount0 > 0) {
                TransferHelper.safeTransferFrom(
                    pool.token0(),
                    decoded.payer,
                    msg.sender,
                    amount0
                );
            }
            if (amount1 > 0) {
                TransferHelper.safeTransferFrom(
                    pool.token1(),
                    decoded.payer,
                    msg.sender,
                    amount1
                );
            }
        }
    }

    function increaseUnusedAmounts(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1
    ) internal returns (uint256 amount0, uint256 amount1) {
        UnusedAmounts storage unusedAmounts = unused[_strategy];
        unusedAmounts.amount0 = unusedAmounts.amount0.add(_amount0);
        unusedAmounts.amount1 = unusedAmounts.amount1.add(_amount1);
    }

    function updateUnusedAmounts(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1
    ) internal returns (uint256 amount0, uint256 amount1) {
        UnusedAmounts storage unusedAmounts = unused[_strategy];
        unusedAmounts.amount0 = _amount0;
        unusedAmounts.amount1 = _amount1;
    }

    function decreaseUnusedAmounts(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1
    ) internal returns (uint256 amount0, uint256 amount1) {
        UnusedAmounts storage unusedAmounts = unused[_strategy];
        unusedAmounts.amount0 = unusedAmounts.amount0.add(_amount0);
        unusedAmounts.amount1 = unusedAmounts.amount1.add(_amount1);
    }

    function getUnusedAmounts(address _strategy)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        UnusedAmounts storage unusedAmounts = unused[_strategy];
        amount0 = unusedAmounts.amount0;
        amount1 = unusedAmounts.amount1;
    }

    /// @notice Updates the shares of the user
    /// @param _strategy Address of the strategy
    /// @param _shares amount of shares user wants to burn
    /// @param _to address where shares should be issued
    function issueShare(
        address _strategy,
        uint256 _shares,
        address _to
    ) internal {
        // update shares
        shares[_strategy][_to] = shares[_strategy][_to].add(uint256(_shares));
        // update total shares
        totalShares[_strategy] = totalShares[_strategy].add(_shares);
        // emit event
        emit MintShare(_strategy, _to, _shares);
    }

    /// @notice Burns the share of the user
    /// @param _strategy Address of the strategy
    /// @param _shares amount of shares user wants to burn
    function burnShare(address _strategy, uint256 _shares) internal {
        // update shares
        shares[_strategy][msg.sender] = shares[_strategy][msg.sender].sub(
            uint256(_shares)
        );
        // update total shares
        totalShares[_strategy] = totalShares[_strategy].sub(_shares);
        emit BurnShare(_strategy, msg.sender, _shares);
    }

    /// @notice Calculates the liquidity amount using current ranges
    /// @param _pool Pool address
    /// @param _tickLower Lower tick
    /// @param _tickUpper Upper tick
    /// @param _amount0 Amount to be added for token0
    /// @param _amount1 Amount to be added for token1
    /// @return liquidity Liquidity amount derived from token amounts
    function getLiquidityForAmounts(
        address _pool,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0,
        uint256 _amount1
    ) internal view returns (uint128 liquidity) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        // get sqrtRatios required to calculate liquidity
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        // calculate liquidity needs to be added
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(_tickLower),
            TickMath.getSqrtRatioAtTick(_tickUpper),
            _amount0,
            _amount1
        );
    }

    /// @notice Calculates the liquidity amount using current ranges
    /// @param _pool Address of the pool
    /// @param _tickLower Lower tick
    /// @param _tickUpper Upper tick
    /// @param _liquidity Liquidity of the pool
    function getAmountsForLiquidity(
        address _pool,
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _liquidity
    ) internal view returns (uint256 amount0, uint256 amount1) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        // get sqrtRatios required to calculate liquidity
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        // calculate liquidity needs to be added
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(_tickLower),
            TickMath.getSqrtRatioAtTick(_tickUpper),
            _liquidity
        );
    }

    /// @dev Get the liquidity between current ticks
    /// @param _pool Address of the pool
    /// @param _tickLower Lower tick of the range
    /// @param _tickUpper Upper tick of the range
    function getCurrentLiquidity(
        address _pool,
        int24 _tickLower,
        int24 _tickUpper
    ) internal view returns (uint128 liquidity) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        (liquidity, , , , ) = pool.positions(
            PositionKey.compute(address(this), _tickLower, _tickUpper)
        );
    }

    /// @dev Updates strategy data for future use
    /// @param _strategy Address of the strategy
    /// @param _amount0 Amount of token0
    /// @param _amount1 Amount of token1
    function updateStrategy(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _secondaryAmount0,
        uint256 _secondaryAmount1
    ) internal {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        Strategy storage newStrategy = strategies[_strategy];
        newStrategy.tickLower = strategy.tickLower();
        newStrategy.tickUpper = strategy.tickUpper();
        newStrategy.secondaryTickLower = strategy.secondaryTickLower();
        newStrategy.secondaryTickUpper = strategy.secondaryTickUpper();
        newStrategy.hold = strategy.hold();
        newStrategy.amount0 = _amount0;
        newStrategy.amount1 = _amount1;
        newStrategy.secondaryAmount0 = _secondaryAmount0;
        newStrategy.secondaryAmount1 = _secondaryAmount1;
    }

    /// @dev Change the fee setter's address
    /// @param _feeSetter New feeSetter address
    function changeFeeSetter(address _feeSetter) external {
        require(msg.sender == _feeSetter);
        feeSetter = _feeSetter;
    }

    /// @dev Change fee receiver
    /// @param _feeTo New fee receiver
    function changeFeeTo(address _feeTo) external {
        require(msg.sender == feeSetter);
        feeTo = _feeTo;
    }

    function blacklist(address _strategy) external {
        require(msg.sender == feeSetter);
        blacklisted[_strategy] = true;
    }
}
