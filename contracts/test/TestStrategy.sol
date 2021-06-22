// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAggregator {
    function rebalance(address _strategy) external;
}

contract TestStrategy {
    int24 public tickLower;
    int24 public tickUpper;
    int24 public secondaryTickLower;
    int24 public secondaryTickUpper;

    uint256 public allowedPriceSlippage;

    address public pool;
    uint256 public fee;

    uint256 public swapAmount;
    // 1000000 is 100% slippage 
    uint160 public allowedSlippage;
    bool public zeroToOne;

    bool public hold;

    address owner;
    address aggregator;

    constructor(
        int24 _tickLower,
        int24 _tickUpper,
        int24 _secondaryTickLower,
        int24 _secondaryTickUpper,
        address _pool,
        uint256 _fee,
        address _owner,
        address _aggregator
    ) {
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        secondaryTickLower = _secondaryTickLower;
        secondaryTickUpper = _secondaryTickUpper;
        pool = _pool;
        owner = _owner;
        aggregator = _aggregator;
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
        IAggregator(aggregator).rebalance(address(this));
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
        allowedPriceSlippage = 0;
        IAggregator(aggregator).rebalance(address(this));
    }

    function holdFunds() public {
        tickLower = 0;
        tickUpper = 0;
        secondaryTickLower = 0;
        secondaryTickUpper = 0;
        hold = true;
        IAggregator(aggregator).rebalance(address(this));
    }

    function changeFee(uint256 _newFee) public {
        fee = _newFee;
    }
}
