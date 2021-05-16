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

contract V3Aggregator is IUniswapV3MintCallback {
    using SafeMath for uint256;
    using SafeCast for uint256;

    // store total stake points
    uint256 public totalShare;

    mapping(address => mapping(address => uint256)) public shares;

    // mapping of strategies with their total share
    mapping(address => uint256) totalShares;

    struct MintCallbackData {
        address payer;
        address pool;
    }

    struct Strategy {
        int24 tickLower;
        int24 tickUpper;
    }

    mapping(address => Strategy) public strategies;

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
            getLiquidityForAmounts(_strategy, _amount0, _amount1);

        (amount0, amount1) = mintLiquidity(_strategy, liquidity, false);

        console.log("mint0", amount0);
        console.log("mint1", amount1);

        uint128 liquidityAfter =
            getCurrentLiquidity(
                strategy.pool(),
                strategy.tickLower(),
                strategy.tickUpper()
            );

        // calculate shares
        // TODO: Replace liquidity with liquidityBefore
        share = uint256(liquidityAfter).sub(liquidity).mul(totalShare).div(
            liquidity
        );

        // update shares w.r.t. strategy
        issueShare(_strategy, share.add(1000));

        // price slippage check
        require(
            amount0 >= _amount0Min && amount1 >= _amount1Min,
            "Aggregator: Slippage"
        );

        // TODO: Add protocol fees
    }

    /*
     * @notice Mints liquidity from V3 Pool
     * @param _stategy Address of the strategy
     * @param _liquidity Liquidity to mint
     */
    function mintLiquidity(
        address _strategy,
        uint128 _liquidity,
        bool rebalance
    ) internal returns (uint256 amount0, uint256 amount1) {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());

        address payer;
        payer = rebalance ? address(this) : msg.sender;

        // add liquidity to Uniswap pool
        (amount0, amount1) = pool.mint(
            address(this),
            strategy.tickLower(),
            strategy.tickUpper(),
            _liquidity,
            abi.encode(MintCallbackData({payer: payer, pool: strategy.pool()}))
        );
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
                strategy.pool(),
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
            getAmountsForLiquidity(_strategy, liquidity);

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

        console.log("collect0", collect0);
        console.log("collect1", collect1);

        console.log(
            "token0 balance: ",
            IERC20(pool.token0()).balanceOf(address(this))
        );
        console.log(
            "token1 balance: ",
            IERC20(pool.token1()).balanceOf(address(this))
        );

        // transfer the tokens back
        if (amount0Real > 0) {
            IERC20(pool.token0()).transfer(msg.sender, amount0Real);
        }
        if (amount1Real > 0) {
            IERC20(pool.token1()).transfer(msg.sender, amount1Real);
        }
    }

    /*
     * @notice Rebalances the pool to new ranges
     * @param _strategy Address of the strategy
     */
    function rebalance(
        address _strategy,
        int24 _oldTickLower,
        int24 _oldTickUpper
    ) external returns (uint256 amount0, uint256 amount1) {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        // Strategy storage newStrategy = strategies[_strategy];

        // // TODO: Store past liquidity
        uint128 oldLiquidity =
            getCurrentLiquidity(strategy.pool(), _oldTickLower, _oldTickUpper);

        // if (oldLiquidity > 0) {
        int24 tickLower = strategy.tickLower();
        int24 tickUpper = strategy.tickUpper();

        // burn liquidity
        (uint256 owed0, uint256 owed1) =
            pool.burn(_oldTickLower, _oldTickUpper, oldLiquidity);

        // collect fees
        (uint128 collect0, uint128 collect1) =
            pool.collect(
                address(this),
                _oldTickLower,
                _oldTickUpper,
                type(uint128).max,
                type(uint128).max
            );

        console.log("collect0", collect0);
        console.log("collect1", collect1);

        // // mint liquidity
        // uint128 liquidity =
        //     getCurrentLiquidity(
        //         strategy.pool(),
        //         strategy.tickLower(),
        //         strategy.tickUpper()
        //     );

        uint128 liquidity = getLiquidityForAmounts(_strategy, collect0, collect1);

        mintLiquidity(_strategy, liquidity, true);

        // // store current ticks
        // newStrategy.tickLower = strategy.tickLower();
        // newStrategy.tickUpper = strategy.tickUpper();
        // }
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
     */
    function issueShare(address _strategy, uint256 _shares) internal {
        // update shares
        shares[_strategy][msg.sender] = shares[_strategy][msg.sender].add(
            uint256(_shares)
        );
        // update total shares
        totalShares[_strategy] = totalShares[_strategy].add(_shares);
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
    }

    /*
     * @notice Calculates the liquidity amount using current ranges
     * @param _strategy Address of the strategy
     * @param _amount0 Amount to be added for token0
     * @param _amount1 Amount to be added for token1
     * @return liquidity Liquidity amount derived from token amounts
     */
    function getLiquidityForAmounts(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1
    ) internal view returns (uint128 liquidity) {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());

        // get sqrtRatios required to calculate liquidity
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint160 sqrtRatioAX96 =
            TickMath.getSqrtRatioAtTick(strategy.tickLower());
        uint160 sqrtRatioBX96 =
            TickMath.getSqrtRatioAtTick(strategy.tickUpper());

        console.log("sqrtRatioAX96", sqrtRatioAX96);
        console.log("sqrtRatioBX96", sqrtRatioBX96);

        // calculate liquidity needs to be added
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            _amount0,
            _amount1
        );
    }

    /*
     * @notice Calculates the liquidity amount using current ranges
     * @param _strategy Address of the strategy
     * @param _liquidity Liquidity of the pool
     */
    function getAmountsForLiquidity(address _strategy, uint128 _liquidity)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());

        // get sqrtRatios required to calculate liquidity
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint160 sqrtRatioAX96 =
            TickMath.getSqrtRatioAtTick(strategy.tickLower());
        uint160 sqrtRatioBX96 =
            TickMath.getSqrtRatioAtTick(strategy.tickUpper());

        // calculate liquidity needs to be added
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
}
