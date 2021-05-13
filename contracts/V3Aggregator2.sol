//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// How it works:
// 1. Users deposit the tokens using stablecoin
// 2. The deposited stablecoin is stored as unused stablecoins
// 3. At the time of rebalance the tokens are swapped to provide liquidity in the V3

// TODO: Move to different file
interface UnboundStrategy {
    function pool() public view returns (address);

    function stablecoin() public view returns (address);

    function tickLower() public view returns (uint256);

    function tickUpper() public view returns (uint256);

    function range0() public view returns (uint256);

    function range1() public view returns (uint256);

    function fee() public view returns (uint256);
}

contract UnboundUniswapV3Aggregator2 {
    using SafeMath for uint256;

    // store deposits
    mapping(address => uint256) deposits;

    function addLiquidity(address _strategy, uint256 _amount) external {
        UnboundStrategy strategy = UnboundStrategy(_strategy);
        IERC20 stablecoin = IERC20(strategy.stablecoin());

        // check if the user has sufficient balance
        require(stablecoin.balanceOf(msg.sender) > _amount, "invalid amount");

        // transfer the stablecoin to the user
        stablecoin.transferFrom(msg.sender, address(this), _amount);

        // update deposits and unused mappings
        deposits[msg.sender] = deposits[msg.sender].add(_amount);
    }

    function removeLiquidity() external {
        
    }

    function rebalance(address _strategy) external {
        UnboundStrategy strategy = UnboundStrategy(_strategy);
        IERC20 stablecoin = IERC20(strategy.stablecoin());
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());

        uint256 burnLiquidityAmount = 0;
        burnLiquidity(strategy.tickLower(), strategy.tickUpper(), liquidity);

        uint256 totalStablecoin = stablecoin.balanceOf(address(this));
        (, int24 currentPrice, , , , , ) = pool.slot0();

        // Formula to calculate Dai required to buy weth using ranges
        // TODO: might need to normalise
        uint256 buyPrice =
            sqrt(currentPrice).mul(
                sqrt(currentPrice).sub(sqrt(strategy.range0())).div(
                    uint256(1).sub(sqrt(currentPrice.div(strategy.range1())))
                )
            );

        // calculate number of other tokens needs to be swapped with the current stablecoin pool
        uint256 swapAmount =
            totalStablecoin.div(uint256(currentPrice).add(buyPrice));

        // true if swap is token0 to token1 and false if swap is token1 to token0
        bool zeroForOne =
            (strategy.stablecoin() == pool.token0()) ? true : false;

        // Swap
        pool.swap(address(this), zeroForOne, swapAmount, 0, 0);

        // TODO: Figure out how to calculate liquidity
        uint256 mintLiquidityAmount = 0;
        mintLiquidity(strategy.tickLower(), strategy.tickUpper(), mintLiquidityAmount);
    }

    // Returns square root using Babylon method
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
    

    function getSwapAmount() internal pure returns (uint256 amount) {}


    function mintLiquidity(
        int112 _tickLower,
        int112 _tickUpper,
        uint256 _liquidity
    ) internal {
        // add the liquidity to V3 pool
        pool.mint(address(this), _tickLower, _tickUpper, _liquidity, 0);
    }

    function burnLiquidity(
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _liquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        if (liquidity > 0) {
            // Burn liquidity
            (uint256 owed0, uint256 owed1) = pool.burn(tickLower, tickUpper, liquidity);

            // Collect amount owed
            uint128 collect0 = type(uint128).max;
            uint128 collect1 = type(uint128).max;
            if (collect0 > 0 || collect1 > 0) {
                (amount0, amount1) = pool.collect(address(this), tickLower, tickUpper, collect0, collect1);
            }
        }
    }
}
