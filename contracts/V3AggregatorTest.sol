//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";

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

contract V3AggregatorTest is IUniswapV3MintCallback {
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
        uint128 liquidity,
        int24 tickLower,
        int24 tickUpper
    );

    // store total stake points
    uint256 public totalShare;

    mapping(address => mapping(address => uint256)) public shares;

    // TEST FUNCTION
    function getShares(address strat, address user) external view returns(uint256) {
        return shares[strat][user];
    }
    // TEST - end

    // mapping of strategies with their total share
    mapping(address => uint256) public totalShares;
    // TEST -- TEST -- TEST -- totalShares "PUBLIC" is test

    struct MintCallbackData {
        address payer;
        address pool;
    }

    struct Strategy {
        int24 tickLower;
        int24 tickUpper;
        int24 secondaryTickLower;  // NEW
        int24 secondaryTickUpper; //
        bool swap; //
        bool hold; // NEW END
    }

    mapping(address => Strategy) public strategies;

    mapping(address => bool) public blacklisted;

    // NEW NEW NEW NEW NEW
    struct Hold {
        uint256 amount0;
        uint256 amount1;
    }
    // hold
    mapping(address => Hold) public holds;
    // NEW

    // to update protocol fees
    address public feeSetter;

    // to receive the fees
    address public feeTo;

    // protocol fees, 1e8 is 100% // don't you mean 1e6?
    uint256 public PROTOCOL_FEE;

    constructor(address _feeSetter) {
        feeSetter = _feeSetter;
        feeTo = address(0);
        
        // TEST 
        PROTOCOL_FEE = 500000;
        // TEST - end
    }

    /*
     * @notice Add liquidity to specific strategy
     * @param _strategy Address of the strategy
     * @param _amount0 Desired token0 amount
     * @param _amount1 Desired token1 amount
     * @param _amount0Min Minimum amoount for to be added for token0
     * @param _amount1Min Minimum amoount for to be added for token1
     */
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
                strategy.pool(),
                strategy.tickLower(),
                strategy.tickUpper()
            );

        // console.log(liquidityBefore);

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
            liquidity,
            msg.sender
        );

        uint128 liquidityAfter =
            getCurrentLiquidity(
                address(pool),
                strategy.tickLower(),
                strategy.tickUpper()
            );

        // TEST
        require(liquidityAfter - liquidityBefore == liquidity, "Loss of liquidity");
        // TEST - END

        // PENDING TEST CHANGES - REVIEW
        // POTENTIAL SOLUTION BELOW

        // calculate shares
        // TODO: Replace liquidity with liquidityBefore
        share = uint256(liquidityAfter)
            .sub(liquidity)
            .mul(totalShare)
            .div(liquidity);
            // .add(1000);

        if (share == 0) {
            share = liquidity; // can add decimals here if desired.
        }
        // PENDING TEST CHANGES - END

        // ADD CHECK FOR PROTOCOL_FEE == 0
        if (feeTo != address(0) ) {
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

        updateStrategyData(_strategy);

        emit AddLiquidity(_strategy, amount0, amount1);
    }

    function TESTgetPositionKey(address addr, int24 tickLower, int24 tickUpper) external view returns(bytes32) {
        return PositionKey.compute(addr, tickLower, tickUpper);
    }


    /*
     * @notice Removes liquidity from the pool
     * @param _stategy Address of the strategy
     * @param _shares Share user wants to burn
     * @param _amount0Min Minimum amount0 user should receive
     * @param _amount1Min Minimum amount1 user should receive
     */
    function removeLiquidity(
        address _strategy,
        uint256 _shares,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());

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

        (uint256 amount0, uint256 amount1) =
            getAmountsForLiquidity(
                address(pool),
                strategy.tickLower(),
                strategy.tickUpper(),
                liquidity
            );

        // check price slippage with the amounts provided
        require(
            _amount0Min <= amount0 && _amount1Min <= amount1,
            "Aggregator: Slippage"
        );

        // burn liquidity
        (uint256 amount0Real, uint256 amount1Real) =
            pool.burn(strategy.tickLower(), strategy.tickUpper(), liquidity);

        // collect fees
        (uint128 collect0, uint128 collect1) =
            pool.collect(
                address(this),
                strategy.tickLower(),
                strategy.tickUpper(),
                type(uint128).max,
                type(uint128).max
            );

        // check price slippage on burned liquidity
        require(
            _amount0Min <= amount0Real && _amount1Min <= amount1Real,
            "Aggregator: Slippage"
        );

        // burn shares of the user
        burnShare(_strategy, _shares);

        // transfer the tokens back
        if (amount0Real > 0) {
            IERC20(pool.token0()).transfer(msg.sender, amount0Real);
        }
        if (amount1Real > 0) {
            IERC20(pool.token1()).transfer(msg.sender, amount1Real);
        }

        emit RemoveLiquidity(_strategy, amount0Real, amount1Real);
    }

    /*
     * @notice Rebalances the pool to new ranges
     * @param _strategy Address of the strategy
     */

    function rebalance(address _strategy)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        Strategy storage oldStrategy = strategies[_strategy];

        // add blacklisting check
        require(!blacklisted[_strategy], "blacklisted");

        uint128 liquidity;

        if (strategy.hold()) {
            (amount0, amount1, liquidity) = burnAllLiquidity(_strategy);
            Hold storage newHold = holds[_strategy];
            newHold.amount0 = amount0;
            newHold.amount1 = amount1;
        } else if (oldStrategy.hold) {
            Hold storage oldHold = holds[_strategy];
            amount0 = oldHold.amount0;
            amount1 = oldHold.amount1;
            liquidity = getLiquidityForAmounts(
                address(pool),
                strategy.tickLower(),
                strategy.tickUpper(),
                amount0,
                amount1
            );
            redeploy(_strategy, amount0, amount1, liquidity);
        } else {
            (amount0, amount1, liquidity) = burnAllLiquidity(_strategy);
            redeploy(_strategy, amount0, amount1, liquidity);
        }
        
        // emit event
        emit Rebalance(
            _strategy,
            msg.sender,
            liquidity,
            strategy.tickLower(),
            strategy.tickUpper()
        );
    }

    // TEST -- VARIABLES -- TEST -- VARIABLES
    uint256 public owed0Test;
    uint256 public owed1Test;
    uint128 public collect0Test;
    uint128 public collect1Test;
    // TEST -- VARIABLES -- TEST -- VARIABLES
    function redeploy(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1,
        uint128 _oldLiquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        Strategy storage oldStrategy = strategies[_strategy];

        // calculate current liquidity
        uint128 liquidity =
            getLiquidityForAmounts(
                address(pool),
                strategy.tickLower(),
                strategy.tickUpper(),
                _amount0,
                _amount1
            );

        // mint liquidity
        mintLiquidity(
            address(pool),
            strategy.tickLower(),
            strategy.tickUpper(),
            liquidity,
            address(this)
        );

        uint128 unusedLiquidity =
            _oldLiquidity > liquidity
                ? _oldLiquidity - liquidity
                : liquidity - _oldLiquidity;

        // calculate pending amount0 and amount1
        (amount0, amount1) = getAmountsForLiquidity(
            address(pool),
            oldStrategy.tickLower,
            oldStrategy.tickUpper,
            unusedLiquidity
        );

        if (strategy.swap()) {
            // swap the tokens
        } else {
            if (
                strategy.secondaryTickLower() != 0 &&
                strategy.secondaryTickUpper() != 0
            ) {
                uint128 secondaryLiquidity =
                    getLiquidityForAmounts(
                        address(this),
                        strategy.secondaryTickLower(),
                        strategy.secondaryTickUpper(),
                        amount0,
                        amount1
                    );
                mintLiquidity(
                    address(pool),
                    strategy.secondaryTickLower(),
                    strategy.secondaryTickUpper(),
                    secondaryLiquidity,
                    address(this)
                );
            }
        }

        // update strategy
        updateStrategyData(_strategy);

        // emit event
        emit Rebalance(
            _strategy,
            msg.sender,
            liquidity,
            strategy.tickLower(),
            strategy.tickUpper()
        );
    }

    /// @notice Mints liquidity from V3 Pool
    /// @param _pool Address of the pool
    /// @param _tickLower Lower tick
    /// @param _tickUpper Upper tick
    /// @param _liquidity Liquidity to mint
    /// @param _payer Address which is adding the liquidity
    function mintLiquidity(
        address _pool,
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _liquidity,
        address _payer
    ) internal returns (uint256 amount0, uint256 amount1) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        // add liquidity to Uniswap pool
        (amount0, amount1) = pool.mint(
            address(this),
            _tickLower,
            _tickUpper,
            _liquidity,
            abi.encode(MintCallbackData({payer: _payer, pool: _pool}))
        );
    }

    /// @notice Burns liquidity in the given range
    /// @param _pool Address of the pool
    /// @param _strategy Address of the strategy
    /// @param _tickLower Lower Tick
    /// @param _tickUpper Upper Tick
    function burnLiquidity(
        address _pool,
        address _strategy,
        int24 _tickLower,
        int24 _tickUpper
    )
        internal
        returns (
            uint256 collect0,
            uint256 collect1,
            uint128 liquidity
        )
    {
        // calculate current liquidity
        liquidity = getCurrentLiquidity(_pool, _tickLower, _tickUpper);
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        // burn liquidity
        (uint256 owed0, uint256 owed1) =
            pool.burn(_tickLower, _tickUpper, liquidity);

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
                oldStrategy.tickUpper
            );

        uint256 limitAmount0;
        uint256 limitAmount1;
        uint128 limitLiquidity;

        if (
            oldStrategy.secondaryTickLower != 0 &&
            oldStrategy.secondaryTickUpper != 0
        ) {
            // Burn liquidity for limit order
            (limitAmount0, limitAmount1, limitLiquidity) = burnLiquidity(
                address(pool),
                address(strategy),
                oldStrategy.secondaryTickLower,
                oldStrategy.secondaryTickUpper
            );
        }

        liquidity = rangeLiquidity + limitLiquidity;
        amount0 = rangeAmount0 + limitAmount0;
        amount1 = rangeAmount1 + limitAmount1;
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

    /*
     * @notice Updates the shares of the user
     * @param _strategy Address of the strategy
     * @param _shares amount of shares user wants to burn
     * @param _to address where shares should be issued
     */
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

    /*
     * @notice Burns the share of the user
     * @param _strategy Address of the strategy
     * @param _shares amount of shares user wants to burn
     */
    function burnShare(address _strategy, uint256 _shares) internal {
        // update shares
        shares[_strategy][msg.sender] = shares[_strategy][msg.sender].sub(
            uint256(_shares)
        );
        // update total shares
        totalShares[_strategy] = totalShares[_strategy].sub(_shares);
        emit BurnShare(_strategy, msg.sender, _shares);
    }

    /*
     * @notice Calculates the liquidity amount using current ranges
     * @param _strategy Address of the strategy
     * @param _amount0 Amount to be added for token0
     * @param _amount1 Amount to be added for token1
     * @return liquidity Liquidity amount derived from token amounts
     */
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

    function getSqrtRatioTEST(int24 tick) external view returns(uint160 liquidity) {
        liquidity = TickMath.getSqrtRatioAtTick(tick);
    }

    function getLiqAmtTEST(uint160 sqrtRatioX96, uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint256 _amount0, uint256 _amount1)
        external
        view
        returns(uint128 liquidity) 
        {
            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
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

    function getAmtForLiqTEST(uint160 sqrtRatioX96, uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 _liquidity)
        external
        view
        returns(uint256 amount0, uint256 amount1) 
        {
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                _liquidity
            );
        }

    /*
     * @dev Get the liquidity between current ticks
     * @param _strategy Strategy address
     * @param _tickLower Lower tick of the range
     * @param _tickUpper Upper tick of the range
     */
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

    /*
     * @dev Updates strategy data for future use
     * @param _stategy Address of the strategy
     */
    function updateStrategyData(address _strategy) internal {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        Strategy storage newStrategy = strategies[_strategy];
        if (
            newStrategy.tickLower != strategy.tickLower() &&
            newStrategy.tickUpper != strategy.tickUpper()
        ) {
            newStrategy.tickLower = strategy.tickLower();
            newStrategy.tickUpper = strategy.tickUpper();
            newStrategy.secondaryTickLower = strategy.secondaryTickLower();
            newStrategy.secondaryTickUpper = strategy.secondaryTickLower();
        }
    }

    /*
     * @dev Change the fee setter's address
     * @param _feeSetter New feeSetter address
     */
    function changeFeeSetter(address _feeSetter) external {
        require(msg.sender == _feeSetter);
        feeSetter = _feeSetter;
    }

    /*
     * @dev Change fee receiver
     * @param _feeTo New fee receiver
     */
    function changeFeeTo(address _feeTo) external {
        require(msg.sender == feeSetter);
        feeTo = _feeTo;
    }

    function blacklist(address _strategy) external {
        require(msg.sender == feeSetter);
        blacklisted[_strategy] = true;
    }
}
