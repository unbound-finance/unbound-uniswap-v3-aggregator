// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract TestStrategy {

    uint256 public range0;
    uint256 public range1;

    int24 public tickLower;
    int24 public tickUpper;

    address public pool;
    address public stablecoin;

    uint256 public fee;

    constructor(
        uint256 _range0,
        uint256 _range1,
        int24 _tickLower,
        int24 _tickUpper,
        address _pool,
        address _stablecoin,
        uint256 _fee
    ) {
        range0 = _range0;
        range1 = _range1;
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        pool = _pool;
        stablecoin = _stablecoin;
    }

    function changeRange0(uint256 _newRange) public {
        range0 = _newRange;
    }


    function changeRange1(uint256 _newRange) public {
        range0 = _newRange;
    }


    function changeTickLower(int24 _tickLower) public {
        tickLower = _tickLower;
    }


    function changeTickUpper(int24 _tickUpper) public {
        tickUpper = _tickUpper;
    }
}