// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

abstract contract Owned {
    /**********
     * Events *
     **********/
     event OwnerChanged(uint indexed timestamp, address prevOwner, address newOwner);

     /*****************
     * The modifiers *
     *****************/
    modifier onlyOwner {
        require(msg.sender == Owner, "Owner err");
        _;
    }

    // Public Properties
    address public Owner;

    bool public IsActivated;

    constructor(address owner) {
        Owner = owner;
    }

    /// @notice Changes the ownership of the contract
    function changeOwnership(address newOwner, bool activationStatus) external onlyOwner {
        IsActivated = activationStatus;
        
        Owner = newOwner;
        emit OwnerChanged(block.timestamp, msg.sender, newOwner);
    }

    function changePoolActivation(bool status) external onlyOwner {
        IsActivated = status;
    }
}