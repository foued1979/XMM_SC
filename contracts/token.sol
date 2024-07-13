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
    modifier isAllowed {
        require(ChangeIsAllowed, "Not allowed");
        _;
    }

    /**************
     * Properties *
     **************/
     // Public Properties
    string public Name;

    // Public properties linked to ITradable
    bool public ChangeIsAllowed;

    // The exchange rate represents a real number with 4 digits precision
    uint64 public ExchangeRate;
    uint16 private _precision = 10_000;

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

    /// @notice Sets the change authorization status
    function setChangeAuthorization(bool status) external onlyOwner {
        ChangeIsAllowed = status;
    }

    /// @notice Updates the exchange rate between ETH and the Token
    function updateExchangeRate(uint64 exchangeRate) external onlyOwner {
        ExchangeRate = exchangeRate;
        ChangeIsAllowed = true;
    }
    
    /// @notice Returns the quantity of ETH available for change against Token
    function getAvailableQuantityOfETH() external view returns(uint256) {
        return address(this).balance;
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

        emit ChangedBack(block.timestamp, msg.sender, amountETH, amountToken);
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