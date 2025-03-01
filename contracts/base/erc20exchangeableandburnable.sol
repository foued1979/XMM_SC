// SPDX-License-Identifier: MIT

pragma solidity >= 0.8.0;

import { ERC20Allocatable } from "./erc20allocatable.sol";
import { ERC20Exchangeable } from "./erc20exchangeable.sol";

/**
 * @dev Extension of {ERC20} that allows token holders to destroy both their own
 * tokens and those that they have an allowance for, in a way that can be
 * recognized off-chain (via event analysis).
 */
abstract contract ERC20ExchangeableAndBurnable is ERC20Allocatable, ERC20Exchangeable {
    /**********
     * Events *
     **********/
    /// @notice The Burnt event is triggered when tokens are burnt
    event Burnt(uint indexed timstamp, uint256 amount);

    /***************
     * Constructor *
     ***************/
    constructor(address owner_, address ccipRouter_, address linkToken_, uint32 initialSupply_, string memory name_, string memory symbol_, uint8 decimals_)
        ERC20Allocatable(owner_, ccipRouter_, linkToken_, initialSupply_, name_, symbol_, decimals_)
        ERC20Exchangeable(owner_)
    { }

    /**
     * @dev Destroys a `value` amount of tokens.
     * @param value The amount of tokens to be burnt
     *
     * The burn function has been changed to allow the owner to burn tokens
     * which are available but not allocated.
     * See {ERC20-_burn}.
     */
    function burn(uint256 value) public virtual {
        if (_msgSender() == _owner) {
            require(value <= _availableTokens, "Burn failed");
            _update(address(0), address(0), value);
            _availableTokens -= value;
        }
        else {
            _burn(_msgSender(), value);
        }

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

        emit Burnt(block.timestamp, value);
    }
}