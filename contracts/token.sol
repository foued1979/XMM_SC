// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./base/erc20.sol";
import "./interfaces/itradable.sol";
import "./libraries/safemath.sol";

contract Token is ERC20, ITradable {
    /// @notice The Allocated event is triggered when Owner allocates some token to
    /// a beneficiary
    event Allocated(uint indexed timestamp, address indexed beneficiary, uint256 amount);
    event Withdrawn(uint indexed timestamp, address indexed from, uint256 amount);

    /*************
     * Modifiers *
     *************/
    modifier onlyOwner {
        require(msg.sender == Owner, "No auth.");
        _;
    }

    modifier isAllowed {
        require(ChangeIsAllowed, "Not allowed");
        _;
    }

    /**************
     * Properties *
     **************/
     // Public Properties
    string public Symbol;
    string public Name;
    uint8 public Decimals;

    // Public properties linked to ITradable
    bool public ChangeIsAllowed;
    uint256 public AvailableQuantityOfETH;

    // The exchange rate represents a real number with 4 digits precision
    uint64 public ExchangeRate;
    uint16 private constant _precision = 10_000;

    // Private Fields
    uint256 public AllocatedAmount;

    constructor(string memory symbol, string memory name, uint8 decimals, address owner, uint256 initialSupply) 
        ERC20(owner, initialSupply) payable { 
        Symbol = symbol;
        Name = name;
        Decimals = decimals;
    }

    /// @notice Burns a number of token
    /// @param amount The amount to be allocated
    function burn(uint256 amount) external onlyOwner {
        require(amount <= TotalSupply);

        uint256 newSupply = SafeMath.SafeSub(TotalSupply, amount);
        TotalSupply = newSupply;
    }

    /// @notice Allocates a number of token to a beneficiary
    /// @param to The beneficiary
    /// @param amount The amount
    function allocate(address to, uint256 amount) external onlyOwner {
        uint256 newAllocation = SafeMath.SafeAdd(AllocatedAmount, amount); 
        require(newAllocation < TotalSupply, "Insufficient supply");

        _balances[to] = SafeMath.SafeAdd(_balances[to], amount);
        AllocatedAmount = newAllocation;
        emit Allocated(block.timestamp, to, amount);
    }

    /// @notice Sets the change authorization status
    function setChangeAuthorization(bool status) external onlyOwner {
        ChangeIsAllowed = status;
    }

    /// @notice Updates the exchange rate between ETH and the Token
    function updateExchangeRate(uint64 exchangeRate) external onlyOwner {
        ExchangeRate = exchangeRate;
    }
    
    /// @notice Returns the quantity of ETH available for change against Token
    function getAvailableQuantityOfETH() external view returns(uint256) {
        return AvailableQuantityOfETH;
    }

    /// @notice Enables a user to deposit ETH and receive Tokens in exchange
    /// The conversion rate applies at a fixed rate, updated by Owner
    function depositEther(uint256 maxGas) external payable isAllowed returns(uint256) {
        uint256 amountETH = msg.value;
        uint256 amountToken = (amountETH * ExchangeRate) / _precision;
        uint256 tokenAvailable = SafeMath.SafeSub(TotalSupply, AllocatedAmount);
        
        if (amountToken > tokenAvailable) {
            amountETH = (uint256(amountToken) * _precision) / ExchangeRate;
            amountToken = tokenAvailable;
        }
        
        (bool success, bytes memory res) = payable(address(this)).call{gas: maxGas, value:amountETH} ("");
        

        if (success) {
            AvailableQuantityOfETH = SafeMath.SafeAdd(AvailableQuantityOfETH, amountETH);
            AllocatedAmount = SafeMath.SafeAdd(AllocatedAmount, amountToken);

            emit Deposited(block.timestamp, msg.sender, amountETH, amountToken);
            emit Allocated(block.timestamp, msg.sender, amountToken);
            _balances[msg.sender] += amountToken;
        }

        return amountToken;
    }

    /// @notice Enables a user to sell back an amount of Tokens against ETH
    /// if there is enough ETH available, and if the change is authorized
    /// @param amountToken The amount of tokens to be exchanged
    function sellBack(uint128 amountToken) external payable isAllowed returns(bool) {
        return this.buyBack(payable(msg.sender), amountToken, ExchangeRate);
    }

    /// @notice Enables the Owner to buy back tokens from a user, in exchange of ETH
    /// and at a specified rate
    /// @param from The beneficiary
    /// @param amountToken The amount of tokens
    /// @param rate The conversion rate
    function buyBack(address payable from, uint128 amountToken, uint64 rate) external payable onlyOwner returns(bool) {
        require(_balances[from] >= amountToken, "Insufficient balance");

        uint256 amountETH = (uint256(amountToken) * _precision) / rate;

        if (amountETH > AvailableQuantityOfETH) {
            amountETH = AvailableQuantityOfETH;
            amountToken = uint128((amountETH * rate) / _precision);
        }

        (bool success, bytes memory res) = from.call{gas: 35000, value:amountETH} ("");

        if (success) {
            AllocatedAmount = SafeMath.SafeSub(AllocatedAmount, amountToken);
            _balances[from] = SafeMath.SafeSub(_balances[from], amountToken);
            AvailableQuantityOfETH = SafeMath.SafeSub(AvailableQuantityOfETH, amountETH);

            emit ChangedBack(block.timestamp, from, amountETH, amountToken);
            emit Withdrawn(block.timestamp, from, amountToken);
        }

        return success;
    }
}