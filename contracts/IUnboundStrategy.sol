//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.6;

// TODO: Move to different file
interface IUnboundStrategy {

    function pool() external view returns (address);

    function tickLower() external view returns (int24);

    function tickUpper() external view returns (int24);

    function swap() external view returns(bool);

    function hold() external view returns(bool);

    function secondaryTickUpper() external view returns(int24);
    
    function secondaryTickLower() external view returns(int24);

    function fee() external view returns (uint256);
}