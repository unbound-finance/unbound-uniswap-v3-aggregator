// SPDX-License-Identifier: MIT

pragma solidity =0.7.6;
pragma abicoder v2;

import "./DefiEdgeStrategy.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract StrategyFactory {
    using SafeMath for uint256;

    event NewStrategy(address indexed strategy, address indexed creater);

    address public immutable aggregator;

    // tracks strategies by Index
    mapping(uint256 => address) public strategyByIndex;

    // check validity of the strategy
    mapping(address => bool) public isValid;

    uint256 public total;

    constructor(address _aggregator) {
        aggregator = _aggregator;
    }

    /**
     * @notice Launches strategy contract
     * @param _pool Address of the pool
     * @param _operator Address of the operator
     */
    function createStrategy(address _pool, address _operator)
        external
        returns (address strategy)
    {
        strategy = address(new DefiEdgeStrategy(aggregator, _pool, _operator));
        isValid[strategy] = true;
        strategyByIndex[total + 1] = strategy;
        total += 1;
        emit NewStrategy(strategy, msg.sender);
    }
}
