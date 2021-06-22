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
        uint256 _amount1Min,
        uint256 _minShare
    )
        external
        returns (
            // uint256 _minShare
            uint256 share,
            uint256 amount0,
            uint256 amount1
        )
    {
        // TODO: If liquidity is on hold don't pass, keep it in unused
        // TODO: Figure out how to make use of fees while issuing shares

        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        Strategy storage oldStrategy = strategies[_strategy];

        // require(strategy.initialized(), "not initilized");

        // get total number of assets under management
        // (amount0, amount1) = getAUM(_strategy);

        // get liquidity before adding the new liqudiity
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

        // get liquidity value after adding liquidity of the user
        uint128 liquidityAfter =
            LiquidityHelper.getCurrentLiquidity(address(pool), _strategy);

        // issue share based on the liquidity added
        share = issueShare(
            _strategy,
            amount0,
            amount1,
            liquidityBefore,
            liquidityAfter,
            msg.sender
        );

        // prevent front running of strategy fee
        require(share >= _minShare, "minimum share check failed");

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
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 amountOut
        )
    {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());
        Strategy storage newStrategy = strategies[_strategy];

        // get total assets under management of the strategy
        (uint256 totalAmount0, uint256 totalAmount1) = getAUM(_strategy);

        // check that swap amount should not exceed amounts managed
        // TODO: Rethink about this check
        if (strategy.zeroToOne()) {
            require(strategy.swapAmount() <= totalAmount0);
        } else {
            require(strategy.swapAmount() <= totalAmount1);
        }

        // swap tokens
        (amountOut) = swap(
            address(pool),
            _strategy,
            strategy.zeroToOne(),
            int256(strategy.swapAmount()),
            strategy.allowedSlippage()
        );

        uint256 deployedAmount0;
        uint256 deployedAmount1;

        // delete old tick data
        delete newStrategy.ticks;

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

            // push new tick to the ticks array
            IUnboundStrategy.Tick memory newTick;
            newTick.tickLower = tick.tickLower;
            newTick.tickUpper = tick.tickUpper;
            newTick.amount0 = amount0;
            newTick.amount1 = amount1;
            newStrategy.ticks.push(newTick);

            // add to the amounts outside the loop
            deployedAmount0 = deployedAmount0.add(amount0);
            deployedAmount1 = deployedAmount1.add(amount1);
        }

        amount0 = deployedAmount0;
        amount1 = deployedAmount1;

        // // check if the total amounts are always less than the managed
        // if(strategy.zeroToOne()) {
        //     amount0 = deployedAmount0.add(strategy.swapAmount());
        //     amount1 = deployedAmount1.sub(amountOut);
        // }
        // else {
        //     amount0 = deployedAmount0.sub(amountOut);
        //     amount1 = deployedAmount1.add(strategy.swapAmount());
        // }
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

        console.log("burned amount");
        console.log(_amount0);
        console.log(_amount1);

        if (strategy.swapAmount() > 0) {
            uint256 amountOut;

            (amount0, amount1, amountOut) = swapAndRedeploy(_strategy);

            console.log("total deployed after swap");
            console.log("amount0", amount0);
            console.log("amount1", amount1);
            console.log("swapAmount", strategy.swapAmount());
            console.log("amountOut", amountOut);

            if (strategy.zeroToOne()) {
                if (amount0 >= _amount0.sub(strategy.swapAmount())) {
                    amount0 = 0;
                } else {
                    amount0 = _amount0.sub(strategy.swapAmount()).sub(amount0);
                }

                if (amount1 >= _amount1.add(amountOut)) {
                    amount1 = 0;
                } else {
                    amount1 = _amount1.add(amountOut).sub(amount1);
                }
            } else {
                if (amount1 >= _amount1.sub(strategy.swapAmount())) {
                    amount1 = 0;
                } else {
                    amount1 = _amount1.sub(strategy.swapAmount()).sub(amount1);
                }

                if (amount0 >= _amount0.add(amountOut)) {
                    amount0 = 0;
                } else {
                    amount0 = _amount1.add(amountOut).sub(amount0);
                }
            }

            console.log("unused");
            console.log(amount0);
            console.log(amount1);
            // update unused amounts
            updateUnusedAmounts(_strategy, amount0, amount1);
        } else {
            uint256 totalAmount0;
            uint256 totalAmount1;

            delete newStrategy.ticks;

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

                // TODO: Move to different file later
                IUnboundStrategy.Tick memory newTick;
                newTick.tickLower = tick.tickLower;
                newTick.tickUpper = tick.tickUpper;
                newTick.amount0 = amount0;
                newTick.amount1 = amount1;
                newStrategy.ticks.push(newTick);

                // update total amounts
                totalAmount0 = totalAmount0.add(amount0);
                totalAmount1 = totalAmount1.add(amount1);
            }

            // to calculate unused amount substract the deployed amounts from original amounts
            amount0 = _amount0.sub(totalAmount0);
            amount1 = _amount1.sub(totalAmount1);

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

    /**
     * @notice Gets assets under management for specific strategy
     * @param _strategy Address of the strategy contract
     */
    function getAUM(address _strategy)
        public
        view
        returns (uint256 amount0, uint256 amount1)
    {
        Strategy memory strategy = strategies[_strategy];
        UnusedAmounts memory unusedAmounts = unused[_strategy];

        uint256 totalAmount0;
        uint256 totalAmount1;

        // add amounts from different ranges
        for (uint256 i = 0; i < strategy.ticks.length; i++) {
            IUnboundStrategy.Tick memory tick = strategy.ticks[i];
            totalAmount0 = totalAmount0.add(tick.amount0);
            totalAmount1 = totalAmount1.add(tick.amount1);
        }

        // add unused amounts
        amount0 = totalAmount0.add(unusedAmounts.amount0);
        amount1 = totalAmount1.add(unusedAmounts.amount1);
    }
}
