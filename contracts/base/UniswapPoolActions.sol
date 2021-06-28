//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

// import libraries
import "../libraries/LiquidityHelper.sol";

// import DefiEdge interfaces
import "../interfaces/IStrategy.sol";

import "../base/AggregatorManagement.sol";


contract UniswapPoolActions is
    AggregatorManagement,
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback
{
    using SafeMath for uint256;

    // used as temporary variable to verify the pool
    address pool_;

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

        // set temparary variable for callback verification
        pool_ = _pool;
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
        // substract 100 GWEI to counter with precision error coming from Uniswap
        liquidity = LiquidityHelper.getLiquidityForAmounts(
            _pool,
            _tickLower,
            _tickUpper,
            _amount0 > 100 ? _amount0.sub(100) : 0,
            _amount1 > 100 ? _amount1.sub(100) : 0
        );

        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        uint256 tokensBurned0;
        uint256 tokensBurned1;

        // burn liquidity
        if (liquidity > 0) {
            (tokensBurned0, tokensBurned1) = pool.burn(
                _tickLower,
                _tickUpper,
                liquidity
            );
        }

        (, , , uint128 tokensOwed0, uint128 tokensOwed1) =
            pool.positions(
                PositionKey.compute(address(this), _tickLower, _tickUpper)
            );

        // collect fees
        (collect0, collect1) = pool.collect(
            address(this),
            _tickLower,
            _tickUpper,
            uint128(tokensOwed0),
            uint128(tokensOwed1)
        );

        emit FeesClaimed(
            _strategy,
            _pool,
            collect0 > _amount0 ? uint256(collect0).sub(_amount0) : 0,
            collect1 > _amount1 ? uint256(collect1).sub(_amount1) : 0
        );
    }

    /**
     * @notice Burns all the liquidity and collects fees
     * @param _strategy Address of the strategy
     */
    function burnAllLiquidity(address _strategy)
        internal
        returns (
            uint256 collect0,
            uint256 collect1,
            uint128 liquidity
        )
    {
        IStrategy strategy = IStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        Strategy storage strategySnapshot = strategies[_strategy];

        for (uint256 i = 0; i < strategySnapshot.ticks.length; i++) {
            IStrategy.Tick memory tick = strategySnapshot.ticks[i];

            // Burn liquidity for range order
            (uint256 amount0, uint256 amount1, uint128 burnedLiquidity) =
                burnLiquidity(
                    address(pool),
                    address(strategy),
                    tick.tickLower,
                    tick.tickUpper,
                    tick.amount0,
                    tick.amount1
                );

            collect0 = collect0.add(amount0);
            collect1 = collect1.add(amount1);
            liquidity = liquidity + burnedLiquidity;
        }
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
        IStrategy strategy = IStrategy(_strategy);

        // TODO: Support partial slippage
        uint160 sqrtPriceLimitX96 =
            _zeroToOne
                ? sqrtRatioX96 - (sqrtRatioX96 * _allowedSlippage) / 1e8
                : sqrtRatioX96 + (sqrtRatioX96 * _allowedSlippage) / 1e8;

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
                uint256(difference) <= strategy.allowedPriceSlippage().div(1e8)
            );
        }
    }

    function swapExactInput(
        address _pool,
        bool _zeroToOne,
        int256 _amount,
        uint160 sqrtPriceLimitX96
    ) internal returns (uint256 amountOut) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        // set temparary variable for callback verification
        pool_ = _pool;

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
        // check if the callback is received from Uniswap V3 Pool
        require(msg.sender == pool_);
        IUniswapV3Pool pool = IUniswapV3Pool(pool_);
        delete pool_;

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
        require(msg.sender == pool_);
        IUniswapV3Pool pool = IUniswapV3Pool(pool_);
        delete pool_;

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

    /**
     * @dev Get the liquidity between current ticks
     * @param _pool Address of the pool
     * @param _strategy Address of the strategy
     */
    function getCurrentLiquidityWithFees(address _pool, address _strategy)
        internal
        returns (uint128 liquidity)
    {
        IStrategy strategy = IStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        for (uint256 i = 0; i < strategy.tickLength(); i++) {
            IStrategy.Tick memory tick = strategy.ticks(i);

            uint128 fees;

            // update fees earned in Uniswap pool
            // Uniswap recalculates the fees and updates the variables when amount is passed as 0
            if (liquidity > 0) {
                pool.burn(tick.tickLower, tick.tickUpper, 0);
            }

            (
                uint128 currentLiquidity,
                ,
                ,
                uint128 tokensOwed0,
                uint128 tokensOwed1
            ) =
                pool.positions(
                    PositionKey.compute(
                        address(this),
                        tick.tickLower,
                        tick.tickUpper
                    )
                );

            // convert collected fees in form of liquidity
            fees = LiquidityHelper.getLiquidityForAmounts(
                _pool,
                tick.tickLower,
                tick.tickUpper,
                tokensOwed0,
                tokensOwed1
            );

            liquidity = liquidity + currentLiquidity + fees;
        }
    }
}
