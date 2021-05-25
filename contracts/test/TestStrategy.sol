// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestStrategy {
    int24 public tickLower;
    int24 public tickUpper;
    int24 public secondaryTickLower;
    int24 public secondaryTickUpper;

    address public pool;
    uint256 public fee;
    bool public swap;
    bool public hold;

    constructor(
        uint256 _range0,
        uint256 _range1,
        int24 _tickLower,
        int24 _tickUpper,
        address _pool,
        address _stablecoin,
        uint256 _fee
    ) {
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        pool = _pool;
        swap = false;
    }

    function changeTicks(
        int24 _newTickLower,
        int24 _newTickUpper,
        int24 _newSecondaryTickLower,
        int24 _newSecondaryTickUpper,
        bool _swap
    ) external {
        tickLower = _newTickLower;
        tickUpper = _newTickUpper;
        secondaryTickLower = _newSecondaryTickLower;
        secondaryTickUpper = _newSecondaryTickUpper;
        swap = _swap;
    }

    function holdFunds() public{
        tickLower = 0;
        tickUpper = 0;
        secondaryTickLower = 0;
        secondaryTickUpper = 0;
        swap = false;
    }
}
