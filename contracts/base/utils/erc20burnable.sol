// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/ERC20Capped.sol)

pragma solidity >= 0.8.0;

import { ERC20CappedAndOwned } from "./erc20cappedandowned.sol";

/**
 * @dev Extension of {ERC20} that adds a cap to the supply of tokens.
 */
abstract contract ERC20Burnable is ERC20CappedAndOwned {
    /**********
     * Events *
     **********/
    /// @notice The Burnt event is triggered when tokens are burnt
    event Burnt(uint indexed timstamp, uint256 amount);

    /**************
     * Properties *
     **************/
    // Private Properties
    uint256 internal _availableTokens;

    /**
     * @dev Sets the value of the `cap`. This value is immutable, it can only be
     * set once during construction.
     */
    constructor(address owner_, uint32 initialSupply_, string memory name_, string memory symbol_, uint8 decimals_)
        ERC20CappedAndOwned(owner_, initialSupply_, name_, symbol_, decimals_) {}

    /**
     * @dev Destroys a `value` amount of tokens.
     * @param value The amount of tokens to be burnt
     *
     * The burn function has been changed to allow the owner to burn tokens
     * which are available but not allocated.
     * See {ERC20-_burn}.
     */
    function burn(uint256 value) public virtual {
        // Owner cannot burn allocated tokens
        if (_msgSender() == _owner) {
            require(value <= _availableTokens, "Burn failed");
            _availableTokens -= value;
        }
        else {
            _burn(_msgSender(), value);
        }

        _cap -= value;

        emit Burnt(block.timestamp, value);
    }

    /**
     * @dev Destroys a `value` amount of tokens from `account`, deducting from
     * the caller's allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `value`.
     */
    function burnFrom(address account, uint256 value) public virtual {
        // Owner is not allowed to burn from an account
        if (_msgSender() == _owner) return;

        _spendAllowance(account, _msgSender(), value);
        _burn(account, value);
        _cap -= value;

        emit Burnt(block.timestamp, value);
    }

    /**
     * @dev See {ERC20-_update}.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);
        _availableTokens = cap() - totalSupply();
    }
}