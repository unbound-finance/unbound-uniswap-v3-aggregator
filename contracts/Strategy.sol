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

contract DefiEdgeStrategy {
    using SafeMath for uint256;

    address public immutable pool;

    uint256 public managementFee = 0;
    address public feeTo;

    bool public initialized;

    bool public onHold;

    address public operator;
    address pendingOperator;
    address public aggregator;

    uint256 public swapAmount;
    uint160 public sqrtPriceLimitX96;
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

    enum feeTier {
        SMALL,
        MEDIUM,
        LARGE
    }

    constructor(
        address _aggregator,
        address _pool,
        address _operator
    ) {
        aggregator = _aggregator;
        pool = _pool;
        operator = _operator;
        managementFee = 0;
    }

    // Modifiers
    modifier onlyOperator() {
        require(msg.sender == operator, "Ownable: caller is not the operator");
        _;
    }

    // Modifiers
    modifier whenInitialized() {
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
        // deletes ticks array
        delete ticks;

        // TODO: Add a check that two tick upper and tick lowers are not in array cannot be same

        // (uint256 allowedAmount0, uint256 allowedAmount1) =
        //     IAggregator(aggregator).getAUM(address(this));

        for (uint256 i = 0; i < _ticks.length; i++) {
            ticks.push(
                Tick(
                    _ticks[i].amount0,
                    _ticks[i].amount1,
                    _ticks[i].tickLower,
                    _ticks[i].tickUpper
                )
            );
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
        initialized = true;
        for (uint256 i = 0; i < _ticks.length; i++) {
            ticks.push(Tick(0, 0, _ticks[i].tickLower, _ticks[i].tickUpper));
        }
    }

    /**
     * @notice Swaps and updates ticks for rebalancing
     * @param _swapAmount Amount to be swapped
     * @param _allowedSlippage The allowed slippage in terms of percentage
     * @param _allowedPriceSlippage The allowed price movement after the swap
     */
    function rebalance(
        uint256 _swapAmount,
        uint160 _allowedSlippage,
        uint256 _allowedPriceSlippage,
        bool _zeroToOne,
        Tick[] memory _ticks
    ) external onlyOperator whenInitialized {
        zeroToOne = _zeroToOne;
        swapAmount = _swapAmount;
        sqrtPriceLimitX96 = _allowedSlippage;
        allowedPriceSlippage = _allowedPriceSlippage;
        onHold = false;
        changeTicks(_ticks);
        IAggregator(aggregator).rebalance(address(this));
    }

    /**
     * @notice Holds the funds
     */
    function hold() external onlyOperator whenInitialized {
        onHold = true;
        delete ticks;
        swapAmount = 0;
        sqrtPriceLimitX96 = 0;
        allowedPriceSlippage = 0;
        IAggregator(aggregator).rebalance(address(this));
    }

    /**
     * @notice Changes the fee
     * @param _newFee New fee
     */
    function changeFee(uint256 _newFee) public onlyOperator {
        managementFee = _newFee;
    }

    /**
     * @notice changes address where the operator is receiving the fee
     * @param _newFeeTo New address where fees should be received
     */
    function changeFeeTo(address _newFeeTo) external onlyOperator {
        feeTo = _newFeeTo;
    }

    // change operator
    function changeOperator(address _operator) external onlyOperator {
        require(_operator != address(0), "invalid operator");
        pendingOperator = _operator;
    }

    // accept operator
    function acceptOperator(address _operator) external {
        require(_operator == pendingOperator, "invalid match");
        operator = _operator;
    }

    function tickLength() public view returns (uint256 length) {
        length = ticks.length;
    }
}
