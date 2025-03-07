// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/ERC20Capped.sol)

pragma solidity >= 0.8.20;

import { ERC20CappedAndOwned } from "./erc20cappedandowned.sol";

import {console} from "hardhat/console.sol";

/**
 * @dev Extension of {ERC20} that adds a cap to the supply of tokens.
 */
abstract contract ERC20Burnable is ERC20CappedAndOwned {
    /**********
     * Events *
     **********/
    /// @dev The Burnt event is triggered when tokens are burnt
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
     * @dev Gets the amount of tokens which remains to be allocated
     */
    function availableTokens() external view returns(uint256) {
        return _availableTokens;
    }

    /**
     * @dev Destroys a `value` amount of tokens.
     * @param value The amount of tokens to be burnt
     *
     * The burn function has been changed to allow the owner to burn tokens
     * which are available but not allocated.
     * See {ERC20-_burn}.
     */
    function burn(uint256 value) public virtual {
        _burn(msg.sender, value);
    }

    /**
     * See {ERC20-_burn}.
     * Overrides the ERC20 method to adjust the cap amount.
     */
    function _burn(address account, uint256 value) internal override {
        _cap -= value;

        // Owner cannot burn allocated tokens
        if (msg.sender == _owner) {
            require(value <= _availableTokens, "Burn err");
            _availableTokens -= value;
        }
        else {
            super._burn(account, value);
        }
        
        emit Burnt(block.timestamp, value);
    }

    // burnFrom is not implemented; each user must burn its own token

    /**
     * @dev See {ERC20-_update}.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);
        _availableTokens = cap() - totalSupply();
    }
}