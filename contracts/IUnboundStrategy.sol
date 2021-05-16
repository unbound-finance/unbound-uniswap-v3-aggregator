//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.6;

// TODO: Move to different file
interface IUnboundStrategy {
    function pool() external view returns (address);

    function stablecoin() external view returns (address);

    function tickLower() external view returns (int24);

    function tickUpper() external view returns (int24);

    function range0() external view returns (uint256);

    function range1() external view returns (uint256);

    function fee() external view returns (uint256);
}