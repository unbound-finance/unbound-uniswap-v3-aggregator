// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

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

    uint256 public swapAmount;
    // 1000000 is 100% slippage 
    uint160 public allowedSlippage;
    bool public zeroToOne;

    bool public hold;

    constructor(
        int24 _tickLower,
        int24 _tickUpper,
        int24 _secondaryTickLower,
        int24 _secondaryTickUpper,
        address _pool,
        uint256 _fee
    ) {
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        secondaryTickLower = _secondaryTickLower;
        secondaryTickUpper = _secondaryTickUpper;
        pool = _pool;
    }

    function changeTicks(
        int24 _newTickLower,
        int24 _newTickUpper,
        int24 _newSecondaryTickLower,
        int24 _newSecondaryTickUpper,
        uint256 _swapAmount
    ) external {
        tickLower = _newTickLower;
        tickUpper = _newTickUpper;
        secondaryTickLower = _newSecondaryTickLower;
        secondaryTickUpper = _newSecondaryTickUpper;
        swapAmount = _swapAmount;
        if (swapAmount == 0) {
            swapAmount = 0;
        }
    }

    function swapFunds(
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _swapAmount,
        uint160 _allowedSlippage,
        bool _zeroToOne
    ) public {
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        swapAmount = _swapAmount;
        allowedSlippage = _allowedSlippage;
        zeroToOne = _zeroToOne;
    }

    function holdFunds() public {
        tickLower = 0;
        tickUpper = 0;
        secondaryTickLower = 0;
        secondaryTickUpper = 0;
        hold = true;
    }
}
