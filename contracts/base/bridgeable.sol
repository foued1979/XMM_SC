// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../libraries/safemath.sol";
import "../structures/bridge.sol";

abstract contract Bridgeable {
    event BridgeOutRequested(uint indexed timestamp, address indexed from, uint64 toChainId, uint128 amount);
    event BridgeOutValidated(uint indexed timestamp, address indexed forUser, uint64 toChainId, uint128 amount);
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
        require(chainId != _chainId && chainIsValid(chainId), "Chain err");
        _;
    }

    //modifier onlyIfHavePendingRequest(uint64 onChainId) {
    //    require(pendingBridgeOutAmountByChain[msg.sender][onChainId] > 0);
    //    _;
    //}

    // Properties
    address private _owner;
    uint64 internal _chainId;
    uint64[] private _validChainIds;

    mapping(address => mapping(uint64 => uint128)) internal pendingBridgeInAmountByChain;
    mapping(address => uint64[]) internal pendingChainIdBridgesInForUser;

    mapping(address => mapping(uint64 => uint128)) internal pendingBridgeOutAmountByChain;
    mapping(address => uint64[]) internal pendingChainIdBridgesOutForUser;

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
    //function cancelBridgeOut(uint64 forChainId) external onlyIfHavePendingRequest(forChainId) {
    //    this.revertBridgeOutRequestForUser(msg.sender, forChainId);
    //}

    /// @notice Gets the list of valid chain Ids for which bridge is possible
    function getValidChainIds() external view returns(uint64[] memory) {
        return _validChainIds;
    }

    /// @notice Returns the array of addresses awaiting for bridging in
    function getPendingBridgesIn() external view _onlyOwner returns(address[] memory) {
        return pendingBridgesIn;
    }

    /// @notice Returns the array of addresses awaiting for bridging out
    function getPendingBridgesOut() external view _onlyOwner returns(address[] memory) {
        return pendingBridgesOut;
    }

    /// @notice Gets the pending bridges-in for a user
    function getPendingBridgesInForUser(address forUser) external view _onlyOwner returns(Bridge[] memory) {
        uint64[] storage pendingChainIdBridges = pendingChainIdBridgesInForUser[forUser];

        if (pendingChainIdBridges.length > 0) {
            Bridge[] memory result = new Bridge[](pendingChainIdBridges.length);

            for (uint i = 0; i < pendingChainIdBridges.length; i++) {
                uint64 chainId = pendingChainIdBridges[i];
                uint128 amt = pendingBridgeInAmountByChain[forUser][chainId];
                
                result[i] = Bridge(chainId, amt);
            }

            return result;
        }

        return new Bridge[](0);
    }

    /// @notice Gets the pending bridges-out for a user
    function getPendingBridgesOutForUser(address forUser) external view _onlyOwner returns(Bridge[] memory) {
        uint64[] storage pendingChainIdBridges = pendingChainIdBridgesOutForUser[forUser];

        if (pendingChainIdBridges.length > 0) {
            Bridge[] memory result = new Bridge[](pendingChainIdBridges.length);

            for (uint i = 0; i < pendingChainIdBridges.length; i++) {
                uint64 chainId = pendingChainIdBridges[i];
                uint128 amt = pendingBridgeOutAmountByChain[forUser][chainId];
                
                result[i] = Bridge(chainId, amt);
            }

            return result;
        }

        return new Bridge[](0);
    }

    /// @notice Checks if msg.sender has a pending bridge to another chain
    function hasPendingBridgeIn() external view returns(Bridge[] memory) {
        return this.getPendingBridgesInForUser(msg.sender);
    }

    /// @notice Checks if msg.sender has a pending bridge to another chain
    function hasPendingBridgeOut() external view returns(Bridge[] memory) {
        return this.getPendingBridgesOutForUser(msg.sender);
    }

    /*******************
     * Virtual methods *
     *******************/
    /// @notice Adds a pending bridge in
    /// @param forUser The address of the beneficiary
    /// @param fromChainId The chainId where the bridge is coming from
    /// @param amount The amount
    function addPendingBridgeIn(address forUser, uint64 fromChainId, uint128 amount) external virtual;

    /// @notice Cancels a bridge in for a user
    /// @param forUser The address of the user to remove
    /// @param fromChainId The chainId where the bridge is coming from
    function cancelBridgeIn(address forUser, uint64 fromChainId) external virtual;

    /// @notice Adds a pending bridge out to a specific chain Id
    /// @param toChainId The destination Chain id
    /// @param amount The amount to be bridged out
    function requestBridgeOut(uint64 toChainId, uint128 amount) external virtual;

    /// @notice Cancels a bridging request for a user and for a chainId
    /// @param forUser The user address to cancel
    /// @param forChainId The target chain Id to cancel
    function revertBridgeOutRequestForUser(address forUser, uint64 forChainId) external virtual;

    /// @notice Validates a bridge in for a user and for a chain Id
    function validateBridgeOut(address forUser, uint64 forChainId) external virtual;

    /// @notice Validates a bridge in for a user
    /// @param forUser The user to validate
    /// @param forChainId The chain id where the bridge is coming from
    function validateBridgeIn(address forUser, uint64 forChainId) external virtual;


    /********************
     * Internal methods *
     ********************/
    // Adds a pending chain id for a user
    function addPendingChainIdBridgeToUser(uint64[] storage pendingChainIdBridgesForUser, uint64 chainId) internal {
        for (uint i = 0; i < pendingChainIdBridgesForUser.length; i++) {
            if (pendingChainIdBridgesForUser[i] == chainId) return;
        }

        pendingChainIdBridgesForUser.push(chainId);
    }

    // Adds a user to the bridges-in
    function addUserForBridingIn(address user) internal {
        for (uint i = 0; i < pendingBridgesIn.length; i++) {
            if (pendingBridgesIn[i] == user) return;
        }

        pendingBridgesIn.push(user);
    }

    // Adds a user to the bridges-out
    function addUserForBridingOut(address user) internal {
        for (uint i = 0; i < pendingBridgesOut.length; i++) {
            if (pendingBridgesOut[i] == user) return;
        }

        pendingBridgesOut.push(user);
    }

    function removePendingChainIdBridgeForUser(address forUser, address[] storage pendingUsers, uint64[] storage pendingChainIdBridgesForUser, uint64 chainId) internal {
        for (uint i = 0; i < pendingChainIdBridgesForUser.length; i++) {
            if (pendingChainIdBridgesForUser[i] == chainId) {
                pendingChainIdBridgesForUser[i] = pendingChainIdBridgesForUser[pendingChainIdBridgesForUser.length - 1];
                pendingChainIdBridgesForUser.pop();

                if (pendingChainIdBridgesForUser.length == 0) removeUserFromPendingBridges(forUser, pendingUsers);
                return;
            }
        }
    }

    /*******************
     * Private methods *
     *******************/
    function removeUserFromPendingBridges(address user, address[] storage pendingUsers) private {
        for (uint i = 0; i < pendingUsers.length; i++) {
            if (pendingUsers[i] == user) {
                pendingUsers[i] = pendingUsers[pendingUsers.length - 1];
                pendingUsers.pop();
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