// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./base/erc20.sol";
import "./interfaces/iexchangeable.sol";
import "./libraries/safemath.sol";

contract Token is ERC20, IExchangeable {
    /*************
     * Modifiers *
     *************/
    modifier isAllowed {
        require(ChangeIsAllowed, "Not allowed");
        _;
    }

    modifier isAllowedForToken(address token) {
        require(_tokenIsApproved[token] && _changeIsAllowed[token], "Not allozed");
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
    bool public ChangeIsAllowed;

    // The exchange rate represents a real number with 4 digits precision
    uint64 public ExchangeRate;
    uint16 private _precision = 10_000;

    // Parameters to manage other token exchanges
    mapping(address => bool) _tokenIsApproved;
    mapping(address => uint64) _exchangeRates;
    mapping(address => bool) _changeIsAllowed;
    address[] ApprovedTokens;

    // Private Fields
    uint256 public AllocatedAmount;

    constructor(string memory symbol, string memory name, uint32 initialSupply, uint32 initialOwnerAllocation) 
        ERC20(symbol, initialSupply, uint8(18)) payable {
        Name = name;
        AllocatedAmount = 0;

        ExchangeRate = 30_000_000;
        require(initialOwnerAllocation < (initialSupply / 5), "Not fair");
        allocateToOwner(uint256(initialOwnerAllocation) * uint256(10 ** 18));
    }

    /// @notice Burns a number of token
    /// @param amount The amount to be allocated
    function burn(uint256 amount) external onlyOwner {
        require(amount <= SafeMath.SafeSub(TotalSupply, AllocatedAmount), "Burn failed");

        uint256 newSupply = SafeMath.SafeSub(TotalSupply, amount);
        TotalSupply = newSupply;
    }

    /// @notice Allocates a number of token to a beneficiary
    /// @param to The beneficiary
    /// @param amount The amount
    function allocate(address to, uint256 amount) external onlyOwner {
        require(to != Owner, "No no");
        require(amount <= SafeMath.SafeSub(TotalSupply, AllocatedAmount), "Insufficient supply");

        uint256 newAllocation = SafeMath.SafeAdd(AllocatedAmount, amount);

        _balances[to] = SafeMath.SafeAdd(_balances[to], amount);
        AllocatedAmount = newAllocation;

        emit Allocated(block.timestamp, to, amount);
    }

    /// @notice Sets the change authorization status for ETH
    function setETHChangeAuthorization(bool status) external onlyOwner {
        ChangeIsAllowed = status;
    }

    /// @notice Sets the change authorization status for a token
    function setChangeAuthorization(address tokenToBeReceived, bool status) external onlyOwner tokenIsApproved(tokenToBeReceived) {
        changeIsAllowed[tokenToBeReceived] = status;
    }

    /// @notice Updates the exchange rate between ETH and the Token
    function updateETHExchangeRate(uint64 exchangeRate) external onlyOwner {
        ExchangeRate = exchangeRate;
        ChangeIsAllowed = true;
    }

    /// @notice Updates the exchange rate between a token and our Token
    /// @param  tokenToBeReceived The token to be received in exchange of our Token
    /// @param  exchangeRate The exchange rate
    function updateExchangeRate(address tokenToBeReceived, uint64 exchangeRate) external onlyOwner tokenIsApproved(tokenToBeReceived) {
        _exchangeRates[tokenToBeReceived] = exchangeRate;
        _changeIsAllowed[tokenToBeReceived] = true;
    }
    
    /// @notice Returns the quantity of ETH available for change against Token
    function getAvailableQuantityOfETH() external view returns(uint256) {
        return address(this).balance;
    }

    /// @notice Returns the latest exchange rate associated to the token to be received
    /// @return Whether the exchange is authorized and the latest exchange rate
    function getExchangeRate(address tokenToBeReceived) external view tokenIsApproved(tokenToBeReceived) returns(bool, uint64) {
        return (_changeIsAllowed[tokenToBeReceived], _exchangeRates[tokenToBeReceived]);
    }

    /// @notice Returns the available quantity of a token to be exchanged against our Token
    function getAvailableQuantityOfToken(address tokenToBeReceived) external view returns(uint256) {
        (bool success , bytes memory res) = tokenToBeReceived.call(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));

        require(success, "Comm error");
        return abi.decode(res, (uint256));
    }

    /// @notice Adds a token which can be traded against our Token
    function addApprovedToken(address token) external onlyOwner {
        if (_tokenIsApproved[token]) return;
        _tokenIsApproved[token] = true;
        _changeIsAllowed[token] = false;
        ApprovedTokens.push(token);
    }

    /// @notice Enables a user to deposit ETH and receive Tokens in exchange
    /// The conversion rate applies at a fixed rate, updated by Owner
    function depositEther() external payable isAllowed returns(uint256) {
        uint256 amountETH = msg.value;
        if (amountETH == 0) return 0;

        uint256 amountToken = (amountETH * uint256(ExchangeRate)) / uint256(_precision);
        uint256 tokenAvailable = SafeMath.SafeSub(TotalSupply, AllocatedAmount);
        
        if (amountToken > tokenAvailable) {
            amountETH = (tokenAvailable * uint256(_precision)) / uint256(ExchangeRate);
            amountToken = tokenAvailable;

            address payable receiver = payable(msg.sender);
            receiver.transfer(msg.value - amountETH);
        }
        
        AllocatedAmount = SafeMath.SafeAdd(AllocatedAmount, amountToken);

        emit Deposited(block.timestamp, msg.sender, amountETH, amountToken);
        emit Allocated(block.timestamp, msg.sender, amountToken);

        _balances[msg.sender] += amountToken;

        return amountToken;
    }

    /// @notice Enables a user to sell back an amount of Tokens against ETH
    /// if there is enough ETH available, and if the change is authorized
    /// @param amountToken The amount of tokens to be exchanged
    function sellBack(uint128 amountToken) external isAllowed {
        require(_balances[msg.sender] >= amountToken, "Insufficient balance");

        uint256 amountETH = (uint256(amountToken) * uint256(_precision)) / uint256(ExchangeRate);
        uint256 availableQuantityOfETH = address(this).balance;

        if (amountETH > availableQuantityOfETH) {
            amountETH = availableQuantityOfETH;
            amountToken = uint128((amountETH * uint256(ExchangeRate)) / uint256(_precision));
        }
        
        payable(msg.sender).transfer(amountETH);
        
        AllocatedAmount = SafeMath.SafeSub(AllocatedAmount, uint256(amountToken));
        _balances[msg.sender] = SafeMath.SafeSub(_balances[msg.sender], uint256(amountToken));

        emit ChangedBack(block.timestamp, msg.sender, amountETH);
        emit Withdrawn(block.timestamp, msg.sender, amountToken);
    }

    /// @notice Enables a user to sell back an amount of Tokens against a preferred token
    /// if there is enough token available, and if the change is authorized
    /// @param amountToken The amount of tokens to be exchanged
    /// @param tokenToBeReceived The address of the token to be exchanged for
    function sellBackAgainst(uint128 amountToken, address tokenToBeReceived) external isAllowedForToken(tokenToBeReceived) {
        require(_balances[msg.sender] >= amountToken, "Insufficient balance");

        uint256 amountExpectedToken = (uint256(amountToken) * uint256(_precision)) / uint256(_exchangeRates[tokenToBeReceived]);
        uint256 availableQuantity = this.getAvailableQuantityOfToken(tokenToBeReceived);

        if (amountExpectedToken > availableQuantity) {
            amountExpectedToken = availableQuantity;
            amountToken = uint128((amountExpectedToken * uint256(_exchangeRates[tokenToBeReceived])) / uint256(_precision));
        }
        
        IERC20(tokenToBeReceived).transfer(msg.sender, amountExpectedToken);
        
        AllocatedAmount = SafeMath.SafeSub(AllocatedAmount, uint256(amountToken));
        _balances[msg.sender] = SafeMath.SafeSub(_balances[msg.sender], uint256(amountToken));

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

        if (amountETH > availableQuantityOfETH) {
            amountETH = availableQuantityOfETH;
            amountToken = uint128((amountETH * uint256(rate)) / uint256(_precision));
        }

        from.transfer(amountETH);

        AllocatedAmount = SafeMath.SafeSub(AllocatedAmount, uint256(amountToken));
        _balances[from] = SafeMath.SafeSub(_balances[from], uint256(amountToken));

        emit ChangedBack(block.timestamp, from, amountETH, amountToken);
        emit Withdrawn(block.timestamp, from, amountToken);
    }

    /// @notice Allocates a number of token to the owner
    /// @param amount The amount
    function allocateToOwner(uint256 amount) private {
        uint256 newAllocation = SafeMath.SafeAdd(AllocatedAmount, amount);
        require(newAllocation < TotalSupply, "Insufficient supply");

        uint256 prevBalance = _balances[Owner];
        _balances[Owner] = SafeMath.SafeAdd(prevBalance, amount);
        AllocatedAmount = newAllocation;
        emit Allocated(block.timestamp, Owner, amount);
    }
}