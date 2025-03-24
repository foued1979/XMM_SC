// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

import { DurationUnits } from  "../enums.sol";
import { ERC20Vested } from "./utils/erc20vested.sol";
import { ERC20Burnable } from "./utils/erc20burnable.sol";

import { IERC20 } from "../interfaces/ierc20.sol";
import { IERC20Errors } from "../interfaces/ierc20errors.sol";
import { IERC677Errors } from "../interfaces/ierc677errors.sol";

import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import { IGetCCIPAdmin } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IGetCCIPAdmin.sol";
import { IRouterClient } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

import { IBurnMint } from "../interfaces/iburnmint.sol";

contract ERC677Allocatable is ERC20Vested, IGetCCIPAdmin, IBurnMint {
    /// @dev Modifier that checks if the msg.sender is the ccipAdmin.
    // This function shall be called only when tokens are transferred from one chain to another.
    // Owner has no right to mint.
    modifier onlyMinter() {
        require(msg.sender == _ccipAdmin, "Denied");
        _;
    }

    /**********
     * Events *
     **********/
    /// @notice Event emitted when CCIP Admin is transferred to a new address
    event CCIPAdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    /// @notice The Allocated event is triggered when Owner allocates some token to
    /// a beneficiary
    event Allocated(address indexed beneficiary, uint256 amount);

    /**************
     * Properties *
     **************/
    // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 chainId => bool) private _allowlistedChains;

    // The address of the CCIP Admin
    address private _ccipAdmin;

    /***************
     * Constructor *
     ***************/
    constructor(address owner_, uint32 initialSupply_, string memory name_, string memory symbol_, uint8 decimals_)
        ERC20Vested(owner_, initialSupply_, name_, symbol_, decimals_)
    { }

    /// @notice Allocates a number of token to a beneficiary
    /// @param to The beneficiary
    /// @param amount The amount to allocate
    /// @param cliffDuration The duration of the cliff
    /// @param cliffDurationUnit The unit of the cliff duration
    /// @param upfrontRelease The amount released when cliff period ends
    /// @param vestingDuration The duration of the vesting
    /// @param vestingDurationUnit The unit of the vesting duration
    function allocateWithVesting(address to, uint256 amount, uint16 cliffDuration, DurationUnits cliffDurationUnit, uint8 upfrontRelease, uint16 vestingDuration, 
    DurationUnits vestingDurationUnit) external onlyOwner {
        allocate(to, amount);

        uint vestingStart = _addDuration(block.timestamp, cliffDuration, cliffDurationUnit);

        if (upfrontRelease > 100) upfrontRelease = 100;
        _createVestingSchedule(to,upfrontRelease, vestingStart, vestingDuration, vestingDurationUnit, amount);
    }

    /// @notice Gets whether a chain id is allowed
    function isChainIdAllowed(uint64 chainId) external view returns(bool) {
        return _allowlistedChains[chainId];
    }

    /// @notice Updates the allowlist status of a destination chain for transactions.
    /// @dev This function can only be called by the owner.
    /// @param _destinationChainSelector The selector of the destination chain to be updated.
    /// @param allowed The allowlist status to be set for the destination chain.
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        _allowlistedChains[_destinationChainSelector] = allowed;
    }

    /// @notice Allocates a number of token to a beneficiary
    /// @param to The beneficiary
    /// @param amount The amount
    function allocate(address to, uint256 amount) public onlyOwner {
        require(to != _owner && to != address(0), "Err");
        super._update(address(0), to, amount);

        emit Allocated(to, amount);
    }

    /// @notice Allocates a number of token to a beneficiary
    /// @param to The beneficiaries
    /// @param amount The amounts
    function massAllocation(address[] memory to, uint256[] memory amount) external onlyOwner {
        require(to.length == amount.length, "Err");

        for (uint i = 0; i < to.length; i++) {
            allocate(to[i], amount[i]);
        }
    }

    /// @notice Returns the token administrator's address
    function getCCIPAdmin() external view returns(address) {
        return _ccipAdmin;
    }

    /// @notice Transfers the CCIPAdmin role to a new address
    /// @dev only the owner can call this function, NOT the current ccipAdmin, and 1-step ownership transfer is used.
    /// @param newAdmin The address to transfer the CCIPAdmin role to. Setting to address(0) is a valid way to revoke
    /// the role
    function setCCIPAdmin(address newAdmin) public onlyOwner {
        emit CCIPAdminTransferred(_ccipAdmin, newAdmin);
        _ccipAdmin = newAdmin;
    }

    /*******************
     *  IBurnMintImpl  *
     *******************/
    /// @notice Mints 'value' amount of tokens when a cross-chain transfer is performed
    /// @param account The account to receive the tokens
    /// @param value The amount of tokens to be minted
    /// @dev this function increases the cap.
    function mint(address account, uint256 value) public onlyMinter {
        _cap += value;
        _mint(account, value);
        _availableTokens = _cap - totalSupply();

        emit Minted(account, _ccipAdmin, value);
    }

    /// @inheritdoc ERC20Burnable
    function burn(uint256 amount) public override(ERC20Burnable) {
        _cap -= amount;

        // Owner or CCIPAdmin cannot burn non-allocated tokens
        if (msg.sender == _owner || msg.sender == _ccipAdmin) {
            require(amount <= _availableTokens, "Burn err");
            _availableTokens -= amount;
        }
        else {
            super._burn(msg.sender, amount);
        }
        
        emit Burnt(amount);
    }

    /// @notice IBurnMint
    function burn(address account, uint256 amount) public override(IBurnMint) {
        if (account == msg.sender) burn(amount);
        else burnFrom(account, amount);
    }

    /// @inheritdoc ERC20Burnable
    function burnFrom(address account, uint256 amount) public override(ERC20Burnable, IBurnMint) {
        _spendAllowance(account, msg.sender, amount);

        _cap -= amount;
        super._burn(account, amount);

        emit Burnt(amount);
    }

    /********************/
}