//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

interface UnboundStrategy {
    function pool() public view returns (address);

    function range0() public view returns (uint256);

    function range1() public view returns (uint256);

    function fee() public view returns (uint256);
}
