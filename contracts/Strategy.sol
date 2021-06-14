// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// TODO: Add events on each action

interface IAggregator {
    function rebalance(address _strategy) external;
}

contract TestStrategy {
    address public pool;

    uint256 public fee;
    address public feeTo;

    bool initialized;

    bool public hold;

    address operator;
    address aggregator;

    uint256 public swapAmount;
    uint160 public allowedSlippage;
    bool public zeroToOne;

    uint256 public allowedPriceSlippage;

    struct Tick {
        uint256 amount0;
        uint256 amount1;
        int24 tickUpper;
        int24 tickLower;
    }

    Tick[] public ticks;

    constructor(
        address _aggregator,
        address _pool,
        address _operator
    ) {
        aggregator = _aggregator;
        pool = _pool;
        operator = _operator;
    }

    // Modifiers
    modifier onlyOperator() {
        require(isOperator(), "Ownable: caller is not the operator");
        _;
    }

    // Modifiers
    modifier isInitialized() {
        require(initialized, "Ownable: caller is not the operator");
        _;
    }

    // Checks if sender is operator
    function isOperator() public view returns (bool) {
        return msg.sender == operator;
    }

    /**
     * @dev Replaces old ticks with new ticks
     * @param _ticks New ticks
     */
    function changeTicks(Tick[] memory _ticks) internal {
        // TODO: Add a check that two tick upper and tick lowers are not  in array cannot be same
        for (uint256 i = 0; i < _ticks.length; i++) {
            Tick storage tick;
            tick.amount0 = _ticks[i].amount0;
            tick.amount1 = _ticks[i].amount1;
            tick.tickLower = _ticks[i].tickLower;
            tick.tickUpper = _ticks[i].tickUpper;
            ticks.push(tick);
        }
    }

    /**
     * @notice Initialised the strategy, can be done only once
     * @param _ticks new ticks in the form of Tick struct
     */
    function initialize(Tick[] memory _ticks) external onlyOperator {
        require(!initialized, "strategy already initialised");
        changeTicks(_ticks);
    }

    /**
     * @notice Changes ticks and rebalances
     * @param _ticks New ticks in the array
     */
    function changeTicksAndRebalance(Tick[] memory _ticks)
        external
        onlyOperator
        isInitialized
    {
        // TODO: Make sure we check the maximum added amounts from aggregator, only allow to add amounts the strtategy is holding in aggregator
        require(ticks.length <= 5, "invalid number of ticks");
        changeTicks(_ticks);
        IAggregator(aggregator).rebalance(address(this));
    }

    /**
     * @notice Swaps and updates ticks for rebalancing
     * @param _swapAmount Amount to be swapped
     * @param _allowedSlippage The allowed slippage in terms of percentage
     * @param _allowedPriceSlippage The allowed price movement after the swap
     */
    function swapAndRebalance(
        uint256 _swapAmount,
        uint160 _allowedSlippage,
        uint256 _allowedPriceSlippage,
        Tick[] memory _ticks
    ) external onlyOperator isInitialized {
        swapAmount = _swapAmount;
        allowedSlippage = _allowedSlippage;
        allowedPriceSlippage = _allowedPriceSlippage;
        IAggregator(aggregator).rebalance(address(this));
    }

    /**
     * @notice Changes the fee
     * @param _newFee New fee
     */
    function changeFee(uint256 _newFee) public onlyOperator {
        fee = _newFee;
    }

    /**
     * @notice changes address where the operator is receiving the fee
     * @param _newFeeTo New address where fees should be received
     */
    function changeFeeTo(address _newFeeTo) external onlyOperator {
        feeTo = _newFeeTo;
    }
}
