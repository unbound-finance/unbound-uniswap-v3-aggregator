//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./AggregatorBase.sol";

import "../interfaces/IUnboundStrategy.sol";

import "hardhat/console.sol";

contract AggregatorManagement is AggregatorBase {
    using SafeMath for uint256;

    struct Strategy {
        uint256 amount0; // used amount0
        uint256 amount1; // used amount1
        uint256 secondaryAmount0;
        uint256 secondaryAmount1;
        int24 tickLower;
        int24 tickUpper;
        int24 secondaryTickLower;
        int24 secondaryTickUpper;
        bool swap;
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
    mapping(address => uint256) totalShares;

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
    ) internal returns (uint256 amount0, uint256 amount1) {
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
    ) internal returns (uint256 amount0, uint256 amount1) {
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
    ) internal returns (uint256 amount0, uint256 amount1) {
        UnusedAmounts storage unusedAmounts = unused[_strategy];
        unusedAmounts.amount0 = unusedAmounts.amount0.add(_amount0);
        unusedAmounts.amount1 = unusedAmounts.amount1.add(_amount1);
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
            share = share.sub(managerShare);
        }

        if (feeTo != address(0)) {
            // TODO: Consider strategy owner fees
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
    function burnShare(address _strategy, uint256 _shares)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        shares[_strategy][msg.sender] = shares[_strategy][msg.sender].sub(
            uint256(_shares)
        );
        // update total shares
        totalShares[_strategy] = totalShares[_strategy].sub(_shares);
        emit BurnShare(_strategy, msg.sender, _shares);
    }

    /**
     * @dev Updates strategy data for future use
     * @param _strategy Address of the strategy
     * @param _amount0 Amount of token0
     * @param _amount1 Amount of token1
     * @param _secondaryAmount0 Amount0 placed in the limit order
     * @param _secondaryAmount1 Amount1 placed in the limit order
     */
    function updateStrategy(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _secondaryAmount0,
        uint256 _secondaryAmount1
    ) internal {
        IUnboundStrategy strategy = IUnboundStrategy(_strategy);
        Strategy storage newStrategy = strategies[_strategy];
        newStrategy.tickLower = strategy.tickLower();
        newStrategy.tickUpper = strategy.tickUpper();
        newStrategy.secondaryTickLower = strategy.secondaryTickLower();
        newStrategy.secondaryTickUpper = strategy.secondaryTickUpper();
        newStrategy.hold = strategy.hold();
        newStrategy.amount0 = _amount0;
        newStrategy.amount1 = _amount1;
        newStrategy.secondaryAmount0 = _secondaryAmount0;
        newStrategy.secondaryAmount1 = _secondaryAmount1;
    }

    /**
     * @dev Increases total stored amounts for a specific strategy
     * @param _strategy Address of the strategy
     * @param _amount0 Amount of token0
     * @param _amount1 Amount of token1
     */
    function increaseTotalAmounts(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        Strategy storage strategy = strategies[_strategy];
        uint256 amount0 = strategy.amount0.add(_amount0);
        uint256 amount1 = strategy.amount1.add(_amount1);
        updateStrategy(
            _strategy,
            amount0,
            amount1,
            strategy.secondaryAmount0,
            strategy.secondaryAmount1
        );
    }

    /**
     * @dev Decreases total stored amounts for a specific strategy
     * @param _strategy Address of the strategy
     * @param _amount0 Amount of token0
     * @param _amount1 Amount of token1
     */
    function decreaseTotalAmounts(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        Strategy storage strategy = strategies[_strategy];
        uint256 amount0 = strategy.amount0.sub(_amount0);
        uint256 amount1 = strategy.amount1.sub(_amount1);
        updateStrategy(
            _strategy,
            amount0,
            amount1,
            strategy.secondaryAmount0,
            strategy.secondaryAmount1
        );
    }
}
