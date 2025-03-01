// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import { ERC20ExchangeableAndBurnable } from "./base/erc20exchangeableandburnable.sol";
import { IERC20 } from "./interfaces/ierc20.sol";

contract Token is ERC20ExchangeableAndBurnable {
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
        ERC20ExchangeableAndBurnable(msg.sender, ccipRouter_, linkToken_, initialSupply_, name_, symbol_, 18) payable {
        allocateToOwner(uint256(initialOwnerAllocation_) * uint256(10 ** 18));
    }

    receive() external payable {
        emit Deposited(block.timestamp, msg.sender, msg.value, 0);
    }

    /// @notice Enables a user to deposit ETH and receive Tokens in exchange
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
        
        _allocatedAmount += amountToken;
        _availableTokens -= amountToken;

        emit Deposited(block.timestamp, msg.sender, amountETH, amountToken);
        emit Allocated(block.timestamp, msg.sender, amountToken);

        _balances[msg.sender] += amountToken;

        return amountToken;
    }

    /// @notice Enables owner to send back some tokens to the Token contract
    function ownerTransfersBack(uint256 amount) external onlyOwner {
        require((uint256)(amount) <= _balances[_owner], "Insuffient balance");

        _balances[_owner] -= amount;
        _allocatedAmount -= amount;
        _availableTokens += amount;
    }

    /// @notice Enables a user to sell back an amount of Tokens against ETH
    /// if there is enough ETH available, and if the change is authorized.
    /// Sold-back tokens are automatically burnt.
    /// @param amountToken The amount of tokens to be exchanged
    function sellBack(uint128 amountToken) external ethExchangeIsAllowed {
        require(_balances[msg.sender] >= amountToken, "Insufficient balance");

        uint256 amt256 = uint256(amountToken);
        uint256 amountETH = (amt256 * uint256(_precision)) / uint256(EthExchangeRate);
        uint256 availableQuantityOfETH = address(this).balance;

        if (amountETH > availableQuantityOfETH) {
            amountETH = availableQuantityOfETH;
            amountToken = uint128((amountETH * uint256(EthExchangeRate)) / uint256(_precision));
        }
        
        _balances[msg.sender] -= amt256;
        payable(msg.sender).transfer(amountETH);
        
        // Now we burn the tokens
        _allocatedAmount -= amt256;
        _totalSupply -= amt256;

        emit ChangedBack(block.timestamp, msg.sender, amountETH);
        emit Withdrawn(block.timestamp, msg.sender, amountToken);
        emit Burnt(block.timestamp, amt256);
    }

    /// @notice Enables a user to sell back an amount of Tokens against a preferred token
    /// if there is enough token available, and if the change is authorized.
    /// Sold-back tokens are automatically burnt.
    /// @param amountToken The amount of tokens to be exchanged
    /// @param tokenToBeReceived The address of the token to be exchanged for
    function sellBackAgainst(uint128 amountToken, address tokenToBeReceived) external exchangeIsAllowedForToken(tokenToBeReceived) {
        require(_balances[msg.sender] >= amountToken, "Insufficient balance");

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
        _balances[msg.sender] -= amt256;
        
        // Now we burn the tokens
        _allocatedAmount -= amt256;
        _totalSupply -= amt256;

        emit ChangedBackFor(block.timestamp, msg.sender, tokenToBeReceived, amountExpectedToken);
        emit Withdrawn(block.timestamp, msg.sender, amountToken);
        emit Burnt(block.timestamp, amt256);
    }

    /// @notice Enables the Owner to buy back tokens from a user, in exchange of ETH
    /// and at a specified rate
    /// @param from The beneficiary
    /// @param amountToken The amount of tokens
    /// @param rate The conversion rate
    function buyBack(address payable from, uint128 amountToken, uint64 rate) external onlyOwner {
        require(_balances[from] >= amountToken, "Insufficient balance");

        uint256 amountETH = (uint256(amountToken) * uint256(_precision)) / uint256(rate);
        uint256 availableQuantityOfETH = address(this).balance;

        // We make sure that the available quantity of ETH is bigger than the expected ETH amount
        // If not, we adjust down the quantity of token to be withdrawn
        if (amountETH > availableQuantityOfETH) {
            amountETH = availableQuantityOfETH;
            amountToken = uint128((amountETH * uint256(rate)) / uint256(_precision));
        }

        from.transfer(amountETH);
        _balances[from] -= uint256(amountToken);

        _allocatedAmount -= uint256(amountToken);
        _availableTokens += uint256(amountToken);

        emit ChangedBack(block.timestamp, from, amountETH);
        emit Withdrawn(block.timestamp, from, amountToken);
    }

    /*******************
     * Private methods *
     *******************/
    /// @notice Allocates a number of token to the owner
    /// @param amount The amount
    function allocateToOwner(uint256 amount) private {
        require(amount < _totalSupply);
        
        _allocatedAmount += amount;
        _balances[_owner] += amount;
        _availableTokens -= amount;

        emit Allocated(block.timestamp, _owner, amount);
    }
}