//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

// import libraries
import "../libraries/LiquidityHelper.sol";

// import Unbound interfaces
import "../interfaces/IUnboundStrategy.sol";

import "../base/AggregatorManagement.sol";

contract UniswapPoolActions is
    AggregatorManagement,
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback
{
    event FeesClaimed(
        address indexed pool,
        address indexed strategy,
        uint256 amount0,
        uint256 amount1
    );

    struct MintCallbackData {
        address payer;
        address pool;
    }

    struct SwapCallbackData {
        address pool;
        bool zeroToOne;
    }

    /**
     * @notice Mints liquidity from V3 Pool
     * @param _pool Address of the pool
     * @param _tickLower Lower tick
     * @param _tickUpper Upper tick
     * @param _amount0 Amount of token0
     * @param _amount1 Amount of token1
     * @param _payer Address which is adding the liquidity
     */
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
            LiquidityHelper.getLiquidityForAmounts(
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

    /**
     * @notice Burns liquidity in the given range
     * @param _pool Address of the pool
     * @param _strategy Address of the strategy
     * @param _tickLower Lower Tick
     * @param _tickUpper Upper Tick
     * @param _amount0 Amount 0 to burn
     * @param _amount1 Amount to burn
     */
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
        liquidity = LiquidityHelper.getLiquidityForAmounts(
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

        (uint128 fee0, uint128 fee1) =
            LiquidityHelper.getAccumulatedFees(_pool, _tickLower, _tickUpper);

        // collect fees
        (collect0, collect1) = pool.collect(
            address(this),
            _tickLower,
            _tickUpper,
            uint128(_amount0) + fee0,
            uint128(_amount1) + fee1
        );

        emit FeesClaimed(
            _strategy,
            _pool,
            uint256(collect0) - owed0,
            uint256(collect1) - owed1
        );
    }

    /**
     * @notice Burns all the liquidity and collects fees
     * @param _strategy Address of the strategy
     */
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

    // swaps with exact input single functionality
    function swap(
        address _pool,
        address _strategy,
        bool _zeroToOne,
        int256 _amount,
        uint160 _allowedSlippage
    ) internal returns (uint256 amountOut) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);

        // TODO: Support partial slippage
        uint160 sqrtPriceLimitX96 =
            _zeroToOne
                ? sqrtRatioX96 - (sqrtRatioX96 * _allowedSlippage) / 10000
                : sqrtRatioX96 + (sqrtRatioX96 * _allowedSlippage) / 10000;

        (amountOut) = swapExactInput(
            _pool,
            _zeroToOne,
            _amount,
            sqrtPriceLimitX96
        );

        (uint160 newSqrtRatioX96, , , , , , ) = pool.slot0();

        uint160 difference =
            sqrtRatioX96 < newSqrtRatioX96
                ? sqrtRatioX96 / newSqrtRatioX96
                : newSqrtRatioX96 / sqrtRatioX96;

        if (strategy.allowedPriceSlippage() > 0) {
            // check price P slippage
            require(
                uint256(difference) <= strategy.allowedPriceSlippage() / 1e6
            );
        }
    }

    // TODO: If on hold in add liquidity add to hold
    function swapExactInput(
        address _pool,
        bool _zeroToOne,
        int256 _amount,
        uint160 sqrtPriceLimitX96
    ) internal returns (uint256 amountOut) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        (int256 amount0, int256 amount1) =
            pool.swap(
                address(this),
                _zeroToOne,
                _amount,
                sqrtPriceLimitX96,
                abi.encode(
                    SwapCallbackData({pool: _pool, zeroToOne: _zeroToOne})
                )
            );

        return uint256(-(_zeroToOne ? amount1 : amount0));
    }

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3SwapCallback(
        int256 amount0,
        int256 amount1,
        bytes calldata data
    ) external override {
        SwapCallbackData memory decoded = abi.decode(data, (SwapCallbackData));

        uint256 amt0 = uint256(amount0);
        uint256 amt1 = uint256(-amount1);

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
                pool.token1(),
                msg.sender,
                uint256(amount1)
            );
        }
    }

    /**
     * @dev Callback for Uniswap V3 pool.
     */
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
}
