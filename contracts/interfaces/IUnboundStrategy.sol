//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.6;

interface IUnboundStrategy {
    // address of the pool
    function pool() external view returns (address);

    // the current lower tick to place range order
    function tickLower() external view returns (int24);

    // the current upper tick to place range order
    function tickUpper() external view returns (int24);

    // if this variable is present, rebalance will swap the amount and redeploy
    // into newly provided ranges
    function swapAmount() external view returns (int256);

    // the direction of the swap, if enabled
    function zeroToOne() external view returns (bool);

    // allowed slippage for the swap
    function allowedSlippage() external view returns (uint160);

    // if enabled, the aggregator will hold the liquidity
    function hold() external view returns (bool);

    // if strategy owner wants to put remaning liquidity in limit order
    // upper tick for limit order
    function secondaryTickUpper() external view returns (int24);

    // lower tick for limit order
    function secondaryTickLower() external view returns (int24);
    
    // 1e8 means 100%
    // strategy fee the owner wants to charge
    function fee() external view returns (uint256);

    // address where the strategy owner's fees should be sent
    function feeTo() external view returns(address);

    // slippage 1e6 means 100%
    // allowed price slippage on the value of root p
    function allowedPriceSlippage() external view returns(uint256);
}
