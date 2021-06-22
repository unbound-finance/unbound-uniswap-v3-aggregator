// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

import "./Strategy.sol";

import "hardhat/console.sol";

contract StrategyFactory {
    address public immutable aggregator;

    mapping(uint256 => address) public strategies;

    uint256 total;

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
        strategy = address(new UnboundStrategy(aggregator, _pool, _operator));
        console.log("new strategy deployed", strategy);
        strategies[total] = strategy;
        total++;
    }
}
