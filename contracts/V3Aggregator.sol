//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// TODO: Move to different file
interface UnboundStrategy {
    function pool() external view returns (address);

    function stablecoin() external view returns (address);

    function tickLower() external view returns (int24);

    function tickUpper() external view returns (int24);

    function range0() external view returns (uint256);

    function range1() external view returns (uint256);

    function fee() external view returns (uint256);
}

contract V3Aggregator {
    using SafeMath for uint256;
    using SafeCast for uint256;

    // store total stake points
    uint256 public totalShare;

    mapping(address => mapping(address => uint256)) public shares;

    // mapping of strategies with their total share
    mapping(address => uint256) totalShares;

    struct MintCallbackData {
        address payer;
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
        UnboundStrategy strategy = UnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());

        uint128 liquidity =
            getLiquidityForAmounts(_strategy, _amount0, _amount1);

        uint128 liquidityBefore = getCurrentLiquidity(_strategy);

        // add liquidity to Uniswap pool
        (amount0, amount1) = pool.mint(
            address(this),
            strategy.tickLower(),
            strategy.tickUpper(),
            liquidity,
            abi.encode(MintCallbackData({payer: msg.sender}))
        );

        uint128 liquidityAfter = getCurrentLiquidity(_strategy);

        // calculate shares
        share = uint256(liquidityAfter)
            .sub(liquidityBefore)
            .mul(totalShare)
            .div(liquidityBefore);

        // update shares w.r.t. strategy
        issueShare(_strategy, share);

        // price slippage check
        require(
            amount0 >= _amount0Min && amount1 >= _amount1Min,
            "Aggregator: Slippage"
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
        UnboundStrategy strategy = UnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());

        uint128 liquidity =
            _shares
                .mul(getCurrentLiquidity(_strategy))
                .div(totalShares[_strategy])
                .toUint128();

        (uint256 amount0, uint256 amount1) =
            getAmountsForLiquidity(_strategy, liquidity);

        require(
            _amount0Min <= amount0 && _amount1Min <= amount1,
            "Aggregator: Slippage"
        );

        (uint256 amount0Real, uint256 amount1Real) =
            pool.burn(strategy.tickLower(), strategy.tickUpper(), liquidity);

        require(
            _amount0Min <= amount0Real && _amount1Min <= amount1Real,
            "Aggregator: Slippage"
        );

        burnShare(_strategy, _shares);

        IERC20(pool.token0()).transfer(msg.sender, amount0Real);
        IERC20(pool.token1()).transfer(msg.sender, amount1Real);
    }

    /*
     * @notice Rebalances the pool to new ranges
     * @param _strategy Address of the strategy
     */
    function rebalance(address _strategy)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        UnboundStrategy strategy = UnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());

        // TODO: Store past liquidity
        uint128 liquidity = getCurrentLiquidity(_strategy);

        if (liquidity > 0) {
            int24 tickLower = strategy.tickLower();
            int24 tickUpper = strategy.tickUpper();

            // burn liquidity
            (uint256 owed0, uint256 owed1) =
                pool.burn(tickLower, tickUpper, liquidity);

            // collect fees
            (uint128 collect0, uint128 collect1) =
                pool.collect(
                    address(this),
                    tickLower,
                    tickUpper,
                    type(uint128).max,
                    type(uint128).max
                );

            // add liquidity to Uniswap pool
            (amount0, amount1) = pool.mint(
                address(this),
                tickLower,
                tickUpper,
                liquidity,
                abi.encode(MintCallbackData({payer: msg.sender}))
            );
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
        UnboundStrategy strategy = UnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());

        // get sqrtRatios required to calculate liquidity
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint160 sqrtRatioAX96 =
            TickMath.getSqrtRatioAtTick(strategy.tickLower());
        uint160 sqrtRatioBX96 =
            TickMath.getSqrtRatioAtTick(strategy.tickUpper());

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
        UnboundStrategy strategy = UnboundStrategy(_strategy);
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
     */
    function getCurrentLiquidity(address _strategy)
        internal
        view
        returns (uint128 liquidity)
    {
        UnboundStrategy strategy = UnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());

        (liquidity, , , , ) = pool.positions(
            PositionKey.compute(
                address(this),
                strategy.tickLower(),
                strategy.tickUpper()
            )
        );
    }
}
