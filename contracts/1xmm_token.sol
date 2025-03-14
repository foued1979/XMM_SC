// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

import { IERC20Errors } from "./interfaces/ierc20errors.sol";
import { IERC20 } from "./interfaces/ierc20.sol";

import { ERC677Allocatable } from "./base/erc677allocatable.sol";
import { ERC20Exchangeable } from "./base/erc20exchangeable.sol";

import {console} from "hardhat/console.sol";

contract OneXMM is ERC677Allocatable, ERC20Exchangeable {
    /**********
     * Events *
     **********/
    event Deposited(uint indexed timestamp, address indexed from, uint256 amountETH, uint256 amountToken);
    event ChangedBack(uint indexed timestamp, address indexed beneficiary, uint256 amountTokens);
    event ChangedBackFor(uint indexed timestamp, address indexed beneficiary, address tokenReceived, uint256 amount);
    event Withdrawn(uint indexed timestamp, address indexed from, uint256 amount);    

    /**
     * @dev Constructor
     * @param symbol_ The symbol of the token
     * @param name_ The name of the token
     * @param initialSupply_ The initial supply
     * @param initialOwnerAllocation_ The initial allocation to the owner
     */
    constructor(string memory symbol_, address ccipRouter_, address linkToken_,  string memory name_, uint32 initialSupply_, uint32 initialOwnerAllocation_)
        ERC677Allocatable(msg.sender, ccipRouter_, linkToken_, initialSupply_, name_, symbol_, 18)
        ERC20Exchangeable(msg.sender) payable {
        _allocateToOwner(uint256(initialOwnerAllocation_) * uint256(10 ** 18));
    }

    receive() external payable {
        emit Deposited(block.timestamp, msg.sender, msg.value, 0);
    }

    /// @dev Enables a user to deposit ETH and receive Tokens in exchange
    /// The conversion rate applies at a fixed rate, updated by Owner
    function depositEther() external payable ethDepositIsAllowed returns(uint256) {
        uint256 amountETH = msg.value;
        if (amountETH == 0) return 0;

        uint256 amountToken = uint256((amountETH * uint256(EthExchangeRate)) / uint256(_precision));
        
        if (amountToken > _availableTokens) {
            // We compute the number of ETH corresponding to the amount of tokens available
            amountETH = (_availableTokens * uint256(_precision)) / uint256(EthExchangeRate);
            amountToken = _availableTokens;

            address payable receiver = payable(msg.sender);
            // We transfer back extra ETH to the msg.sender
            receiver.transfer(msg.value - amountETH);
        }

        _update(address(0), msg.sender, amountToken);

        emit Deposited(block.timestamp, msg.sender, amountETH, amountToken);
        emit Allocated(block.timestamp, msg.sender, amountToken);

        return amountToken;
    }

    /// @dev Enables owner to send back some tokens to the Token contract
    function ownerTransfersBack(uint256 amount) external onlyOwner {
        if (amount > balanceOf(_owner)) revert IERC20Errors.ERC20InsufficientBalance(_owner, balanceOf(_owner), amount);
        _update(_owner, address(0), amount);
    }

    /// @dev Enables a user to sell back an amount of Tokens against ETH
    /// if there is enough ETH available, and if the change is authorized.
    /// Sold-back tokens are automatically burnt.
    /// @param amountToken The amount of tokens to be exchanged
    function sellBack(uint128 amountToken) external ethExchangeIsAllowed {
        if (balanceOf(msg.sender) < uint256(amountToken)) revert IERC20Errors.ERC20InsufficientBalance(msg.sender, balanceOf(msg.sender), amountToken);
        
        uint256 amt256 = uint256(amountToken);
        uint256 amountETH = (amt256 * uint256(_precision)) / uint256(EthExchangeRate);
        uint256 availableQuantityOfETH = address(this).balance;

        if (amountETH > availableQuantityOfETH) {
            amountETH = availableQuantityOfETH;
            amountToken = uint128((amountETH * uint256(EthExchangeRate)) / uint256(_precision));
        }
        
        payable(msg.sender).transfer(amountETH);
        
        // Now we burn the tokens
        burn(amountToken);

        emit ChangedBack(block.timestamp, msg.sender, amountETH);
        emit Withdrawn(block.timestamp, msg.sender, amountToken);
    }

    /// @dev Enables a user to sell back an amount of Tokens against a preferred token
    /// if there is enough token available, and if the change is authorized.
    /// Sold-back tokens are automatically burnt.
    /// @param amountToken The amount of tokens to be exchanged
    /// @param tokenToBeReceived The address of the token to be exchanged for
    function sellBackAgainst(uint128 amountToken, address tokenToBeReceived) external exchangeIsAllowedForToken(tokenToBeReceived) {
        if (balanceOf(msg.sender) < uint256(amountToken)) revert IERC20Errors.ERC20InsufficientBalance(msg.sender, balanceOf(msg.sender), amountToken);

        uint8 decimalAdjust = 18 - _approvedTokenDecimals[tokenToBeReceived];
        uint256 amt256 = uint256(amountToken);

        uint256 amountExpectedToken = (amt256 * uint256(_precision)) / uint256(_exchangeRates[tokenToBeReceived]);
        if (decimalAdjust != 0) amountExpectedToken /= (10 ** decimalAdjust);
        uint256 availableQuantity = getAvailableQuantityOfToken(tokenToBeReceived);

        // We make sure that the available quantity of expected token is bigger than the requested amount of expected token
        if (amountExpectedToken > availableQuantity) {
            amountExpectedToken = availableQuantity;
            // We adjust down the quantity of token to be delivered
            amountToken = uint128((amountExpectedToken * uint256(_exchangeRates[tokenToBeReceived])) / uint256(_precision));
        }
        
        // We transfer the expected to token to msg.sender
        // Then, we adjust msg.sender's balance
        IERC20(tokenToBeReceived).transfer(msg.sender, amountExpectedToken);
        
        // Now we burn the tokens
        burn(amountToken);

        emit ChangedBackFor(block.timestamp, msg.sender, tokenToBeReceived, amountExpectedToken);
        emit Withdrawn(block.timestamp, msg.sender, amountToken);
    }

    /// @dev Enables the Owner to buy back tokens from a user, in exchange of ETH
    /// and at a specified rate
    /// @param from The beneficiary
    /// @param amountToken The amount of tokens
    /// @param rate The conversion rate
    function buyBack(address payable from, uint128 amountToken, uint64 rate) external onlyOwner {
        if (from == address(0)) revert IERC20Errors.ERC20InvalidReceiver(from);
        if (balanceOf(from) < uint256(amountToken)) revert IERC20Errors.ERC20InsufficientBalance(msg.sender, balanceOf(msg.sender), amountToken);

        uint256 availableQuantityOfETH = address(this).balance;
        require (availableQuantityOfETH != 0, "BBack err");

        uint256 amountETH = (uint256(amountToken) * uint256(_precision)) / uint256(rate); 

        // We make sure that the available quantity of ETH is bigger than the expected ETH amount
        // If not, we adjust down the quantity of token to be withdrawn
        if (amountETH > availableQuantityOfETH) {
            amountETH = availableQuantityOfETH;
            amountToken = uint128((amountETH * uint256(rate)) / uint256(_precision));
        }

        // We check the allowance first
        // If allowance is not enough, it triggers an error
        _spendAllowance(from, _owner, amountToken);

        from.transfer(amountETH);
        _update(from, address(0), amountToken); // In this case, we don't burn the tokens; tokens can be reallocated.

        emit ChangedBack(block.timestamp, from, amountETH);
        emit Withdrawn(block.timestamp, from, amountToken);
    }

    /*******************
     * Private methods *
     *******************/
    /// @dev Allocates a number of token to the owner
    /// @param amount The amount
    function _allocateToOwner(uint256 amount) private {
        require(amount < _cap);
        
        _update(address(0), _owner, amount);
        emit Allocated(block.timestamp, _owner, amount);
    }
}