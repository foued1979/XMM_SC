// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./interfaces/ierc20.sol";
import "./interfaces/ixmm.sol";
import "./libraries/financial.sol";
import "./structures.sol";

contract XMM is IXMM {
    /**********
     * Events *
     **********/
     event Deposit(uint timestamp, address from, uint256 amount);

    /*****************
     * The modifiers *
     *****************/
    modifier onlyOwner {
        require(msg.sender == _owner);
        _;
    }

    /***********************
     * Contract Properties *
     ***********************/
    // Private properties
    address private _owner;
    
    mapping(address => uint256) _balances;

    // Public properties
    /// @notice The Term of the XMM
    Terms public Term;

    /// @notice The token which managed by the XMM
    address public Token;

    /// @notice The total balance of deposits
    uint256 public TotalDeposit;

    /*************
     * Functions *
     *************/
    constructor(address token, Terms term) {
        Owner = msg.sender;
        Term = term;
        Token = token;
    }

    /// @notice Gets the term of the XMM
    function getTerm() external view returns(Terms) {
        return Term;
    }

    /// @notice Changes the ownership of the contract
    function changeOwnership(address newOwner) external {
        if (msg.sender == _owner) _owner = newOwner;
    }

    /// @notice Executes a deposit to the XMM from msg.sender
    function deposit(uint256 amount) external {
        (bool success, bytes memory res) = Token.call(abi.encodeWithSelector(IERC20.balanceOf.selector, msg.sender));

        if (success) {
            uint256 balance = abi.decode(res, (uint256));
            require(balance >= amount, "Insufficient balance");

            (sucess, _) = Token.call(abi.encodeWithSelector(IERC20.transfer.selector, address(this), amount));

            if (success) {
                _balances[msg.sender] += amount;
                emit Deposit(block.timestamp, msg.sender, amount);
            }
        }
    }
}