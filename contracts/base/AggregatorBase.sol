//SPDX-License-Identifier: Unlicense
pragma solidity =0.7.6;

contract AggregatorBase {
    // to update protocol fees
    address public governance;

    // used for two step governance change
    address public pendingGovernance;

    // to receive the fees
    address public feeTo;

    // protocol fees, 1e8 is 100%
    uint256 public PROTOCOL_FEE;

    // mapping of blacklisted strategies
    mapping(address => bool) public blacklisted;

    // Modifiers
    modifier onlyGovernance() {
        require(isOwner(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Change the fee setter's address
     * @param _governance New governance address
     */
    function changeGovernance(address _governance) external onlyGovernance {
        require(_governance != address(0), "invalid governance address");
        pendingGovernance = _governance;
    }

    function acceptGovernance() external onlyGovernance {
        require(msg.sender == pendingGovernance, "invalid match");
        governance = pendingGovernance;
    }

    /**
     * @notice Change protocol's fee
     * @dev 1e8 is 100%
     * @param _newFee New governance address
     */
    function changeFee(uint256 _newFee) external onlyGovernance {
        PROTOCOL_FEE = _newFee;
    }

    /**
     * @dev Change fee receiver
     * @param _feeTo New fee receiver
     */
    function changeFeeTo(address _feeTo) external onlyGovernance {
        feeTo = _feeTo;
    }

    /**
     * @dev Blacklists the strategy
     * @param _strategy Address of the strategy
     */
    function blacklist(address _strategy) external onlyGovernance {
        blacklisted[_strategy] = true;
    }

    // Checks if sender is owner
    function isOwner() public view returns (bool) {
        return msg.sender == governance;
    }
}
