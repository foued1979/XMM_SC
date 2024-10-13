// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./erc20.sol";

contract Allocatable is ERC20 {
    /**********
     * Events *
     **********/
    /// @notice The Allocated event is triggered when Owner allocates some token to
    /// a beneficiary
    event Allocated(uint indexed timestamp, address indexed beneficiary, uint256 amount);

    /**************
     * Properties *
     **************/
    // Public Properties
    uint256 public AllocatedAmount;
    uint256 public AvailableTokens;

    /***************
     * Constructor *
     ***************/
    constructor(string memory symbol, uint32 initialSupply, uint8 decimals) ERC20(symbol, initialSupply, decimals) {
        AvailableTokens = TotalSupply;
    }

    /// @notice Allocates a number of token to a beneficiary
    /// @param to The beneficiary
    /// @param amount The amount
    function allocate(address to, uint256 amount) external onlyOwner {
        require(to != Owner, "No no");
        require(amount <= AvailableTokens, "Insufficient supply");

        _balances[to] = SafeMath.add(_balances[to], amount);
        AllocatedAmount = SafeMath.add(AllocatedAmount, amount);
        AvailableTokens = SafeMath.sub(AvailableTokens, amount);

        emit Allocated(block.timestamp, to, amount);
    }
}