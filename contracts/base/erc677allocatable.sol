// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

import { DurationUnits } from  "../enums.sol";
import { ERC20Vested } from "./utils/erc20vested.sol";

import { IERC20 } from "../interfaces/ierc20.sol";
import { IERC20Errors } from "../interfaces/ierc20errors.sol";
import { IERC677Errors } from "../interfaces/ierc677errors.sol";

import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import { CCIPReceiver } from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { IRouterClient } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract ERC677Allocatable is ERC20Vested, CCIPReceiver {
    IRouterClient public immutable _ccipRouter;  // Chainlink CCIP Router
    IERC20 public immutable _linkToken;  // Chainlink CCIP Router

    /// @dev Modifier that checks if the chain with the given destinationChainSelector is allowed.
    /// @param _destinationChainSelector The selector of the destination chain.
    modifier onlyAllowlistedChain(uint64 _destinationChainSelector) {
        require(_allowlistedChains[_destinationChainSelector], "Chain err");
        _;
    }

    /**********
     * Events *
     **********/
    /// @dev The Allocated event is triggered when Owner allocates some token to
    /// a beneficiary
    event Allocated(uint indexed timestamp, address indexed beneficiary, uint256 amount);
    // Event emitted when the tokens are transferred to an account on another chain.
    event TokensTransferred(bytes32 indexed messageId, uint64 indexed destinationChainSelector, address receiver, uint256 tokenAmount, address feeToken, uint256 fees);
    // Event emitted when the tokens are received on another chain.
    event TokensReceived(uint indexed timestamp, address indexed receiver, address indexed sender, bytes32 messageId, uint256 amount);

    /**************
     * Properties *
     **************/
    // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 chainId => bool) private _allowlistedChains;

    /***************
     * Constructor *
     ***************/
    constructor(address owner_, address ccipRouter_, address linkToken_, uint32 initialSupply_, string memory name_, string memory symbol_, uint8 decimals_)
        ERC20Vested(owner_, initialSupply_, name_, symbol_, decimals_)
        CCIPReceiver(ccipRouter_)
    { 
        _ccipRouter = IRouterClient(ccipRouter_);
        _linkToken = IERC20(linkToken_);
    }

    /// @dev Allocates a number of token to a beneficiary
    /// @param to The beneficiary
    /// @param amount The amount to allocate
    /// @param cliffDuration The duration of the cliff
    /// @param cliffDurationUnit The unit of the cliff duration
    /// @param upfrontRelease The amount released when cliff period ends
    /// @param vestingDuration The duration of the vesting
    /// @param vestingDurationUnit The unit of the vesting duration
    function allocateWithVesting(address to, uint256 amount, uint16 cliffDuration, DurationUnits cliffDurationUnit, uint8 upfrontRelease, uint16 vestingDuration, 
    DurationUnits vestingDurationUnit) external onlyOwner {
        allocate(to, amount);

        uint vestingStart = _addDuration(block.timestamp, cliffDuration, cliffDurationUnit);

        if (upfrontRelease > 100) upfrontRelease = 100;
        _createVestingSchedule(to,upfrontRelease, vestingStart, vestingDuration, vestingDurationUnit, amount);
    }

    /// @dev Gets whether a chain id is allowed
    function isChainIdAllowed(uint64 chainId) external view returns(bool) {
        return _allowlistedChains[chainId];
    }

    /// @dev Updates the allowlist status of a destination chain for transactions.
    /// @dev This function can only be called by the owner.
    /// @param _destinationChainSelector The selector of the destination chain to be updated.
    /// @param allowed The allowlist status to be set for the destination chain.
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        _allowlistedChains[_destinationChainSelector] = allowed;
    }

    /// @dev Allocates a number of token to a beneficiary
    /// @param to The beneficiary
    /// @param amount The amount
    function allocate(address to, uint256 amount) public onlyOwner {
        require(to != _owner && to != address(0), "Err");
        super._update(address(0), to, amount);

        emit Allocated(block.timestamp, to, amount);
    }

    /// @dev Allocates a number of token to a beneficiary
    /// @param to The beneficiaries
    /// @param amount The amounts
    function massAllocation(address[] memory to, uint256[] memory amount) external onlyOwner {
        require(to.length == amount.length, "Err");

        for (uint i = 0; i < to.length; i++) {
            this.allocate(to[i], amount[i]);
        }
    }

    /// @dev Sends a number of tokens to a receiver on another chain
    /// Users MUST provide allowance to the CCIP router to enable the bridge:
    ///    - For LINK, the allowance is the fee required to send the message
    ///    - For the token, the allowance is the amount to be sent
    /// CCIP Router address is accessible via the getRouter() function
    /// @param amount The amount to be sent
    /// @param destinationChain The destination chain
    /// @param receiver The address of the receiver
    /// @param gasLimit The max amount of gas to be paid
    function sendTokensPayLINK(uint256 amount, uint64 destinationChain, address receiver, uint256 gasLimit) external 
    onlyAllowlistedChain(destinationChain) returns(bytes32 messageId) {
        if (receiver == address(0)) revert ERC20InvalidReceiver(receiver);

        uint256 availableBalance = _releaseTokens(msg.sender, amount);
        if (availableBalance < amount) revert ERC20InsufficientBalance(msg.sender, availableBalance, amount);

        Client.EVM2AnyMessage memory message = _buildCCIPMessage(receiver, amount, address(_linkToken), gasLimit);

        // Get the fee required to send the message
        uint256 fees = _ccipRouter.getFee(destinationChain, message);
        if (fees > _linkToken.balanceOf(msg.sender)) revert ERC20InsufficientBalance(msg.sender, _linkToken.balanceOf(msg.sender), fees);
        
        // Check allowances
        // First, we check that the token has an allowance for the fees, approved by msg.sender
        if (fees > _linkToken.allowance(msg.sender, i_ccipRouter)) 
            revert IERC677Errors.ERC677InsufficientCCIPRouterAllowance(msg.sender, i_ccipRouter, address(_linkToken), fees);
        // Then, we check that the token has an allowance for the amount, approved by msg.sender
        if (amount > this.allowance(msg.sender, i_ccipRouter)) 
            revert IERC677Errors.ERC677InsufficientCCIPRouterAllowance(msg.sender, i_ccipRouter, address(this), amount);

        // Send the message via Chainlink CCIP Router
        messageId = _ccipRouter.ccipSend(destinationChain, message);
        _update(msg.sender, address(0), amount); // Tokens are removed from sender balance and from supply

        // Emit an event with message details
        emit TokensTransferred(messageId, destinationChain, receiver, amount, address(_linkToken), fees);
    }
    
    /// @dev Receives tokens from another chain
    /// @param message The transfer message sent by the CCIP Router
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        address sender = abi.decode(message.sender, (address));
        address receiver = abi.decode(message.data, (address));
        uint256 amount = message.destTokenAmounts[0].amount;

        _update(address(0), receiver, amount);
        emit TokensReceived(block.timestamp, receiver, sender, message.messageId, amount);
    }

    /// @dev Construct a CCIP message.
    /// @dev This function will create an EVM2AnyMessage struct with all the necessary information for tokens transfer.
    /// @param receiver The address of the receiver.
    /// @param amount The amount of the token to be transferred.
    /// @param feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    function _buildCCIPMessage(address receiver, uint256 amount, address feeTokenAddress, uint256 gasLimit) private view returns (Client.EVM2AnyMessage memory) {
        // Set the token amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(this),
            amount: amount
        });

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(receiver), // ABI-encoded receiver address
                data: "", // No data
                tokenAmounts: tokenAmounts, // The amount and type of token being transferred
                extraArgs: Client._argsToBytes(
                    // Additional arguments, setting gas limit and allowing out-of-order execution.
                    Client.EVMExtraArgsV1({
                        gasLimit: gasLimit // Gas limit for the callback on the destination chain
                    })
                ),
                // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
                feeToken: feeTokenAddress
            });
    }
}