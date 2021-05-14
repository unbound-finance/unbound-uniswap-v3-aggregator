//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.6;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

// How it works:
// 1. Users deposit the tokens using stablecoin
// 2. The deposited stablecoin is stored as unused stablecoins
// 3. At the time of rebalance the tokens are swapped to provide liquidity in the V3

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

contract UnboundUniswapV3Aggregator2 {
    using SafeMath for uint256;

    // store deposits
    mapping(address => uint256) deposits;

    // store stake points
    // user => strategy address => points
    mapping(address => mapping(address => uint256)) userStakePoints;

    // strategy => totalPoints
    mapping(address => uint256) totalStakePointsOfStrategy;

    function addLiquidity(address _strategy, uint256 _amount) external {
        UnboundStrategy strategy = UnboundStrategy(_strategy);
        IERC20 stablecoin = IERC20(strategy.stablecoin());

        // check if the user has sufficient balance
        require(stablecoin.balanceOf(msg.sender) > _amount, "invalid amount");

        // transfer the stablecoin from the user
        stablecoin.transferFrom(msg.sender, address(this), _amount);

        // update deposits and unused mappings
        deposits[msg.sender] = deposits[msg.sender].add(_amount);

        // we need to track total value of liquidity within the strategy, then we can calculate amount of stake points

        // stake points to mint = _amount * totalStakePointsOfStrategy[_strategy] / total Value of Liquidity

        // add the liquidity after issuing stake points
    }

    function removeLiquidity(address _strategy, uint256 _stakeToWithdraw)
        external
    {
        UnboundStrategy strategy = UnboundStrategy(_strategy);
        IERC20 stablecoin = IERC20(strategy.stablecoin());

        uint256 valueToReturn = 0;
        // uint256 valueToReturn =
        //     _stakeToWithdraw.mul(totalValue).div(
        //         totalStakePointsOfStrategy[_strategy]
        //     );

        // remove amount of liquidity equal to valueToReturn

        userStakePoints[_strategy][msg.sender] = userStakePoints[_strategy][
            msg.sender
        ]
            .sub(_stakeToWithdraw);
        totalStakePointsOfStrategy[_strategy] = totalStakePointsOfStrategy[
            _strategy
        ]
            .sub(_stakeToWithdraw);
    }

    // Strategy Owner Functions
    function rebalance(address _strategy) external {
        UnboundStrategy strategy = UnboundStrategy(_strategy);
        IERC20 stablecoin = IERC20(strategy.stablecoin());

        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());

        IERC20 token0 = IERC20(pool.token0());
        IERC20 token1 = IERC20(pool.token1());

        uint128 burnLiquidityAmount =
            liquidityForAmounts(
                _strategy,
                strategy.tickLower(),
                strategy.tickUpper(),
                token0.balanceOf(address(this)),
                token1.balanceOf(address(this))
            );

        burnLiquidity(
            _strategy,
            strategy.tickLower(),
            strategy.tickUpper(),
            burnLiquidityAmount
        );

        uint256 totalStablecoin = stablecoin.balanceOf(address(this));
        (, int24 currentPrice, , , , , ) = pool.slot0();

        // Formula to calculate Dai required to buy weth using ranges
        // TODO: might need to normalise
        uint256 buyPrice =
            sqrt(uint256(currentPrice)).mul( // why do we multiply the sqrt by the sqrt here?
                sqrt(uint256(currentPrice)).sub(sqrt(strategy.range0())).div(
                    uint256(1).sub(
                        sqrt(uint256(currentPrice) / strategy.range1())
                    ) // isn't this going to always revert unless root(currentprice/range1) = 0?
                )
            );

        // // calculate number of other tokens needs to be swapped with the current stablecoin pool
        // int256 swapAmount =
        //     totalStablecoin.div(uint256(currentPrice).add(buyPrice)); // not sure what this line does...

        // true if swap is token0 to token1 and false if swap is token1 to token0
        bool zeroForOne =
            (strategy.stablecoin() == pool.token0()) ? true : false;

        // Swap
        // pool.swap(address(this), zeroForOne, swapAmount, 0);

        // TODO: Figure out how to calculate liquidity
        uint128 mintLiquidityAmount =
            liquidityForAmounts(
                _strategy,
                strategy.tickLower(),
                strategy.tickUpper(),
                token0.balanceOf(address(this)),
                token1.balanceOf(address(this))
            );

        mintLiquidity(
            _strategy,
            strategy.tickLower(),
            strategy.tickUpper(),
            mintLiquidityAmount
        );
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

    function mintLiquidity(
        address _strategy,
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _liquidity
    ) internal {
        UnboundStrategy strategy = UnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        // add the liquidity to V3 pool
        pool.mint(
            address(this),
            _tickLower,
            _tickUpper,
            _liquidity,
            abi.encode(address(this))
        );
    }

    function burnLiquidity(
        address _strategy,
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _liquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        UnboundStrategy strategy = UnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        if (_liquidity > 0) {
            // Burn liquidity
            (uint256 owed0, uint256 owed1) =
                pool.burn(_tickLower, _tickUpper, _liquidity);

            // Collect amount owed
            uint128 collect0 = type(uint128).max; // no idea what these lines do...
            uint128 collect1 = type(uint128).max; // where is the type() function? Looks like there is nothing updating these numbers
            if (collect0 > 0 || collect1 > 0) {
                (amount0, amount1) = pool.collect(
                    address(this),
                    _tickLower,
                    _tickUpper,
                    collect0,
                    collect1
                );
            }
        }
    }

    function liquidityForAmounts(
        address _strategy,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0,
        uint256 _amount1
    ) internal view returns (uint128) {
        UnboundStrategy strategy = UnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        return
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(_tickLower),
                TickMath.getSqrtRatioAtTick(_tickUpper),
                _amount0,
                _amount1
            );
    }
}
