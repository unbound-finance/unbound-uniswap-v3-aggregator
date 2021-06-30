pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "hardhat/console.sol";

contract TestSwap is IUniswapV3SwapCallback {
    address pool_;

    struct SwapCallbackData {
        address user;
        bool zeroToOne;
    }

    // swaps with exact input single functionality
    function swap(
        address _pool,
        bool _zeroToOne,
        int256 _amount,
        uint160 _sqrtPriceLimitX96
    ) external returns (uint256 amountOut) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        (amountOut) = swapExactInput(
            _pool,
            _zeroToOne,
            _amount,
            _sqrtPriceLimitX96
        );

        (uint160 newSqrtRatioX96, , , , , , ) = pool.slot0();

        uint160 difference = sqrtRatioX96 < newSqrtRatioX96
            ? sqrtRatioX96 / newSqrtRatioX96
            : newSqrtRatioX96 / sqrtRatioX96;
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
        address _user = msg.sender;

        (int256 amount0, int256 amount1) = pool.swap(
            address(this),
            _zeroToOne,
            _amount,
            sqrtPriceLimitX96,
            abi.encode(SwapCallbackData({user: _user, zeroToOne: _zeroToOne}))
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
            TransferHelper.safeTransferFrom(
                pool.token0(),
                decoded.user,
                msg.sender,
                uint256(amount0)
            );
        } else {
            TransferHelper.safeTransferFrom(
                pool.token1(),
                decoded.user,
                msg.sender,
                uint256(amount1)
            );
        }
    }
}
