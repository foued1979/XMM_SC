// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.20;

import { IERC20 } from  "../../interfaces/ierc20.sol";
import { IERC20Errors } from  "../../interfaces/ierc20errors.sol";

import { DurationUnits } from  "../../enums.sol";
import { VestingSchedule } from  "../../structures/vestingschedule.sol";

import { ERC20Burnable } from  "./erc20burnable.sol";

import { console } from "hardhat/console.sol";

abstract contract ERC20Vested is ERC20Burnable {
    /**********
     * Events *
     **********/
    /// @dev Emitted when a vesting schedule is created
    event VestingScheduleCreated(address indexed beneficiary, uint indexed timestamp, uint start, uint end, uint8 upfrontRelease, uint256 amount);
    /// @dev Emitted when a vesting schedule is created
    event TokensAddedToVestingSchedule(address indexed beneficiary, uint indexed timestamp, uint256 amount);
    /// @dev Emitted when tokens are released
    event TokensReleased(address indexed beneficiary, uint indexed timestamp, uint256 amount);

    /**************
     * Properties *
     **************/
    /// @dev The vesting schedules for each beneficiary
    mapping(address beneficiary => VestingSchedule) private _vestingSchedules;
    mapping(address beneficiary => bool) private _hasVestingSchedule;

    /***************
     * Constructor *
     ***************/
    constructor(address owner_, uint32 initialSupply_, string memory name_, string memory symbol_, uint8 decimals_)
        ERC20Burnable(owner_, initialSupply_, name_, symbol_, decimals_)
    {}

    /// @dev Transfers tokens from the msg sender to another address
    /// overrides the transfer function of ERC20
    function transfer(address to, uint256 value) public override returns(bool) {
        uint256 releasableAmount = _releaseTokens(msg.sender, value);
        require(releasableAmount >= value, "Vest err");

        return super.transfer(to, value);
    }

    /// @dev Transfers tokens from one address to another
    /// overrides the transferFrom function of ERC20
    function transferFrom(address from, address to, uint256 value) public override returns(bool) {
        uint256 releasableAmount = _releaseTokens(from, value);
        require(releasableAmount >= value, "Vest err");

        return super.transferFrom(from, to, value);
    }

    /// @dev Gets the remaining amount of tokens which are vested
    function getRemainingVestedAmount() public view returns(uint256) {
        if (_hasVestingSchedule[msg.sender]) {
            VestingSchedule storage schedule = _vestingSchedules[msg.sender];
            return schedule.totalAmount - schedule.released;
        }

        return 0;
    }

    /// @dev Gets the amount of vested tokens which can be withdrawn by the msg.sender
    function getReleasableAmount() external view returns(uint256) {
        (uint256 amt, ) = _getReleasableAmount(msg.sender);
        return amt;
    }

    /// @dev Gets the amount of vested tokens which can be withdrawn by the beneficiary
    function _getReleasableAmount(address beneficiary) internal view returns(uint256, bool) {
        uint256 totalReleasableAmount = 0;

        if (_hasVestingSchedule[beneficiary]) {
            VestingSchedule storage schedule = _vestingSchedules[beneficiary];
            
            // if end of cliff period has not been reached, 0 can be released
            if (block.timestamp < schedule.start) return (0, false);
            if (block.timestamp >= schedule.end) {
                totalReleasableAmount = schedule.totalAmount - schedule.released;
                return (totalReleasableAmount, true);
            }
            
            uint256 upfrontRelease = uint256((schedule.totalAmount * schedule.upfrontRelease) / 100);
            totalReleasableAmount = upfrontRelease + uint256(((schedule.totalAmount - upfrontRelease) * (block.timestamp - schedule.start)) / schedule.totalDuration);
            
            // Sanity check - we make sure to always release at max the total amount of tokens
            if (totalReleasableAmount > schedule.totalAmount) totalReleasableAmount = schedule.totalAmount;
            return (totalReleasableAmount - schedule.released, false);
        }

        return (0, false);
    }

    /// @dev Gets the amount of tokens which are not vested
    function _getNonVestedAmount(address beneficiary) internal view returns(uint256) {
        if (_hasVestingSchedule[beneficiary]) {
            VestingSchedule storage schedule = _vestingSchedules[beneficiary];

            uint256 currentBalance = IERC20(address(this)).balanceOf(beneficiary);
            if (currentBalance > schedule.totalAmount) return currentBalance - schedule.totalAmount;
        }

        return 0;
    }

    /// @dev Computes the amount of tokens which can be released and updates the schedule (if ever)
    function _releaseTokens(address beneficiary, uint256 amount) internal returns(uint256) {
        if (_hasVestingSchedule[beneficiary]) {
            (uint256 releasableAmount, bool canDelete) = _getReleasableAmount(beneficiary);
            uint256 extraAmount = 0;

            if (releasableAmount < amount) extraAmount = _getNonVestedAmount(beneficiary);
            else releasableAmount = amount;

            if (canDelete) {
                _hasVestingSchedule[beneficiary] = false;
                delete _vestingSchedules[beneficiary];
            } else {
                _vestingSchedules[beneficiary].released += releasableAmount;
                emit TokensReleased(beneficiary, block.timestamp, releasableAmount);
            }
            
            return releasableAmount + extraAmount;
        }

        return amount;
    }

     /**
     * @dev Creates a vesting schedule
     * @param beneficiary The address of the beneficiary
     * @param upfrontRelease The amount released when cliff period ends
     * @param start The start UNIX timestamp of the vesting period - this can correspond to a cliff period
     * @param duration The duration of the vesting period in DurationUnits
     * @param durationUnit The units of the duration(0 = days, 1 = weeks, 2 = months)
     * @param amount The total amount of tokens to be vested
     */
    function _createVestingSchedule(address beneficiary, uint8 upfrontRelease, uint start, uint16 duration, DurationUnits durationUnit, uint256 amount) internal {
        // perform input checks
        require(beneficiary != address(0) && amount > 0 && start >= block.timestamp && duration > 0, "Vesting Err");

        // if beneficiary already has a vesting schedule, we just add the amount to the existing schedule
        if (_hasVestingSchedule[beneficiary]) {
            VestingSchedule storage schedule = _vestingSchedules[beneficiary];
            schedule.totalAmount += amount;
            emit TokensAddedToVestingSchedule(beneficiary, block.timestamp, amount);
            return;
        }
        
        uint end = _addDuration(start, duration, durationUnit);
        
        // create the vesting schedule and add it to the list of schedules for the beneficiary
        _vestingSchedules[beneficiary] = VestingSchedule(beneficiary, upfrontRelease, start, end, end - start, amount, 0);
        _hasVestingSchedule[beneficiary] = true;

        emit VestingScheduleCreated(beneficiary, block.timestamp, start, end, upfrontRelease, amount);
    }

    /*******************
     * Private Methods *
     *******************/
    /// @dev Adds a duration to a timestamp
    function _addDuration(uint start, uint16 duration, DurationUnits durationUnit) internal pure returns(uint) {
        if (durationUnit == DurationUnits.Days) return start + duration * 86_400;
        if (durationUnit == DurationUnits.Weeks) return start + duration * 604_800;
        return start + duration * 2_592_000;
    }
}