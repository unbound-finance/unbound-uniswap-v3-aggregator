//SPDX-License-Identifier: Unlicense
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../libraries/UniswapV3Oracle.sol";

import "./AggregatorBase.sol";

import "../interfaces/IStrategy.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

// TODO: Remove this:
import "hardhat/console.sol";

contract AggregatorManagement is AggregatorBase {
    using SafeMath for uint256;

    struct Strategy {
        IStrategy.Tick[] ticks;
        bool hold;
    }

    // store strategy
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

    // unused amounts
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
        view
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

    function calculateShares(
        address _pool,
        address _strategy,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _totalAmount0,
        uint256 _totalAmount1
    ) internal returns (uint256 share) {
        uint256 totalShares = totalShares[_strategy];
        uint256 price = UniswapV3Oracle.consult(_pool, 60);

        if (_totalAmount0 == 0) {
            share = (_amount1.mul(price).add(_amount0)).div(1000);
        } else if (_totalAmount1 == 0) {
            share = (_amount0.mul(price).add(_amount1)).div(1000);
        } else {
            share = totalShares.mul(((_amount0).mul(price).add(_amount1))).div(
                _totalAmount0.mul(price).add(_totalAmount1)
            );
        }
    }

    /**
     * @notice Updates the shares of the user
     * @param _strategy Address of the strategy
     * @param _amount0 Amount of token0
     * @param _amount1 Amount of token1
     * @param _totalAmount0 Total amount0 in the specific strategy
     * @param _totalAmount1 Total amount1 in the specific strategy
     * @param _user address where shares should be issued
     */
    function issueShare(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _totalAmount0,
        uint256 _totalAmount1,
        address _user
    ) internal returns (uint256 share) {
        IStrategy strategy = IStrategy(_strategy);

        // // TODO: implement oracle here
        IUniswapV3Pool pool = IUniswapV3Pool(strategy.pool());

        share = calculateShares(
            address(pool),
            _strategy,
            _amount0,
            _amount1,
            _totalAmount0,
            _totalAmount1
        );

        require(share > 0, "invalid shares");

        // strategy owner fees
        if (strategy.feeTo() != address(0) && strategy.managementFee() > 0) {
            uint256 managerShare = share.mul(strategy.managementFee()).div(1e8);
            mintShare(_strategy, managerShare, strategy.feeTo());
            share = share.sub(managerShare);
        }

        if (feeTo != address(0)) {
            uint256 fee = share.mul(PROTOCOL_FEE).div(1e8);
            mintShare(_strategy, fee, feeTo);
            share = share.sub(fee);
        }

        // issue shares
        mintShare(_strategy, share, _user);
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
    ) internal {
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
        Strategy storage strategySnapshot = strategies[_strategy];
        if (strategySnapshot.ticks.length == 0) {
            updateUsedAmounts(_strategy, _tickId, _amount0, _amount1);
        } else {
            updateUsedAmounts(
                _strategy,
                _tickId,
                strategySnapshot.ticks[_tickId].amount0.add(_amount0),
                strategySnapshot.ticks[_tickId].amount1.add(_amount1)
            );
        }
    }

    /**
     * @dev Updates used amounts
     * @param _strategy Address of the strategy
     * @param _tickId Index of the tick to update
     * @param _amount0 Amount of token0
     * @param _amount1 Amount of token1
     */
    function updateUsedAmounts(
        address _strategy,
        uint256 _tickId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        Strategy storage strategySnapshot = strategies[_strategy];
        IStrategy strategy = IStrategy(_strategy);

        if (strategySnapshot.ticks.length == 0) {
            // initiate an ticks array and push new tick data to it
            strategySnapshot.ticks.push(
                IStrategy.Tick(
                    _amount0,
                    _amount1,
                    strategy.ticks(_tickId).tickLower,
                    strategy.ticks(_tickId).tickUpper
                )
            );
        } else {
            // updated specific tick data
            IStrategy.Tick storage newTick = strategySnapshot.ticks[_tickId];
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
        Strategy storage strategySnapshot = strategies[_strategy];
        updateUsedAmounts(
            _strategy,
            _tickId,
            strategySnapshot.ticks[_tickId].amount0.sub(_amount0),
            strategySnapshot.ticks[_tickId].amount1.sub(_amount1)
        );
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
            IStrategy.Tick memory tick = strategy.ticks[i];
            totalAmount0 = totalAmount0.add(tick.amount0);
            totalAmount1 = totalAmount1.add(tick.amount1);
        }

        // add unused amounts
        amount0 = totalAmount0.add(unusedAmounts.amount0);
        amount1 = totalAmount1.add(unusedAmounts.amount1);
    }
}
