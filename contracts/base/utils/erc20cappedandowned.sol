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

    /// @notice The decimal property
    uint8 private _decimals;

    /**
     * @notice Sets the value of the `cap`. This value is immutable, it can only be
     * set once during construction.
     */
    constructor(address owner_, uint32 initialSupply_, string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_)
        Owned(owner_) {

        _decimals = decimals_;
        _cap = uint256(initialSupply_) * (10 ** decimals_);

        // We set the initial supply to the Contract
        super._update(address(0), address(this), _cap);
    }

    /**
     * @notice Returns the token's number of decimals.
     */
    function decimals() public view override(ERC20) returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Returns the cap of total supply.
     */
    function cap() external view returns (uint256) {
        return _cap;
    }

    /**
     * @notice The number of tokens which are circulating.
     */
    function circulatingSupply() public view returns (uint256) {
        return totalSupply() - balanceOf(address(this));
    }

    /**
     * @dev See {ERC20-_update}.
     */
    function _update(address from, address to, uint256 value) internal virtual override(ERC20) {
        if (from == address(0)) {
            uint256 maxSupply = totalSupply();
            uint256 circSupply = circulatingSupply();

            if (circSupply + value > maxSupply) revert ERC20ExceededCap(circSupply, maxSupply);
        }

        super._update(from, to, value);
    }
}