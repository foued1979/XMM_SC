// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../interfaces/ierc20.sol";
import "../libraries/safemath.sol";

import "hardhat/console.sol";

contract ERC20 is IERC20 {
    /*************
     * Modifiers *
     *************/
    modifier onlyOwner {
        require(msg.sender == Owner, "No auth.");
        _;
    }
    
    /**************
     * Properties *
     **************/
    // Public Properties

    address public Owner;
    string public Symbol;
    uint256 public TotalSupply;
    uint8 public Decimals;

    // Private Fields
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    /***************
     * Constructor *
     ***************/
    constructor(string memory symbol, uint32 initialSupply, uint8 decimals) {
        Owner = msg.sender;
        Symbol = symbol;
        TotalSupply = uint256(initialSupply) * (10 ** decimals);
        Decimals = decimals;
    }

    /// @notice Returns the value of tokens in existence.
    function totalSupply() external view returns(uint256) {
        return TotalSupply;
    }

    /// @notice Returns the amount of tokens owned by account
    /// @param account The address of the account
    function balanceOf(address account) external view returns(uint256) {
        return _balances[account];
    }

    /// @notice Transfers tokens
    /// @param to The recipient wallet
    /// @param amount The amount to be transferred
    // Throws Transfer event
    function transfer(address to, uint256 amount) external returns(bool) {
        require (to != address(this), "Transfer err");
        if (_balances[msg.sender] < amount) return false;
        
        _balances[msg.sender] = SafeMath.sub(_balances[msg.sender], amount);
        _balances[to] = SafeMath.add(_balances[to], amount);
        
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Returns the remaining number of tokens that `spender` will be
    /// allowed to spend on behalf of `owner` through {transferFrom}. This is
    /// zero by default.
    /// @param owner The wallet which has given the allowance
    /// @param spender The spender
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @notice Sets a `value` amount of tokens as the allowance of `spender` over the
    /// caller's tokens.
    /// @param spender The spender
    /// @param amount The approved amount
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    /// @notice Moves a `value` amount of tokens from `from` to `to` using the
    /// allowance mechanism. `value` is then deducted from the caller's
    /// allowance.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        require(_balances[from] >= amount, "Insufficient funds");
        
        _balances[from] = SafeMath.sub(_balances[from], amount);
        _balances[to] = SafeMath.add(_balances[to], amount);

        emit Transfer(from, to, amount);
        _allowances[from][msg.sender] = SafeMath.subOr0(_allowances[from][msg.sender], amount);

        return true;
    }
}