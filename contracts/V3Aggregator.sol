//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.6;

pragma abicoder v2;

// import base contracts
import "./base/AggregatorBase.sol";
import "./base/AggregatorManagement.sol";
import "./base/UniswapPoolActions.sol";

// import DefiEdge interfaces
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

    event Rebalance(address indexed strategy, IUnboundStrategy.Tick[] ticks);

    // TODO: Remove this later, only for testing on Kovan
    uint256 public recentlyBurned0;
    uint256 public recentlyBurned1;

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
        // require(strategy.initialized(), "not initilized");

        // get total number of assets under management
        // (amount0, amount1) = getAUM(_strategy);

        // get liquidity before adding the new liqudiity
        uint128 liquidityBefore = getCurrentLiquidityWithFees(
            address(pool),
            _strategy
        );

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
        uint128 liquidityAfter = LiquidityHelper.getCurrentLiquidity(
            address(pool),
            _strategy
        );

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
        Strategy storage strategySnapshot = strategies[_strategy];

        uint256 collect0;
        uint256 collect1;

        if (strategySnapshot.ticks.length != 0) {
            for (uint256 i = 0; i < strategySnapshot.ticks.length; i++) {
                IUnboundStrategy.Tick memory tick = strategySnapshot.ticks[i];

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
        }

        uint256 unusedAmount0;
        uint256 unusedAmount1;

        // TODO: Make sure get unused do not underflow
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
            TransferHelper.safeTransfer(pool.token0(), msg.sender, amount0);
        }
        if (amount1 > 1000) {
            TransferHelper.safeTransfer(pool.token1(), msg.sender, amount1);
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
        Strategy storage strategySnapshot = strategies[_strategy];

        // add blacklisting check
        // TODO: Remove this check
        require(!blacklisted[_strategy], "blacklisted");

        uint128 liquidity;

        // if hold is activated in strategy, strategy will burn the funds and hold
        if (strategy.hold()) {
            // burn liquidity
            (amount0, amount1, liquidity) = burnAllLiquidity(_strategy);

            // store the values contract  is holding
            increaseUnusedAmounts(_strategy, amount0, amount1);

            // tell contract that funds are on hold
            strategySnapshot.hold = true;

            // delete the old ticks data
            delete strategySnapshot.ticks;
        } else if (strategySnapshot.hold) {
            // if hold has been enabled in previous update, deploy the hold
            // amount in the current ranges
            (amount0, amount1) = getUnusedAmounts(_strategy);

            strategySnapshot.hold = strategy.hold();

            // redploy the liquidity
            redeploy(_strategy, amount0, amount1);
        } else {
            (uint256 unusedAmount0, uint256 unusedAmount1) = getUnusedAmounts(
                _strategy
            );

            // remove all the liquidity
            (uint256 collect0, uint256 collect1, ) = burnAllLiquidity(
                _strategy
            );

            // redploy the liquidity
            redeploy(
                _strategy,
                collect0.add(unusedAmount0),
                collect1.add(unusedAmount1)
            );

            // emit rebalance event
            emit Rebalance(_strategy, strategySnapshot.ticks);
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
        Strategy storage strategySnapshot = strategies[_strategy];

        // get total assets under management of the strategy
        (uint256 totalAmount0, uint256 totalAmount1) = getAUM(_strategy);

        // check that swap amount should not exceed amounts managed
        if (strategy.zeroToOne()) {
            require(
                strategy.swapAmount() <= totalAmount0,
                "swap amounts exceed"
            );
        } else {
            require(
                strategy.swapAmount() <= totalAmount1,
                "swap amounts exceed"
            );
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
        delete strategySnapshot.ticks;

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
            strategySnapshot.ticks.push(
                IUnboundStrategy.Tick(
                    amount0,
                    amount1,
                    tick.tickLower,
                    tick.tickUpper
                )
            );

            // add to the amounts outside the loop
            deployedAmount0 = deployedAmount0.add(amount0);
            deployedAmount1 = deployedAmount1.add(amount1);
        }

        // return total deployed amounts
        amount0 = deployedAmount0;
        amount1 = deployedAmount1;
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
        Strategy storage strategySnapshot = strategies[_strategy];

        if (strategy.swapAmount() > 0) {
            uint256 amountOut;

            (amount0, amount1, amountOut) = swapAndRedeploy(_strategy);

            // calculate unused amounts
            if (strategy.zeroToOne()) {
                // if deployed amount0 is greater than burned amount0
                // substract swap amount from burned amount0
                if (amount0 >= _amount0.sub(strategy.swapAmount())) {
                    amount0 = 0;
                } else {
                    amount0 = _amount0.sub(strategy.swapAmount()).sub(amount0);
                }

                // add the amount after swapped to burned amount
                if (amount1 >= _amount1.add(amountOut)) {
                    amount1 = 0;
                } else {
                    amount1 = _amount1.add(amountOut).sub(amount1);
                }
            } else {
                // if the swap is happening in reverse direction
                // .. substract swap amount from amount1
                if (amount1 >= _amount1.sub(strategy.swapAmount())) {
                    amount1 = 0;
                } else {
                    amount1 = _amount1.sub(strategy.swapAmount()).sub(amount1);
                }

                if (amount0 >= _amount0.add(amountOut)) {
                    amount0 = 0;
                } else {
                    amount0 = _amount0.add(amountOut).sub(amount0);
                }
            }

            // update unused amounts
            updateUnusedAmounts(_strategy, amount0, amount1);
        } else {
            uint256 totalAmount0;
            uint256 totalAmount1;

            delete strategySnapshot.ticks;

            for (uint256 i = 0; i < strategy.tickLength(); i++) {
                IUnboundStrategy.Tick memory tick = strategy.ticks(i);

                (amount0, amount1) = mintLiquidity(
                    address(pool),
                    tick.tickLower,
                    tick.tickUpper,
                    tick.amount0,
                    tick.amount1,
                    address(this)
                );

                strategySnapshot.ticks.push(
                    IUnboundStrategy.Tick(
                        amount0,
                        amount1,
                        tick.tickLower,
                        tick.tickUpper
                    )
                );

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
    }

    /**
     * @notice Gets current ticks and it's amounts
     * @param _strategy Address of the strategy
     */
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
