// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./base/allocatable.sol";
import "./base/bridgeable.sol";
import "./interfaces/iexchangeable.sol";
import "./libraries/safemath.sol";

contract Token is Allocatable, Bridgeable, IExchangeable {
    /**********
     * Events *
     **********/
    /// @notice The Burnt event is triggered when tokens are burnt
    event Burnt(uint indexed timstamp, uint256 amount);

    /*************
     * Modifiers *
     *************/
    modifier ethDepositIsAllowed {
        require(ETHDepositIsAllowed, "Not allowed");
        _;
    }

    modifier ethExchangeIsAllowed {
        require(ETHExchangeIsAllowed && EthExchangeRate != 0, "Not allowed");
        _;
    }

    modifier exchangeIsAllowedForToken(address token) {
        require(_tokenIsApproved[token] && _exchangeIsAllowed[token] && _exchangeRates[token] != 0, "Not allowed");
        _;
    }

    modifier tokenIsApproved(address token) {
        require(_tokenIsApproved[token], "Not approved");
        _;
    }

    /**************
     * Properties *
     **************/
     // Public Properties
    string public Name;

    // Public properties linked to IExchangeable
    // The exchange rate represents a real number with 4 digits precision
    bool public ETHExchangeIsAllowed;
    bool public ETHDepositIsAllowed;
    uint64 public EthExchangeRate;
    uint16 private _precision = 10_000;

    // Other public Properties
    address[] public ApprovedTokens;

    // Parameters to manage other token exchanges
    mapping(address => bool) private _tokenIsApproved;
    mapping(address => uint64) private _exchangeRates;
    mapping(address => bool) private _exchangeIsAllowed;

    constructor(string memory symbol, string memory name, uint64 chainId, uint32 initialSupply, uint32 initialOwnerAllocation) 
        Allocatable(symbol, initialSupply, uint8(18)) Bridgeable(chainId) payable {

        Name = name;
        ETHDepositIsAllowed = false;
        ETHExchangeIsAllowed = false;
        allocateToOwner(uint256(initialOwnerAllocation) * uint256(10 ** 18));
    }

    /// @notice Burns a number of token
    /// @param amount The amount to be allocated
    function burn(uint256 amount) external onlyOwner {
        require(amount <= AvailableTokens, "Burn failed");

        TotalSupply = SafeMath.sub(TotalSupply, amount);
        AvailableTokens = SafeMath.sub(AvailableTokens, amount);
        
        emit Burnt(block.timestamp, amount);
    }

    /// @notice Sets the change authorization status for ETH to false
    function removeETHExchangeAuthorization() external onlyOwner {
        ETHExchangeIsAllowed = false;
    }

    /// @notice Sets the change authorization status for a token to false
    function removeExchangeAuthorization(address tokenToBeReceived) external onlyOwner tokenIsApproved(tokenToBeReceived) {
        _exchangeIsAllowed[tokenToBeReceived] = false;
    }

    /// @notice Sets whether the deposit of ETH against token is allowed or not
    //          The exchange rate is expressed in pips
    function setETHDepositExchangeRate(uint64 exchangeRate) external onlyOwner {
        EthExchangeRate = exchangeRate;
        ETHDepositIsAllowed = true;
    }

    /// @notice Sets the ETH deposit authorization to false
    function removeETHDepositAuthorization() external onlyOwner {
        ETHDepositIsAllowed = false;
    }

    /// @notice Updates the exchange rate between ETH and the Token
    //          The exchange rate is expressed in pips
    function updateETHExchangeRate(uint64 exchangeRate) external onlyOwner {
        EthExchangeRate = exchangeRate;
        ETHExchangeIsAllowed = true;
    }

    /// @notice Updates the exchange rate between a token and our Token
    /// @param  tokenToBeReceived The token to be received in exchange of our Token
    /// @param  exchangeRate The exchange rate, with 4 digits precision (in pips)
    function updateTokenExchangeRate(address tokenToBeReceived, uint64 exchangeRate) external onlyOwner tokenIsApproved(tokenToBeReceived) {
        _exchangeRates[tokenToBeReceived] = exchangeRate;
        _exchangeIsAllowed[tokenToBeReceived] = true;
    }
    
    /// @notice Returns the quantity of ETH available for change against Token
    function getAvailableQuantityOfETH() external view returns(uint256) {
        return address(this).balance;
    }

    /// @notice Returns the latest exchange rate associated to the token to be received
    /// @return Whether the exchange is authorized and the latest exchange rate
    function getExchangeRate(address tokenToBeReceived) external view tokenIsApproved(tokenToBeReceived) returns(bool, uint64) {
        return (_exchangeIsAllowed[tokenToBeReceived], _exchangeRates[tokenToBeReceived]);
    }

    /// @notice Returns the available quantity of a token to be exchanged against our Token
    function getAvailableQuantityOfToken(address tokenToBeReceived) public tokenIsApproved(tokenToBeReceived) returns(uint256) {
        (bool success , bytes memory res) = tokenToBeReceived.call(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));

        require(success, "Comm error");
        return abi.decode(res, (uint256));
    }

    /// @notice Adds a token which can be traded against our Token
    function addApprovedToken(address token) external onlyOwner {
        if (_tokenIsApproved[token]) return;
        _tokenIsApproved[token] = true;
        _exchangeIsAllowed[token] = false;
        ApprovedTokens.push(token);
    }

    /// @notice Gets approved tokens
    function getApprovedTokens() external view returns(address[] memory) {
        return ApprovedTokens;
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

    /// @notice Deposits ETH for future token exchange
    function depositEtherForExchange() external payable onlyOwner {
        uint256 amountETH = msg.value;
        if (amountETH == 0) return;

        emit Deposited(block.timestamp, msg.sender, amountETH, 0);
    }

    /// @notice Enables owner to send back some tokens to the Token contract
    function ownerTransfersBack(uint256 amount) external onlyOwner {
        require((uint256)(amount) <= _balances[Owner], "Insuffient balance");

        _balances[Owner] = SafeMath.sub(_balances[Owner], amount);

        AllocatedAmount = SafeMath.sub(AllocatedAmount, amount);
        AvailableTokens = SafeMath.add(AvailableTokens, amount);
    }

    /// @notice Enables a user to sell back an amount of Tokens against ETH
    /// if there is enough ETH available, and if the change is authorized
    /// @param amountToken The amount of tokens to be exchanged
    function sellBack(uint128 amountToken) external ethExchangeIsAllowed {
        require(_balances[msg.sender] >= amountToken, "Insufficient balance");

        uint256 amountETH = (uint256(amountToken) * uint256(_precision)) / uint256(EthExchangeRate);
        uint256 availableQuantityOfETH = address(this).balance;

        if (amountETH > availableQuantityOfETH) {
            amountETH = availableQuantityOfETH;
            amountToken = uint128((amountETH * uint256(EthExchangeRate)) / uint256(_precision));
        }
        
        _balances[msg.sender] = SafeMath.sub(_balances[msg.sender], uint256(amountToken));
        payable(msg.sender).transfer(amountETH);
        
        AllocatedAmount = SafeMath.sub(AllocatedAmount, uint256(amountToken));
        AvailableTokens = SafeMath.add(AvailableTokens, uint256(amountToken));

        emit ChangedBack(block.timestamp, msg.sender, amountETH);
        emit Withdrawn(block.timestamp, msg.sender, amountToken);
    }

    /// @notice Enables a user to sell back an amount of Tokens against a preferred token
    /// if there is enough token available, and if the change is authorized
    /// @param amountToken The amount of tokens to be exchanged
    /// @param tokenToBeReceived The address of the token to be exchanged for
    function sellBackAgainst(uint128 amountToken, address tokenToBeReceived) external exchangeIsAllowedForToken(tokenToBeReceived) {
        require(_balances[msg.sender] >= amountToken, "Insufficient balance");

        uint256 amountExpectedToken = (uint256(amountToken) * uint256(_precision)) / uint256(_exchangeRates[tokenToBeReceived]);
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
        _balances[msg.sender] = SafeMath.sub(_balances[msg.sender], uint256(amountToken));
        
        AllocatedAmount = SafeMath.sub(AllocatedAmount, uint256(amountToken));
        AvailableTokens = SafeMath.add(AvailableTokens, uint256(amountToken));

        emit ChangedBackFor(block.timestamp, msg.sender, tokenToBeReceived, amountExpectedToken);
        emit Withdrawn(block.timestamp, msg.sender, amountToken);
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
        require(_balances[msg.sender] >= amount, "Insufficient balance");

        pendingBridgeOutAmountByChain[msg.sender][toChainId] = SafeMath.add128(pendingBridgeOutAmountByChain[msg.sender][toChainId], amount);
        _balances[msg.sender] = SafeMath.sub(_balances[msg.sender], uint256(amount));

        addUserForBridingOut(msg.sender);
        addPendingChainIdBridgeToUser(pendingChainIdBridgesOutForUser[msg.sender], toChainId);

        emit BridgeOutRequested(block.timestamp, msg.sender, toChainId, amount);
    }

    /// @notice Cancels a bridging request for a user and for a chainId
    /// @param forUser The user address to cancel
    /// @param forChainId The target chain Id to cancel
    function revertBridgeOutRequestForUser(address forUser, uint64 forChainId) external override onlyOwner {
        // We credit back the tokens to the user
        _balances[msg.sender] = SafeMath.add(_balances[msg.sender], uint256(pendingBridgeOutAmountByChain[forUser][forChainId]));
        pendingBridgeOutAmountByChain[forUser][forChainId] = 0;

        removePendingChainIdBridgeForUser(forUser, pendingBridgesOut, pendingChainIdBridgesOutForUser[forUser], forChainId);

        emit BridgeOutCancelled(block.timestamp, forUser, forChainId);
    }

    /// @notice Validates a bridge in for a user and for a chain Id
    function validateBridgeOut(address forUser, uint64 forChainId) external override onlyOwner {
        // We add the bridge quantity back to the available tokens
        uint128 amt = pendingBridgeOutAmountByChain[forUser][forChainId];
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