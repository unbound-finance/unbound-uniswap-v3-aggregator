//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./AggregatorBase.sol";

import "../interfaces/IUnboundStrategy.sol";

import "hardhat/console.sol";

contract AggregatorManagement is AggregatorBase {
    using SafeMath for uint256;

    struct Tick {
        uint256 amount0;
        uint256 amount1;
        int24 tickUpper;
        int24 tickLower;
    }

    struct Strategy {
        // uint256 amount0; // used amount0
        // uint256 amount1; // used amount1
        // uint256 secondaryAmount0;
        // uint256 secondaryAmount1;
        // int24 tickLower;
        // int24 tickUpper;
        // int24 secondaryTickLower;
        // int24 secondaryTickUpper;
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
        @dev Gets unused (remaining) amounts
        @param _strategy Address of the strategy
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

        // strategy owner fees
        if (strategy.fee() > 0) {
            uint256 managerShare = share.mul(strategy.fee()).div(1e6);
            mintShare(_strategy, managerShare, strategy.feeTo());
            share = share.sub(managerShare);
        }

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
     * @dev Updates strategy data for future use
     * @param _strategy Address of the strategy
     * @param _ticks Array of the new ticks
     */
    function updateStrategy(
        address _strategy,
        IUnboundStrategy.Tick[] memory _ticks
    ) internal {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        Strategy storage newStrategy = strategies[_strategy];
        newStrategy.hold = strategy.hold();
        // update the ticks
        updateTicks(false, _strategy, 0, 0, 0, _ticks);
    }

    function updateUsedAmounts(
        address _strategy,
        IUnboundStrategy.Tick[] memory _ticks,
        uint256 _tickId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        Strategy storage strategy = strategies[_strategy];

        // store old amounts in memory to use later
        IUnboundStrategy.Tick memory tick = strategy.ticks[_tickId];

        // update ticks
        updateTicks(true, _strategy, _tickId, _amount0, _amount1, _ticks);
    }

    /**
     * @dev Increase amounts in the current ticks
     * @param _ticks The array of ticks
     * @param _amount0 Amount of token0 to be increased
     * @param _amount1 Amount of token1 to be increased
     */
    function increaseUsedAmounts(
        address _strategy,
        IUnboundStrategy.Tick[] memory _ticks,
        uint256 _tickId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        Strategy storage strategy = strategies[_strategy];

        // store old amounts in memory to use later
        IUnboundStrategy.Tick memory tick = strategy.ticks[_tickId];

        // update ticks
        updateTicks(
            true,
            _strategy,
            _tickId,
            tick.amount0.add(_amount0),
            tick.amount1.add(_amount1),
            _ticks
        );
    }

    function updateTicks(
        bool specificUpdate,
        address _strategy,
        uint256 _tickId,
        uint256 _amount0,
        uint256 _amount1,
        IUnboundStrategy.Tick[] memory _ticks
    ) internal {
        Strategy storage strategy = strategies[_strategy];
        delete strategy.ticks;
        for (uint256 i = 0; i < _ticks.length; i++) {
            IUnboundStrategy.Tick memory tick = strategy.ticks[i];
            IUnboundStrategy.Tick memory newTick;
            newTick.tickLower = tick.tickLower;
            newTick.tickUpper = tick.tickUpper;
            // if the provided tick id matches with index
            // update the amounts directly else continue with old amounts
            if (i == _tickId && specificUpdate) {
                newTick.amount0 = _amount0;
                newTick.amount1 = _amount1;
            } else {
                newTick.amount0 = tick.amount0;
                newTick.amount1 = tick.amount1;
            }

            strategy.ticks.push(newTick);
        }
    }

    /**
     * @dev Decrease amounts in the current ticks
     * @param _ticks The array of ticks
     * @param _amount0 Amount of token0 to be increased
     * @param _amount1 Amount of token1 to be increased
     */
    function decreaseUsedAmounts(
        address _strategy,
        IUnboundStrategy.Tick[] memory _ticks,
        uint256 _tickId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        Strategy storage strategy = strategies[_strategy];

        // store old amounts in memory to use later
        IUnboundStrategy.Tick memory tick = strategy.ticks[_tickId];

        // update ticks
        updateTicks(
            true,
            _strategy,
            _tickId,
            tick.amount0.sub(_amount0),
            tick.amount1.sub(_amount1),
            _ticks
        );
    }
}
