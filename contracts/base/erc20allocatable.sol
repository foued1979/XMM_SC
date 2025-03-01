// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import { ERC20CappedAndOwned } from "./utils/erc20cappedandowned.sol";
import { IERC20Errors } from "../interfaces/ierc20errors.sol";
import { ILinkToken } from "../interfaces/ilinktoken.sol";
import { IRouterClient } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract ERC20Allocatable is ERC20CappedAndOwned {
    address public immutable _ccipRouter;  // Chainlink CCIP Router
    address public immutable _linkToken;  // Chainlink CCIP Router

    /**********
     * Events *
     **********/
    /// @notice The Allocated event is triggered when Owner allocates some token to
    /// a beneficiary
    event Allocated(uint indexed timestamp, address indexed beneficiary, uint256 amount);

    /***************
     * Constructor *
     ***************/
    constructor(address owner_, address ccipRouter_, address linkToken_, uint32 initialSupply_, string memory name_, string memory symbol_, uint8 decimals_)
        ERC20CappedAndOwned(owner_, initialSupply_, name_, symbol_, decimals_)
        { 
            _ccipRouter = ccipRouter_;
            _linkToken = linkToken_;
        }

    /// @notice Allocates a number of token to a beneficiary
    /// @param to The beneficiary
    /// @param amount The amount
    function allocate(address to, uint256 amount) external onlyOwner {
        require(to != _owner, "Not allowed");
        if(amount > _availableTokens) revert ERC20InsufficientBalance(_owner, _availableTokens, amount);
        super._update(address(0), to, amount);

        emit Allocated(block.timestamp, to, amount);
    }

    /// @notice Allocates a number of token to a beneficiary
    /// @param to The beneficiaries
    /// @param amount The amounts
    function massAllocation(address[] memory to, uint256[] memory amount) external onlyOwner {
        require(to.length == amount.length, "Dim err");

        for (uint i = 0; i < to.length; i++) {
            this.allocate(to[i], amount[i]);
        }
    }

    /// @notice Sends a number of tokens to a receiver on another chain
    /// @param amount The amount to be sent
    /// @param destinationChain The destination chain
    /// @param receiver The address of the receiver
    function sendTokens(uint256 amount, uint64 destinationChain, address receiver) external {
        if (balanceOf(msg.sender) < amount) revert ERC20InsufficientBalance(msg.sender, balanceOf(msg.sender), amount);
        _burn(msg.sender, amount);  // Burn tokens on the source chain

        // Construct the message struct for CCIP
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),  // Encode the recipient address
            data: "",  // No additional payload data
            tokenAmounts: new Client.EVMTokenAmount[](1),  // Only one token transfer
            feeToken: _linkToken,  // Pay CCIP fees in LINK
            extraArgs: ""  // No extra arguments for now
        });

        // Define the token transfer inside the message
        message.tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(this),  // Address of this ERC20 token
            amount: amount
        });

        // Approve LINK token for CCIP fee payment
        ILinkToken(_linkToken).approve(_ccipRouter, type(uint256).max);

        // Send the message via Chainlink CCIP Router
        IRouterClient(_ccipRouter).ccipSend(destinationChain, message);
    }

    function receiveTokens(uint64 sourceChain, bytes memory payload) external {
        require(msg.sender == _ccipRouter, "Unauthorized sender");
        
        (address receiver, uint256 amount) = abi.decode(payload, (address, uint256));
        _mint(receiver, amount);
    }
}