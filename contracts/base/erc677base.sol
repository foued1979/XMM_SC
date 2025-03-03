// SPDX-License-Identifier: MIT

pragma solidity >= 0.8.0;

import { ERC677Allocatable } from "./erc677allocatable.sol";
import { ERC20Exchangeable } from "./erc20exchangeable.sol";

/**
 * @dev Extension of {ERC20} that allows token holders to destroy both their own
 * tokens and those that they have an allowance for, in a way that can be
 * recognized off-chain (via event analysis).
 */
abstract contract ERC677Base is ERC677Allocatable, ERC20Exchangeable {
    
    /***************
     * Constructor *
     ***************/
    constructor(address owner_, address ccipRouter_, address linkToken_, uint32 initialSupply_, string memory name_, string memory symbol_, uint8 decimals_)
        ERC677Allocatable(owner_, ccipRouter_, linkToken_, initialSupply_, name_, symbol_, decimals_)
        ERC20Exchangeable(owner_)
    { }
}