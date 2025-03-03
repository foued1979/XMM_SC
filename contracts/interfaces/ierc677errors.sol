// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

/**
 * @dev Standard ERC-677 Errors
 */
interface IERC677Errors {
    /**
     * @dev Indicates an error related to the current `allowance` of a `sender`.
     * @param sender Address whose tokens are being transferred.
     * @param router The address of the LINK router.
     * @param token The address of the token to be bridged.
     * @param needed Minimum amount required to perform a bridge.
     */
    error ERC677InsufficientCCIPRouterAllowance(address sender, address router, address token, uint256 needed);
}