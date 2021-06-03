pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./AggregatorBase.sol";

contract AggregatorManagement is AggregatorBase {
    using SafeMath for uint256;

    struct UnusedAmounts {
        uint256 amount0;
        uint256 amount1;
    }

    event MintShare(
        address indexed strategy,
        address indexed user,
        uint256 amount
    );

    event BurnShare(
        address indexed strategy,
        address indexed user,
        uint256 amount
    );

    mapping(address => mapping(address => uint256)) public shares;

    // mapping of strategies with their total share
    mapping(address => uint256) totalShares;

    // hold
    mapping(address => UnusedAmounts) public unused;

    function increaseUnusedAmounts(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1
    ) internal returns (uint256 amount0, uint256 amount1) {
        UnusedAmounts storage unusedAmounts = unused[_strategy];
        unusedAmounts.amount0 = unusedAmounts.amount0.add(_amount0);
        unusedAmounts.amount1 = unusedAmounts.amount1.add(_amount1);
    }

    function updateUnusedAmounts(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1
    ) internal returns (uint256 amount0, uint256 amount1) {
        UnusedAmounts storage unusedAmounts = unused[_strategy];
        unusedAmounts.amount0 = _amount0;
        unusedAmounts.amount1 = _amount1;
    }

    function decreaseUnusedAmounts(
        address _strategy,
        uint256 _amount0,
        uint256 _amount1
    ) internal returns (uint256 amount0, uint256 amount1) {
        UnusedAmounts storage unusedAmounts = unused[_strategy];
        unusedAmounts.amount0 = unusedAmounts.amount0.add(_amount0);
        unusedAmounts.amount1 = unusedAmounts.amount1.add(_amount1);
    }

    function getUnusedAmounts(address _strategy)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        UnusedAmounts storage unusedAmounts = unused[_strategy];
        amount0 = unusedAmounts.amount0;
        amount1 = unusedAmounts.amount1;
    }

    /// @notice Updates the shares of the user
    /// @param _strategy Address of the strategy
    /// @param _shares amount of shares user wants to burn
    /// @param _to address where shares should be issued
    function mintShare(
        address _strategy,
        uint256 _shares,
        address _to
    ) internal {
        // update shares
        shares[_strategy][_to] = shares[_strategy][_to].add(uint256(_shares));
        // update total shares
        totalShares[_strategy] = totalShares[_strategy].add(_shares);
        // emit event
        emit MintShare(_strategy, _to, _shares);
    }

    function issueShare(
        address _strategy,
        uint160 _liquidityAfter,
        uint160 _liquidity,
        address _user
    ) internal returns (uint256 share) {
        // calculate shares
        // TODO: Replace liquidity with liquidityBefore
        share = uint256(_liquidityAfter)
            .sub(_liquidity)
            .mul(totalShares[_strategy])
            .div(_liquidity)
            .add(1000);

        if (feeTo != address(0)) {
            uint256 fee = share.mul(PROTOCOL_FEE).div(1e6);

            share = share.sub(fee);
            // issue fee
            mintShare(_strategy, fee, feeTo);
            // issue shares
            mintShare(_strategy, share, _user);
        } else {
            // update shares w.r.t. strategy
            mintShare(_strategy, share, _user);
        }
    }

    /// @notice Burns the share of the user
    /// @param _strategy Address of the strategy
    /// @param _shares amount of shares user wants to burn
    function burnShare(address _strategy, uint256 _shares) internal {
        // update shares
        shares[_strategy][msg.sender] = shares[_strategy][msg.sender].sub(
            uint256(_shares)
        );
        // update total shares
        totalShares[_strategy] = totalShares[_strategy].sub(_shares);
        emit BurnShare(_strategy, msg.sender, _shares);
    }
}
