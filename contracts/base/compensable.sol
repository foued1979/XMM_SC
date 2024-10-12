// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./owned.sol";
import "../enums.sol";
import "../interfaces/ierc20.sol";
import "../libraries/math.sol";

abstract contract Compensable is Owned {
    /**********
     * Events *
     **********/
    event CompensationTokenChanged(uint indexed timestamp, address previousToken, address newToken);
    event CompensationStatusChanged(uint indexed timestamp, bool status);
    event CompensationSideChanged(uint indexed timestamp, CompensatedSides compensationSide);

    // Public Properties
    /// @notice The compensation token
    address public CompensationToken;

    /// @notice The compensation token balance
    uint128 public CompensationTokenBalance;

    /// @notice Indicates whether the compensation is active
    bool public CompensationIsActive;

    /// @notice The compensated side; 0-None, 1-Long, 2-Short, 3-All
    CompensatedSides public CompensatedSide;

    /// @notice The compensation ratio to the loss
    uint64 public CompensationRatio;

    /// @notice The conversion rate: Pool_Token -> CompensationToken
    uint64 public ConversionRate;

    /***************
     * Constructor *
     ***************/
    constructor(address owner, address compensationToken) Owned(owner) {
        CompensationToken = compensationToken;
        CompensationIsActive = false;
        CompensatedSide = CompensatedSides.Long;

        CompensationRatio = 0;
        ConversionRate = Math.One_32;
    }

    /*************
     * Functions *
     *************/
    /// @notice Changes the compensation token
    function changeCompensationToken(address newToken) external onlyOwner {
        emit CompensationTokenChanged(block.timestamp, CompensationToken, newToken);
        CompensationToken = newToken;
    }

    /// @notice Updates the compensation token balance
    function updateCompensationTokenBalance() external {
        (bool success, bytes memory res) = CompensationToken.call(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));

        if (success) {
            CompensationTokenBalance = abi.decode(res, (uint128));
        }
    }

    /// @notice Activates or deactivates the compensation
    function changeCompensationActivation(bool status) external onlyOwner {
        CompensationIsActive = status;
        emit CompensationStatusChanged(block.timestamp, status);
    }

    /// @notice Activates or deactivates the compensation
    function changeCompensationSide(CompensatedSides newCompensationSide) external onlyOwner {
        CompensatedSide = newCompensationSide;
        emit CompensationSideChanged(block.timestamp, newCompensationSide);
    }

    function isCompensable(LongShort position) internal view returns(bool) {
        if (CompensatedSide == CompensatedSides.None) return false;
        if (CompensatedSide == CompensatedSides.All) return true;

        if (position == LongShort.Long) return CompensatedSide == CompensatedSides.Long;
        return CompensatedSide == CompensatedSides.Short;
    }

    /// @notice The compensation ratio as a percentage; e.g. 1 for 1%, 2 for 2%, etc. up to 100
    function setCompensationRatio(uint8 ratio) external onlyOwner {
        if (ratio > 100) { ratio = 100; CompensationRatio = Math.One_32; }
        else CompensationRatio = (ratio << 32) / 100;
    }

    /// @notice Sets the conversion rate Pool_Token -> CompensationToken
    //          The conversion rate is expressed in pips <=> 10_000 for 1 unit
    function setConversionRate(uint32 conversionRate) external onlyOwner {
        ConversionRate = (conversionRate << 32) / 10_000;
    }

    function getCompensationAmount(uint128 positionSize, int64 loss) internal view returns(uint128) {
        if (!CompensationIsActive) return 0;
        
        uint64 absLoss = uint64(loss);
        uint64 ratio = Math.mult(ConversionRate, Math.mult(absLoss, CompensationRatio));
        return uint128((positionSize * ratio) >> 32);
    }
}