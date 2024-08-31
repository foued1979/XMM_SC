// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../libraries/safemath.sol";
import "../structures/bridge.sol";

abstract contract Bridgeable {
    event BridgeOutRequested(uint indexed timestamp, address indexed from, uint64 toChainId, uint128 amount);
    event BridgeOutCancelled(uint indexed timestamp, address indexed from, uint64 toChainId);

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
    uint256 internal pendingAmountToBeTransferredIn;

    mapping(address => mapping(uint64 => uint128)) internal pendingBridgeOutAmountByChain;
    mapping(address => uint64[]) internal pendingChainIdBridgesForUser;

    address[] internal pendingBridgesOut;
    address[] internal pendingBridgesIn;

    constructor(uint64 chainId) {
        _owner = msg.sender;
        _chainId = chainId;
    }

    /// @notice Adds a chain id to the current list of authorised chain Ids
    // If the chain is already registered, exit
    function addValidChainId(uint64 chainId) external _onlyOwner notSameChain(chainId) {
        for (uint i = 0; i < _validChainIds.length; i++) {
            if (_validChainIds[i] == chainId) return;
        }

        _validChainIds.push(chainId);
    }

    /// @notice Cancels a bridging request for msg.sender and for a chainId
    /// @param forChainId The target chain Id to cancel
    function cancelBridgeOut(uint64 forChainId) external onlyIfHavePendingRequest(forChainId) {
        this.revertBridgeRequestForUser(msg.sender, forChainId);
    }

    /// @notice Returns the array of addresses awaiting for bridging in
    function getPendingBridgesIn() external view _onlyOwner returns(address[] memory) {
        return pendingBridgesIn;
    }

    /// @notice Returns the array of addresses awaiting for bridging out
    function getPendingBridgesOut() external view _onlyOwner returns(address[] memory) {
        return pendingBridgesOut;
    }

    /// @notice Gets the pending bridges out for a user
    function getPendingBridgesOutForUser(address forUser) external view _onlyOwner returns(Bridge[] memory) {
        return getPendingBridges(forUser);
    }

    /// @notice Checks if msg.sender has a pending bridge to another chain
    function hasPendingBridgeIn() external view returns(uint128) {
        return pendingBridgingAmountsIn[msg.sender];
    }

    /// @notice Checks if msg.sender has a pending bridge to another chain
    function hasPendingBridgeOut() external view returns(Bridge[] memory) {
        return getPendingBridges(msg.sender);
    }

    /*******************
     * Virtual methods *
     *******************/
    /// @notice Adds a pending bridge in
    /// @param forUser The address of the beneficiary
    /// @param amount The amount
    function addPendingBridgeIn(address forUser, uint128 amount) external virtual;

    /// @notice Cancels a bridge in for a user
    /// @param forUser The address of the user to remove
    function cancelBridgeIn(address forUser) external virtual;

    /// @notice Adds a pending bridge out to a specific chain Id
    /// @param toChainId The destination Chain id
    /// @param amount The amount to be bridged out
    function requestBridgeOut(uint64 toChainId, uint128 amount) external virtual;

    /// @notice Cancels a bridging request for a user and for a chainId
    /// @param forUser The user address to cancel
    /// @param forChainId The target chain Id to cancel
    function revertBridgeRequestForUser(address forUser, uint64 forChainId) external virtual;

    /// @notice Validates a bridge in for a user and for a chain Id
    function validateBridgeOut(address forUser, uint64 forChainId) external virtual;

    /// @notice Validates a bridge in for a user
    function validateBridgeIn(address forUser) external virtual;


    /********************
     * Internal methods *
     ********************/
    // Adds a pending chain id for a user
    function addPendingChainIdToUser(address forUser, uint64 chainId) internal {
        uint64[] storage pendingBridges = pendingChainIdBridgesForUser[forUser];

        for (uint i = 0; i < pendingBridges.length; i++) {
            if (pendingBridges[i] == chainId) return;
        }

        pendingBridges.push(chainId);
    }

    // Adds a user to the bridges in
    function addUserForBridingIn(address user) internal {
        for (uint i = 0; i < pendingBridgesIn.length; i++) {
            if (pendingBridgesIn[i] == user) return;
        }

        pendingBridgesIn.push(user);
    }

    function removePendingBridgingOutForUser(address user, uint64 chainId) internal {
        uint64[] storage pendingBridges = pendingChainIdBridgesForUser[user];

        for (uint i = 0; i < pendingBridges.length; i++) {
            if (pendingBridges[i] == chainId) {
                pendingBridges[i] = pendingBridges[pendingBridges.length - 1];
                pendingBridges.pop();

                if (pendingBridges.length == 0) removeUserFromPendingBridgesOut(user);
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

    /*******************
     * Private methods *
     *******************/
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

    function getPendingBridges(address user) view private returns(Bridge[] memory) {
        uint64[] storage pendingBridges = pendingChainIdBridgesForUser[user];

        if (pendingBridges.length > 0) {
            Bridge[] memory result = new Bridge[](pendingBridges.length);

            for (uint i = 0; i < pendingBridges.length; i++) {
                uint64 chainId = pendingBridges[i];
                result[i] = Bridge(chainId, pendingBridgeOutAmountByChain[user][chainId]);
            }

            return result;
        }

        return new Bridge[](0);
    }
}