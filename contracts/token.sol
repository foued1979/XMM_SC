// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./base/allocatable.sol";
import "./base/exchangeable.sol";
import "./libraries/safemath.sol";

contract Token is Allocatable, Exchangeable {
    /**********
     * Events *
     **********/
    /// @notice The Burnt event is triggered when tokens are burnt
    event Burnt(uint indexed timstamp, uint256 amount);
    event Deposited(uint indexed timestamp, address indexed from, uint256 amountETH, uint256 amountToken);
    event ChangedBack(uint indexed timestamp, address indexed beneficiary, uint256 amountTokens);
    event ChangedBackFor(uint indexed timestamp, address indexed beneficiary, address tokenReceived, uint256 amount);
    event Withdrawn(uint indexed timestamp, address indexed from, uint256 amount);    

    /**************
     * Properties *
     **************/
     // Public Properties
    string public Name;

    constructor(string memory symbol, string memory name, uint64 chainId, uint32 initialSupply, uint32 initialOwnerAllocation) 
        Allocatable(symbol, initialSupply, uint8(18)) Exchangeable(chainId) payable {

        Name = name;
        allocateToOwner(uint256(initialOwnerAllocation) * uint256(10 ** 18));
    }

    receive() external payable {
        emit Deposited(block.timestamp, msg.sender, msg.value, 0);
    }

    /// @notice Burns a number of token
    /// @param amount The amount to be allocated
    function burn(uint256 amount) external onlyOwner {
        require(amount <= AvailableTokens, "Burn failed");
        TotalSupply = SafeMath.sub(TotalSupply, amount);
        AvailableTokens = SafeMath.sub(AvailableTokens, amount);
        
        emit Burnt(block.timestamp, amount);
    }

    /// @notice Enables a user to deposit ETH and receive Tokens in exchange
    /// The conversion rate applies at a fixed rate, updated by Owner
    function depositEther() external payable ethDepositIsAllowed returns(uint256) {
        uint256 amountETH = msg.value;
        if (amountETH == 0) return 0;

        uint256 amountToken = uint256((amountETH * uint256(EthExchangeRate)) / uint256(_precision));
        
        if (amountToken > AvailableTokens) {
            // We compute the number of ETH corresponding to the amount of tokens available
            amountETH = (AvailableTokens * uint256(_precision)) / uint256(EthExchangeRate);
            amountToken = AvailableTokens;

            address payable receiver = payable(msg.sender);
            // We transfer back extra ETH to the msg.sender
            receiver.transfer(msg.value - amountETH);
        }
        
        AllocatedAmount = SafeMath.add(AllocatedAmount, amountToken);
        AvailableTokens = SafeMath.add(AvailableTokens, amountToken);

        emit Deposited(block.timestamp, msg.sender, amountETH, amountToken);
        emit Allocated(block.timestamp, msg.sender, amountToken);

        _balances[msg.sender] += amountToken;

        return amountToken;
    }

    /// @notice Enables owner to send back some tokens to the Token contract
    function ownerTransfersBack(uint256 amount) external onlyOwner {
        require((uint256)(amount) <= _balances[Owner], "Insuffient balance");

        _balances[Owner] = SafeMath.sub(_balances[Owner], amount);

        AllocatedAmount = SafeMath.sub(AllocatedAmount, amount);
        AvailableTokens = SafeMath.add(AvailableTokens, amount);
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
        
        _balances[msg.sender] = SafeMath.sub(_balances[msg.sender], amt256);
        payable(msg.sender).transfer(amountETH);
        
        // Now we burn the tokens
        AllocatedAmount = SafeMath.sub(AllocatedAmount, amt256);
        TotalSupply = SafeMath.sub(TotalSupply, amt256);

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
        _balances[msg.sender] = SafeMath.sub(_balances[msg.sender], amt256);
        
        // Now we burn the tokens
        AllocatedAmount = SafeMath.sub(AllocatedAmount, amt256);
        TotalSupply = SafeMath.sub(TotalSupply, amt256);

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
        _balances[from] = SafeMath.sub(_balances[from], uint256(amountToken));

        AllocatedAmount = SafeMath.sub(AllocatedAmount, uint256(amountToken));
        AvailableTokens = SafeMath.add(AvailableTokens, uint256(amountToken));

        emit ChangedBack(block.timestamp, from, amountETH);
        emit Withdrawn(block.timestamp, from, amountToken);
    }

    /*********************************
     * The Bridgeable Implementation *
     *********************************/

    /// @notice Adds a pending bridge in
    /// @param forUser The address of the beneficiary
    /// @param fromChainId The chainId where the bridge is coming from
    /// @param amount The amount
    function addPendingBridgeIn(address forUser, uint64 fromChainId, uint128 amount) external override onlyOwner {
        require(AvailableTokens >= uint256(amount), "Insufficient balance");
        
        pendingBridgeInAmountByChain[forUser][fromChainId] = SafeMath.add128(pendingBridgeInAmountByChain[forUser][fromChainId], amount);
        addUserForBridingIn(forUser);

        AvailableTokens = SafeMath.sub(AvailableTokens, amount);
    }

    /// @notice Cancels a bridge in for a user
    /// @param forUser The address of the user to remove
    /// @param fromChainId The chainId where the bridge is coming from
    function cancelBridgeIn(address forUser, uint64 fromChainId) external override onlyOwner {
        uint256 pendingAmt = uint256(pendingBridgeInAmountByChain[forUser][fromChainId]);

        AvailableTokens = SafeMath.add(AvailableTokens, pendingAmt);
        pendingBridgeInAmountByChain[forUser][fromChainId] = 0;
        
        removePendingChainIdBridgeForUser(forUser, pendingBridgesIn, pendingChainIdBridgesInForUser[forUser], fromChainId);
    }

    /// @notice Adds a pending bridge out to a specific chain Id
    /// @param toChainId The destination Chain id
    /// @param amount The amount to be bridged out
    function requestBridgeOut(uint64 toChainId, uint128 amount) external override isValidChain(toChainId) {
        address user = msg.sender;

        require(_balances[user] >= amount, "Insufficient balance");

        pendingBridgeOutAmountByChain[user][toChainId] = SafeMath.add128(pendingBridgeOutAmountByChain[user][toChainId], amount);
        _balances[user] = SafeMath.sub(_balances[user], uint256(amount));

        addUserForBridingOut(user);
        addPendingChainIdBridgeToUser(pendingChainIdBridgesOutForUser[user], toChainId);

        emit BridgeOutRequested(block.timestamp, user, toChainId, amount);
    }

    /// @notice Cancels a bridging request for a user and for a chainId
    /// @param forUser The user address to cancel
    /// @param forChainId The target chain Id to cancel
    function cancelBridgeOut(address forUser, uint64 forChainId) external override onlyOwner {
        if (pendingBridgeOutAmountByChain[forUser][forChainId] == 0) return;

        // We credit back the tokens to the user
        _balances[forUser] = SafeMath.add(_balances[forUser], uint256(pendingBridgeOutAmountByChain[forUser][forChainId]));
        pendingBridgeOutAmountByChain[forUser][forChainId] = 0;

        removePendingChainIdBridgeForUser(forUser, pendingBridgesOut, pendingChainIdBridgesOutForUser[forUser], forChainId);

        emit BridgeOutCancelled(block.timestamp, forUser, forChainId);
    }

    /// @notice Validates a bridge in for a user and for a chain Id
    function validateBridgeOut(address forUser, uint64 forChainId) external override onlyOwner {
        // We add the bridge quantity back to the available tokens
        uint128 amt = pendingBridgeOutAmountByChain[forUser][forChainId];
        
        AllocatedAmount = SafeMath.sub(AllocatedAmount, uint256(amt));
        AvailableTokens = SafeMath.add(AvailableTokens, uint256(amt));

        pendingBridgeOutAmountByChain[forUser][forChainId] = 0;
        removePendingChainIdBridgeForUser(forUser, pendingBridgesOut, pendingChainIdBridgesOutForUser[forUser], forChainId);

        emit BridgeOutValidated(block.timestamp, forUser, forChainId, amt);
    }

    /// @notice Validates a bridge in for a user
    /// @param forUser The user to validate
    /// @param forChainId The chain id where the bridge is coming from
    function validateBridgeIn(address forUser, uint64 forChainId) external override onlyOwner {
        uint256 amtToCredit = uint256(pendingBridgeInAmountByChain[forUser][forChainId]);
        
        _balances[forUser] = SafeMath.add(_balances[forUser], amtToCredit);
        AllocatedAmount = SafeMath.add(AllocatedAmount, amtToCredit);

        removePendingChainIdBridgeForUser(forUser, pendingBridgesIn, pendingChainIdBridgesInForUser[forUser], forChainId);
    }

    /*******************
     * Private methods *
     *******************/
    /// @notice Allocates a number of token to the owner
    /// @param amount The amount
    function allocateToOwner(uint256 amount) private {
        require(amount < TotalSupply);
        
        AllocatedAmount = SafeMath.add(AllocatedAmount, amount);
        _balances[Owner] = SafeMath.add(_balances[Owner], amount);
        AvailableTokens = SafeMath.sub(TotalSupply, amount);

        emit Allocated(block.timestamp, Owner, amount);
    }
}