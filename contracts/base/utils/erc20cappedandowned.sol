// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/ERC20Capped.sol)

pragma solidity >= 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Owned } from "./owned.sol";

/**
 * @dev Extension of {ERC20} that adds a cap to the supply of tokens.
 */
abstract contract ERC20CappedAndOwned is ERC20, Owned {
    uint256 internal _cap;

    /**
     * @notice Total supply cap has been exceeded.
     */
    error ERC20ExceededCap(uint256 increasedSupply, uint256 cap);

    /**
     * @notice The supplied cap is not a valid cap.
     */
    error ERC20InvalidCap(uint256 cap);

    /// @notice The decimal property
    uint8 private _decimals;

    /**
     * @notice Sets the value of the `cap`. This value is immutable, it can only be
     * set once during construction.
     */
    constructor(address owner_, uint32 initialSupply_, string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_)
        Owned(owner_) {
        if (initialSupply_ == 0) { revert ERC20InvalidCap(0); }
        _decimals = decimals_;
        _cap = initialSupply_ * (10 ** decimals_);
    }

    /**
     * @notice Returns the token's number of decimals.
     */
    function decimals() public view override(ERC20) returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Returns the cap on the token's total supply.
     */
    function cap() public view virtual returns (uint256) {
        return _cap;
    }

    /**
     * @dev See {ERC20-_update}.
     */
    function _update(address from, address to, uint256 value) internal virtual override(ERC20) {
        if (from == address(0)) {
            uint256 maxSupply = cap();
            uint256 supply = totalSupply();

            if (supply + value > maxSupply) revert ERC20ExceededCap(supply, maxSupply);
        }

        super._update(from, to, value);
    }
}