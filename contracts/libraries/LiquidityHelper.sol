pragma solidity ^0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";

library LiquidityHelper {
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
    ) external view returns (uint256 amount0, uint256 amount1) {
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

    // TODO: Change temporary external external functions to internal
    // TODO: Consider liquidity only from the strategy in it
    /// @dev Get the liquidity between current ticks
    /// @param _pool Address of the pool
    /// @param _tickLower Lower tick of the range
    /// @param _tickUpper Upper tick of the range
    function getCurrentLiquidity(
        address _pool,
        int24 _tickLower,
        int24 _tickUpper,
        int24 _secondaryTickLower,
        int24 _secondaryTickUpper
    ) internal view returns (uint128 liquidity) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        // get current liquidity for range order
        (uint128 rangeOrderLiquidity, , , , ) =
            pool.positions(
                PositionKey.compute(address(this), _tickLower, _tickUpper)
            );

        // get current liquidity for limit order
        (uint128 limitOrderLiquidity, , , , ) =
            pool.positions(
                PositionKey.compute(
                    address(this),
                    _secondaryTickLower,
                    _secondaryTickUpper
                )
            );

        // add both liquiditys
        liquidity = rangeOrderLiquidity + limitOrderLiquidity;
    }
}
