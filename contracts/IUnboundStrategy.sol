//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.6;

interface IUnboundStrategy {
    function pool() external view returns (address);

    function tickLower() external view returns (int24);

    function tickUpper() external view returns (int24);

    function swapAmount() external view returns (int256);
    function zeroToOne() external view returns (bool);
    function allowedSlippage() external view returns (uint160);

    // TODO: Add hold and swap
    function hold() external view returns (bool);

    function secondaryTickUpper() external view returns (int24);

    function secondaryTickLower() external view returns (int24);

    function fee() external view returns (uint256);
}
