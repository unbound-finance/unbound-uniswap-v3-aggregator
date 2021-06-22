// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

// TODO: Add events on each action
// TODO: Add address validation checks
// TODO: Add logic in such a way that both ticks cannot be same

interface IAggregator {
    function rebalance(address _strategy) external;

    function getAUM(address _strategy) external returns (uint256, uint256);
}

contract UnboundStrategy {
    using SafeMath for uint256;

    address public immutable pool;

    uint256 public fee;
    address public feeTo;

    bool public initialized;

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
        int24 tickLower;
        int24 tickUpper;
    }

    Tick[] public ticks;

    address public factory;

    uint256 totalAmount0;
    uint256 totalAmount1;

    constructor(
        address _aggregator,
        address _pool,
        address _operator
    ) {
        aggregator = _aggregator;
        pool = _pool;
        operator = _operator;
        fee = 0;
    }

    // Modifiers
    modifier onlyOperator() {
        require(msg.sender == operator, "Ownable: caller is not the operator");
        _;
    }

    // Modifiers
    modifier isInitialized() {
        require(initialized, "Ownable: strategy not initialized");
        _;
    }

    // Checks if sender is operator
    function isOperator() internal view returns (bool) {
        return msg.sender == operator;
    }

    /**
     * @dev Replaces old ticks with new ticks
     * @param _ticks New ticks
     */
    function changeTicks(Tick[] memory _ticks) internal {
        delete ticks;

        // TODO: Add a check that two tick upper and tick lowers are not  in array cannot be same

        // (uint256 allowedAmount0, uint256 allowedAmount1) =
        //     IAggregator(aggregator).getAUM(address(this));

        for (uint256 i = 0; i < _ticks.length; i++) {
            Tick storage tick;
            tick.amount0 = _ticks[i].amount0;
            tick.amount1 = _ticks[i].amount1;
            tick.tickLower = _ticks[i].tickLower;
            tick.tickUpper = _ticks[i].tickUpper;
            ticks.push(tick);
            totalAmount0 = totalAmount0.add(_ticks[i].amount0);
            totalAmount1 = totalAmount1.add(_ticks[i].amount1);
        }

        // require(
        //     totalAmount0 <= allowedAmount0 && totalAmount1 <= allowedAmount1,
        //     "total amounts exceed"
        // );
    }

    /**
     * @notice Initialised the strategy, can be done only once
     * @param _ticks new ticks in the form of Tick struct
     */
    function initialize(Tick[] memory _ticks) external onlyOperator {
        require(!initialized, "strategy already initialised");
        for (uint256 i = 0; i < _ticks.length; i++) {
            Tick storage tick;
            tick.amount0 = 0;
            tick.amount1 = 0;
            tick.tickLower = _ticks[i].tickLower;
            tick.tickUpper = _ticks[i].tickUpper;
            ticks.push(tick);
        }
    }

    /**
     * @notice Changes ticks and rebalances
     * @param _ticks New ticks in the array
     */
    function changeTicksAndRebalance(Tick[] memory _ticks) external {
        // TODO: Make sure we check the maximum added amounts from aggregator, only allow to add amounts the strtategy is holding in aggregator
        require(ticks.length <= 5, "invalid number of ticks");
        changeTicks(_ticks);
        swapAmount = 0;
        hold = false;
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
        bool _zeroToOne,
        Tick[] memory _ticks
    ) external {
        // console.log("swap and rebalance");
        // console.log(msg.sender);
        // console.log(operator);
        // require(msg.sender == operator, "not manager");
        // require(initialized, "Ownable: strategy not initialized");

        zeroToOne = _zeroToOne;
        swapAmount = _swapAmount;
        allowedSlippage = _allowedSlippage;
        allowedPriceSlippage = _allowedPriceSlippage;
        hold = false;
        changeTicks(_ticks);
        IAggregator(aggregator).rebalance(address(this));
    }

    function holdFunds() external {
        hold = true;
        delete ticks;
        swapAmount = 0;
        allowedSlippage = 0;
        allowedPriceSlippage = 0;
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

    function tickLength() public view returns (uint256 length) {
        length = ticks.length;
    }
}
