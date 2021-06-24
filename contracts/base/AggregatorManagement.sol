//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./AggregatorBase.sol";

import "../interfaces/IUnboundStrategy.sol";

// TODO: Remove
import "hardhat/console.sol";

contract AggregatorManagement is AggregatorBase {
    using SafeMath for uint256;

    struct Strategy {
        IUnboundStrategy.Tick[] ticks;
        bool hold;
    }

    mapping(address => Strategy) public strategies;

    struct UnusedAmounts {
        uint256 amount0;
        uint256 amount1;
    }

    event MintShare(
        address indexed strategy,
        address indexed user,
        uint256 amount
    );

    event BurnShare(
        address indexed strategy,
        address indexed user,
        uint256 amount
    );

    mapping(address => mapping(address => uint256)) public shares;

    // mapping of strategies with their total share
    mapping(address => uint256) public totalShares;

    // hold
    mapping(address => UnusedAmounts) public unused;

    /**
        @dev Increases unused (remaining) amounts
        @param _strategy Address of the strategy
        @param _amount0 The amount of token0
        @param _amount1 The amount of token1
     */
    function increaseUnusedAmounts(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        UnusedAmounts storage unusedAmounts = unused[_strategy];
        unusedAmounts.amount0 = unusedAmounts.amount0.add(_amount0);
        unusedAmounts.amount1 = unusedAmounts.amount1.add(_amount1);
    }

    /**
        @dev Updates unused (remaining) amounts
        @param _strategy Address of the strategy
        @param _amount0 The amount of token0
        @param _amount1 The amount of token1
     */
    function updateUnusedAmounts(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        UnusedAmounts storage unusedAmounts = unused[_strategy];
        unusedAmounts.amount0 = _amount0;
        unusedAmounts.amount1 = _amount1;
    }

    /**
        @dev Decreases unused (remaining) amounts
        @param _strategy Address of the strategy
        @param _amount0 The amount of token0
        @param _amount1 The amount of token1
     */
    function decreaseUnusedAmounts(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        UnusedAmounts storage unusedAmounts = unused[_strategy];
        if (unusedAmounts.amount0 > 0) {
            unusedAmounts.amount0 = unusedAmounts.amount0.sub(_amount0);
        }
        if (unusedAmounts.amount1 > 0) {
            unusedAmounts.amount1 = unusedAmounts.amount1.sub(_amount1);
        }
    }

    /**
     * @dev Gets unused (remaining) amounts
     * @param _strategy Address of the strategy
     */
    function getUnusedAmounts(address _strategy)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        UnusedAmounts storage unusedAmounts = unused[_strategy];
        amount0 = unusedAmounts.amount0;
        amount1 = unusedAmounts.amount1;
    }

    /**
     * @notice Updates the shares of the user
     * @param _strategy Address of the strategy
     * @param _shares amount of shares user wants to burn
     * @param _to address where shares should be issued
     */
    function mintShare(
        address _strategy,
        uint256 _shares,
        address _to
    ) internal {
        // update shares
        shares[_strategy][_to] = shares[_strategy][_to].add(uint256(_shares));
        // update total shares
        totalShares[_strategy] = totalShares[_strategy].add(_shares);
        // emit event
        emit MintShare(_strategy, _to, _shares);
    }

    /**
     * @notice Updates the shares of the user
     * @param _strategy Address of the strategy
     * @param _amount0 Amount of token0
     * @param _amount1 Amount of token1
     * @param _liquidityBefore The liquidity before the user amounts are added
     * @param _liquidityAfter Liquidity after user's liquidity is minted
     * @param _user address where shares should be issued
     */
    function issueShare(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1,
        uint128 _liquidityBefore,
        uint128 _liquidityAfter,
        address _user
    ) internal returns (uint256 share) {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);

        if (totalShares[_strategy] == 0) {
            share = Math.max(_amount0, _amount1);
        } else {
            share = uint256(_liquidityAfter)
                .sub(uint256(_liquidityBefore))
                .mul(totalShares[_strategy])
                .div(uint256(_liquidityBefore));
        }

        console.log("strategy fee", strategy.fee());

        // strategy owner fees
        // if (uint256(strategy.fee()) > 0) {
        //     uint256 managerShare = share.mul(strategy.fee()).div(1e6);
        //     mintShare(_strategy, managerShare, strategy.feeTo());
        //     share = share.sub(managerShare);
        // }

        if (feeTo != address(0)) {
            uint256 fee = share.mul(PROTOCOL_FEE).div(1e6);
            share = share.sub(fee);
            // issue fee
            mintShare(_strategy, fee, feeTo);
            // issue shares
            mintShare(_strategy, share, _user);
        } else {
            // update shares w.r.t. strategy
            mintShare(_strategy, share, _user);
        }
    }

    /**
     * @notice Burns the share of the user
     * @param _strategy Address of the strategy
     * @param _shares amount of shares user wants to burn
     */
    function burnShare(
        address _strategy,
        uint256 _shares,
        address _user
    ) internal returns (uint256 amount0, uint256 amount1) {
        shares[_strategy][_user] = shares[_strategy][_user].sub(_shares);
        // update total shares
        totalShares[_strategy] = totalShares[_strategy].sub(_shares);
        emit BurnShare(_strategy, _user, _shares);
    }

    /**
     * @dev Increase amounts in the current ticks
     * @param _strategy The array of ticks
     * @param _tickId The tick to update
     * @param _amount0 Amount of token0 to be increased
     * @param _amount1 Amount of token1 to be increased
     */
    function increaseUsedAmounts(
        address _strategy,
        uint256 _tickId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        Strategy storage localStrategyData = strategies[_strategy];
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);

        if (localStrategyData.ticks.length == 0) {
            updateUsedAmounts(_strategy, _tickId, _amount0, _amount1);
        } else {
            updateUsedAmounts(
                _strategy,
                _tickId,
                localStrategyData.ticks[_tickId].amount0.add(_amount0),
                localStrategyData.ticks[_tickId].amount1.add(_amount1)
            );
        }
    }

    function updateUsedAmounts(
        address _strategy,
        uint256 _tickId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        Strategy storage localStrategyData = strategies[_strategy];
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);

        uint256 oldLength = localStrategyData.ticks.length;

        if (localStrategyData.ticks.length == 0) {
            // initiate an ticks array and push new tick data to it
            IUnboundStrategy.Tick memory newTick;
            newTick.tickLower = strategy.ticks(_tickId).tickLower;
            newTick.tickUpper = strategy.ticks(_tickId).tickUpper;
            newTick.amount0 = _amount0;
            newTick.amount1 = _amount1;
            localStrategyData.ticks.push(newTick);
        } else {
            // updated specific tick data
            IUnboundStrategy.Tick storage newTick =
                localStrategyData.ticks[_tickId];
            newTick.tickLower = strategy.ticks(_tickId).tickLower;
            newTick.tickUpper = strategy.ticks(_tickId).tickUpper;
            newTick.amount0 = _amount0;
            newTick.amount1 = _amount1;
        }
    }

    /**
     * @dev Decrease amounts in the current ticks
     * @param _strategy Address of strategy
     * @param _tickId Id of the tick to update
     * @param _amount0 Amount of token0 to be increased
     * @param _amount1 Amount of token1 to be increased
     */
    function decreaseUsedAmounts(
        address _strategy,
        uint256 _tickId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        Strategy storage localStrategyData = strategies[_strategy];
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);

        updateUsedAmounts(
            _strategy,
            _tickId,
            localStrategyData.ticks[_tickId].amount0.sub(_amount0),
            localStrategyData.ticks[_tickId].amount1.sub(_amount1)
        );
    }
}
