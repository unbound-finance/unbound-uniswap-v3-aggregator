// SPDX-License-Identifier: MIT

pragma solidity =0.7.6;
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

        for (uint256 i = 0; i < _ticks.length; i++) {
            int24 tickLower = _ticks[i].tickLower;
            int24 tickUpper = _ticks[i].tickUpper;

            // check that two tick upper and tick lowers are not in array cannot be same
            for (uint256 j = 0; j < _ticks.length; j++) {
                if (i != j) {
                    if (tickLower == _ticks[j].tickLower) {
                        require(
                            tickUpper != _ticks[j].tickUpper,
                            "ticks cannot be same"
                        );
                    }
                }
            }

            ticks.push(
                Tick(
                    _ticks[i].amount0,
                    _ticks[i].amount1,
                    _ticks[i].tickLower,
                    _ticks[i].tickUpper
                )
            );
        }
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
     * @param _sqrtPriceLimitX96 The allowed slippage in terms of percentage
     * @param _allowedPriceSlippage The allowed price movement after the swap
     */
    function rebalance(
        uint256 _swapAmount,
        uint160 _sqrtPriceLimitX96,
        uint256 _allowedPriceSlippage,
        bool _zeroToOne,
        Tick[] memory _ticks
    ) external onlyOperator whenInitialized {
        zeroToOne = _zeroToOne;
        swapAmount = _swapAmount;
        sqrtPriceLimitX96 = _sqrtPriceLimitX96;
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
     * @param _tier Fee tier from indexes 0 to 2
     */
    function changeFee(uint256 _tier) public onlyOperator {
        if (_tier == 2) {
            managementFee = 5000000;
        } else if (_tier == 1) {
            managementFee = 2000000;
        } else {
            managementFee = 1000000;
        }
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
    function acceptOperator() external {
        require(msg.sender == pendingOperator, "invalid match");
        operator = pendingOperator;
    }

    // get length of ticks array
    function tickLength() public view returns (uint256 length) {
        length = ticks.length;
    }
}
