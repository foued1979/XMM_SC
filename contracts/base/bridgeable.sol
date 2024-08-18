// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../libraries/safemath.sol";
import "../structures/bridge.sol";

abstract contract Bridgeable {
    // Modifiers
    modifier _onlyOwner {
        require(msg.sender == _owner);
        _;
    }

    modifier notSameChain(uint64 chainId) {
        require(chainId != _chainId);
        _;
    }

    modifier isValidChain(uint64 chainId) {
        require(chainId != _chainId && chainIsValid(chainId));
        _;
    }

    modifier onlyIfHavePendingRequest(uint64 onChainId) {
        require(pendingBridgeOutAmountByChain[msg.sender][onChainId] > 0);
        _;
    }

    // Properties
    address private _owner;
    uint64 internal _chainId;
    uint64[] private _validChainIds;

    mapping(address => uint128) internal pendingBridgingAmountsIn;
    uint128 internal pendingAmountToBeTransferredIn;

    mapping(address => mapping(uint64 => uint128)) internal pendingBridgeOutAmountByChain;
    mapping(address => uint64[]) internal pendingBridgesForChain;

    address[] internal pendingBridgesOut;
    address[] internal pendingBridgesIn;

    constructor(uint64 chainId) {
        _owner = msg.sender;
        _chainId = chainId;
    }

    function addValidChainId(uint64 chainId) external _onlyOwner notSameChain(chainId) {
        for (uint i = 0; i < _validChainIds.length; i++) {
            if (_validChainIds[i] == chainId) return;
        }

        _validChainIds.push(chainId);
    }

    /// @notice Checks if msg.sender has a pending bridge to another chain
    function hasPendingBridgeOut() external view returns(bool, Bridge[] memory) {
        uint64[] storage pendingBridges = pendingBridgesForChain[msg.sender];

        if (pendingBridges.length > 0) {
            Bridge[] memory result = new Bridge[](pendingBridges.length);

            for (uint i = 0; i < pendingBridges.length; i++) {
                result[i] = Bridge(pendingBridges[i], pendingBridgeOutAmountByChain[msg.sender][pendingBridges[i]]);
            }

            return (true, result);
        }

        return (false, new Bridge[](0));
    }

    /// @notice Checks if msg.sender has a pending bridge to another chain
    function hasPendingBridgeIn() external view returns(bool, uint128) {
        uint128 pendingAmount = pendingBridgingAmountsIn[msg.sender];
        return (pendingAmount != 0, pendingAmount);
    }

    /// @notice Returns the array of addresses awaiting for bridging out
    function getPendingBridgesOut() external view _onlyOwner returns(address[] memory) {
        return pendingBridgesOut;
    }

    /// @notice Returns the array of addresses awaiting for bridging in
    function getPendingBridgesIn() external view _onlyOwner returns(address[] memory) {
        return pendingBridgesIn;
    }

    /// @notice Gets the pending bridges out for a user
    function getPendingBridgesOut(address forUser) external view _onlyOwner returns(Bridge[] memory) {
        uint64[] storage pendingBridges = pendingBridgesForChain[forUser];

        if (pendingBridges.length > 0) {
            Bridge[] memory result = new Bridge[](pendingBridges.length);

            for (uint i = 0; i < pendingBridges.length; i++) {
                result[i] = Bridge(pendingBridges[i], pendingBridgeOutAmountByChain[forUser][pendingBridges[i]]);
            }

            return result;
        }

        return new Bridge[](0);
    }

    /// @notice Adds a pending bridge out to a specific chain Id
    /// @param toChainId The destination Chain id
    /// @param amount The amount to be bridged out
    function requestBridgeOut(uint64 toChainId, uint128 amount) external virtual;

    /// @notice Cancels a bridging request for msg.sender and for a chainId
    /// @param forChainId The target chain Id to cancel
    function cancelBridgeOut(uint64 forChainId) external onlyIfHavePendingRequest(forChainId) {
        revertBridgeRequestForUser(msg.sender, forChainId);
    }

    /// @notice Cancels a bridging request for a user and for a chainId
    /// @param forUser The user address to cancel
    /// @param forChainId The target chain Id to cancel
    function revertBridgeRequestForUser(address forUser, uint64 forChainId) public virtual;

    /// @notice Adds a pending bridge in
    /// @param to The address of the beneficiary
    /// @param amount The amount
    function addPendingBridgingIn(address to, uint128 amount) external virtual;

    /// @notice Cancels a bridge in for a user
    /// @param forUser The address of the user to remove
    function cancelBridgeIn(address forUser) external _onlyOwner {
        pendingAmountToBeTransferredIn = SafeMath.SafeSub128(pendingAmountToBeTransferredIn, pendingBridgingAmountsIn[forUser]);
        pendingBridgingAmountsIn[forUser] = 0;
        removePendingBridgeIn(forUser);
    }

    /// @notice Validates a bridge in for a user and for a chain Id
    function validateBridgeOut(address forUser, uint64 forChainId) external virtual;

    /// @notice Validates a bridge in for a user
    function validateBridgeIn(address forUser) external virtual;

    // Internal methods
    function addPendingChainIdToUser(address forUser, uint64 chainId) internal {
        uint64[] storage pendingBridges = pendingBridgesForChain[forUser];

        for (uint i = 0; i < pendingBridges.length; i++) {
            if (pendingBridges[i] == chainId) return;
        }

        pendingBridges.push(chainId);
    }

    function addUserForBridingIn(address user) internal {
        for (uint i = 0; i < pendingBridgesIn.length; i++) {
            if (pendingBridgesIn[i] == user) return;
        }

        pendingBridgesIn.push(user);
    }

    function removePendingBridgingOutForUser(address user, uint64 chainId) internal {
        uint64[] storage pendingBridgings = pendingBridgesForChain[user];

        for (uint i = 0; i < pendingBridgings.length; i++) {
            if (pendingBridgings[i] == chainId) {
                pendingBridgings[i] = pendingBridgings[pendingBridgings.length - 1];
                pendingBridgings.pop();

                if (pendingBridgings.length == 0) removeUserFromPendingBridgesOut(user);
                return;
            }
        }
    }

    function removePendingBridgeIn(address user) internal {
        for (uint i = 0; i < pendingBridgesIn.length; i++) {
            if (pendingBridgesIn[i] == user) {
                pendingBridgesIn[i] = pendingBridgesIn[pendingBridgesIn.length - 1];
                pendingBridgesIn.pop();
                return;
            }
        }
    }

    // Private methods
    function removeUserFromPendingBridgesOut(address user) private {
        for (uint i = 0; i < pendingBridgesOut.length; i++) {
            if (pendingBridgesOut[i] == user) {
                pendingBridgesOut[i] = pendingBridgesOut[pendingBridgesOut.length - 1];
                pendingBridgesOut.pop();
                return;
            }
        }
    }

    function chainIsValid(uint64 chainId) private view returns(bool) {
        for (uint i = 0; i < _validChainIds.length; i++) {
            if (_validChainIds[i] == chainId) return true;
        }

        return false;
    }
}