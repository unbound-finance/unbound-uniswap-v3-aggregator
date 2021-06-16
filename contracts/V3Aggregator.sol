//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.6;

pragma abicoder v2;

// import base contracts
import "./base/AggregatorBase.sol";
import "./base/AggregatorManagement.sol";
import "./base/UniswapPoolActions.sol";

// import Unbound interfaces
import "./interfaces/IUnboundStrategy.sol";
import "./Strategy.sol";

// import libraries
import "./libraries/LiquidityHelper.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "hardhat/console.sol";

// TODO: Add Reentrancy guard
// TODO: Add Pausable functionality

contract V3Aggregator is
    AggregatorBase,
    AggregatorManagement,
    UniswapPoolActions
{
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

    event Rebalance(
        address indexed strategy,
        address indexed caller,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    );

    constructor(address _governance) {
        governance = _governance;
        feeTo = address(0);
    }

    /**
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
        // TODO: If liquidity is on hold don't pass, keep it in unused

        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        Strategy storage oldStrategy = strategies[_strategy];

        // require(strategy.initialized(), "not initilized");

        uint128 liquidityBefore =
            LiquidityHelper.getCurrentLiquidity(address(pool), _strategy);

        // index 0 will always be an primary tick
        (amount0, amount1) = mintLiquidity(
            address(pool),
            strategy.ticks(0).tickLower,
            strategy.ticks(0).tickUpper,
            _amount0,
            _amount1,
            msg.sender
        );

        uint128 liquidityAfter =
            LiquidityHelper.getCurrentLiquidity(address(pool), _strategy);

        share = issueShare(
            _strategy,
            amount0,
            amount1,
            liquidityBefore,
            liquidityAfter,
            msg.sender
        );
        // price slippage check
        require(
            amount0 >= _amount0Min && amount1 >= _amount1Min,
            "Aggregator: Slippage"
        );

        increaseUsedAmounts(_strategy, 0, amount0, amount1);

        emit AddLiquidity(_strategy, amount0, amount1);
    }

    /**
     * @notice Removes liquidity from the pool
     * @param _strategy Address of the strategy
     * @param _shares Share user wants to burn
     * @param _amount0Min Minimum amount0 user should receive
     * @param _amount1Min Minimum amount1 user should receive
     */
    function removeLiquidity(
        address _strategy,
        uint256 _shares,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external returns (uint256 amount0, uint256 amount1) {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        require(
            shares[_strategy][msg.sender] >= _shares,
            "insufficient shares"
        );
        Strategy storage oldStrategy = strategies[_strategy];

        uint256 collect0;
        uint256 collect1;

        for (uint256 i = 0; i < oldStrategy.ticks.length; i++) {
            IUnboundStrategy.Tick memory tick = oldStrategy.ticks[i];

            amount0 = tick.amount0.mul(_shares).div(totalShares[_strategy]);
            amount1 = tick.amount1.mul(_shares).div(totalShares[_strategy]);

            (amount0, amount1, ) = burnLiquidity(
                address(pool),
                _strategy,
                tick.tickLower,
                tick.tickUpper,
                amount0,
                amount1
            );

            // decrease used amounts for each tick
            decreaseUsedAmounts(_strategy, i, amount0, amount1);

            collect0 = collect0.add(amount0);
            collect1 = collect1.add(amount1);
        }

        uint256 unusedAmount0;
        uint256 unusedAmount1;

        // get unused amounts of the strategy
        (unusedAmount0, unusedAmount1) = getUnusedAmounts(_strategy);

        console.log("unused amounts");
        console.log(unusedAmount0);
        console.log(unusedAmount1);

        if (unusedAmount0 > 1000) {
            unusedAmount0 = unusedAmount0.mul(_shares).div(
                totalShares[_strategy]
            );
        }

        if (unusedAmount1 > 1000) {
            unusedAmount1 = unusedAmount1.mul(_shares).div(
                totalShares[_strategy]
            );
        }

        decreaseUnusedAmounts(_strategy, unusedAmount0, unusedAmount1);

        amount0 = collect0.add(unusedAmount0);
        amount1 = collect1.add(unusedAmount1);

        require(
            _amount0Min <= amount0 && _amount1Min <= amount1,
            "Aggregator: Slippage"
        );

        // burn shares of the user
        burnShare(_strategy, _shares, msg.sender);

        // transfer the tokens back
        if (amount0 > 1000) {
            IERC20(pool.token0()).transfer(msg.sender, amount0);
        }
        if (amount1 > 1000) {
            IERC20(pool.token1()).transfer(msg.sender, amount1);
        }

        emit RemoveLiquidity(_strategy, amount0, amount1);
    }

    /**
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

        uint256 newAmount0;
        uint256 newAmount1;

        // add blacklisting check
        require(!blacklisted[_strategy], "blacklisted");

        uint128 liquidity;

        // if hold is activated in strategy, strategy will burn the funds and hold
        if (strategy.hold()) {
            // burn liquidity
            (amount0, amount1, liquidity) = burnAllLiquidity(_strategy);

            IUnboundStrategy.Tick[] memory ticks = oldStrategy.ticks;
            // store the values contract is holding
            increaseUnusedAmounts(_strategy, amount0, amount1);
            // update amounts in the strategy
            updateStrategy(_strategy, false, 0, 0, 0);
        } else if (oldStrategy.hold) {
            // if hold has been enabled in previous update, deploy the hold
            // amount in the current ranges
            (amount0, amount1) = getUnusedAmounts(_strategy);

            // redploy the liquidity
            (newAmount0, newAmount1) = redeploy(_strategy, amount0, amount1);
        } else {
            (uint256 unusedAmount0, uint256 unusedAmount1) =
                getUnusedAmounts(_strategy);

            // remove all the liquidity
            (uint256 collect0, uint256 collect1, ) =
                burnAllLiquidity(_strategy);

            console.log("liquidity burned");
            console.log(collect0);
            console.log(collect1);

            // redploy the liquidity
            redeploy(
                _strategy,
                collect0 + unusedAmount0,
                collect1 + unusedAmount1
            );
        }
    }

    function swapAndRedeploy(address _strategy)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        Strategy storage newStrategy = strategies[_strategy];

        // don't let strategy owner swap more than they manage
        // TODO: Add a check to check total amounts managed by the liquidity
        // if (strategy.zeroToOne()) {
        //     require(
        //         uint256(strategy.swapAmount()) <=
        //             newStrategy.amount0.add(newStrategy.secondaryAmount0)
        //     );
        // } else {
        //     require(
        //         uint256(strategy.swapAmount()) <=
        //             newStrategy.amount1.add(newStrategy.secondaryAmount1)
        //     );
        // }

        uint256 amountOut;

        // swap tokens
        (amountOut) = swap(
            address(pool),
            _strategy,
            strategy.zeroToOne(),
            strategy.swapAmount(),
            strategy.allowedSlippage()
        );

        for (uint256 i = 0; i < strategy.tickLength(); i++) {
            IUnboundStrategy.Tick memory tick = strategy.ticks(i);

            // the amount going in mint liquidity should be influenced by swap amount;
            (amount0, amount1) = mintLiquidity(
                address(pool),
                tick.tickLower,
                tick.tickUpper,
                tick.amount0,
                tick.amount1,
                address(this)
            );

            updateUsedAmounts(_strategy, i, amount0, amount1);

            amount0 = amount0.add(amount0);
            amount1 = amount1.add(amount1);
        }
    }

    /**
     * @notice Redeploys the liquidity
     * @param _amount0 Amount of token0
     * @param _amount1 Amount of token1
     */
    function redeploy(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1
    ) internal returns (uint256 amount0, uint256 amount1) {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        Strategy storage newStrategy = strategies[_strategy];

        if (strategy.swapAmount() > 0) {
            (amount0, amount1) = swapAndRedeploy(_strategy);

            // unused amounts
            amount0 = _amount0 - amount0;
            amount1 = _amount1 - amount1;

            // update unused amounts
            updateUnusedAmounts(_strategy, amount0, amount1);
        } else {
            uint256 totalAmount0;
            uint256 totalAmount1;

            for (uint256 i = 0; i < strategy.tickLength(); i++) {
                IUnboundStrategy.Tick memory tick = strategy.ticks(i);

                // the amount going in mint liquidity should be influenced by swap amount;
                (amount0, amount1) = mintLiquidity(
                    address(pool),
                    tick.tickLower,
                    tick.tickUpper,
                    tick.amount0,
                    tick.amount1,
                    address(this)
                );

                updateUsedAmounts(_strategy, i, amount0, amount1);

                console.log("deployed");
                console.log(amount0);
                console.log(amount1);

                totalAmount0 = totalAmount0.add(amount0);
                totalAmount1 = totalAmount1.add(amount1);
            }

            console.log("total deployed");
            console.log(totalAmount0);
            console.log(totalAmount1);

            // to calculate unused amount substract the deployed amounts from original amounts
            amount0 = _amount0 - totalAmount0;
            amount1 = _amount1 - totalAmount1;

            console.log("unused amounts");
            console.log(amount0);
            console.log(amount1);

            // update unused amounts
            updateUnusedAmounts(_strategy, amount0, amount1);
        }

        // // emit event
        // emit Rebalance(
        //     _strategy,
        //     msg.sender,
        //     amount0,
        //     amount1,
        //     strategy.tickLower(),
        //     strategy.tickUpper()
        // );
    }

    function getTicks(address _strategy)
        public
        view
        returns (IUnboundStrategy.Tick[] memory)
    {
        Strategy storage strategy = strategies[_strategy];

        return strategy.ticks;
    }
}
