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

    /// @notice Indicates whether the compensation is active
    bool public CompensationIsActive;

    /// @notice The compensated side; 0-None, 1-Long, 2-Short, 3-All
    CompensatedSides public CompensatedSide;

    /// @notice The fee rebate threshold
    // User gts 2.5% rebate on the reminaing fee for each FeeRebateThreshold level that
    // user's position being offset will represent; up to 35%
    // E.g. if FeeRebateThreshold is 100 1XMM, a user who has 600 tokens will have:
    // 6 * 2.5% discount = 15% discount
    uint32 public FeeRebateThreshold;

    /// @notice The mininum fee rebate threshold
    // If user has more than threshold => 15% discount
    // If user has more than 2 * threshold => 30% discount
    // If user has more than 4 * threshold => 50% discount
    uint32 public MinFeeRebateThreshold;
    uint32 private _2threshold;
    uint32 private _4threshold;

    /// @notice The compensation ratio to the loss
    uint64 public CompensationRatio;

    /// @notice The conversion rate: Pool_Token -> CompensationToken
    uint64 public ConversionRate;

    // Private Fields
    uint8 private _compensationTokenDecimals;

    /***************
     * Constructor *
     ***************/
    constructor(address owner, address compensationToken, uint8 compensationTokenDecimals) Owned(owner) {
        _compensationTokenDecimals = compensationTokenDecimals;

        MinFeeRebateThreshold = 50;
        _2threshold = 100;
        _4threshold = 200;
        FeeRebateThreshold = 50;

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
    function changeCompensationToken(address newToken, uint8 newTokenDecimals) external onlyOwner {
        emit CompensationTokenChanged(block.timestamp, CompensationToken, newToken);
        CompensationToken = newToken;
        _compensationTokenDecimals = newTokenDecimals;
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

    /// @notice Updates the thresholds for minimum fee rebate
    function changeFeeRebateThreshold(uint32 newThreshold) external onlyOwner {
        FeeRebateThreshold = newThreshold;
    }

    /// @notice Updates the thresholds for minimum fee rebate
    function changeMinFeeRebateThreshold(uint32 newThreshold) external onlyOwner {
        MinFeeRebateThreshold = newThreshold;
        _2threshold = 2 * newThreshold;
        _4threshold = 4 * newThreshold;
    }

    function getCompensationTokenBalance() external returns(uint128) {
        (bool success, bytes memory res) = CompensationToken.call(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        if (success) {
            return uint128(abi.decode(res, (uint256)));
        }

        return 0;
    }

    function getRebatedFee(address user, uint128 fee) internal returns(uint128) {
        (bool success, bytes memory res) = CompensationToken.call(abi.encodeWithSelector(IERC20.balanceOf.selector, user));

        if (success) {
            uint32 balance = uint32(abi.decode(res, (uint256)) / (10 ** _compensationTokenDecimals));

            uint32 mul = uint32(balance / FeeRebateThreshold);
            
            for (uint32 i = 14; i > 0; i--) {
                if (mul >= i) return uint128(fee * uint128(1000 - (i * 25))) / 1000;
            }
        }

        return fee;
    }

    function getRebatedMinimumFee(address user, uint128 minFee) internal returns(uint128) {
        (bool success, bytes memory res) = CompensationToken.call(abi.encodeWithSelector(IERC20.balanceOf.selector, user));

        if (success) {
            uint32 balance = uint32(abi.decode(res, (uint256)) / (10 ** _compensationTokenDecimals));

            if (balance >= _4threshold) return minFee * 60 / 100;
            if (balance >= _2threshold) return minFee * 70 / 100;
            if (balance >= MinFeeRebateThreshold) return minFee * 85 / 100;
        }

        return minFee;
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

    function getCompensationAmount(uint128 positionSize, int64 loss, uint8 poolTokenDecimals) internal returns(uint128) {
        if (!CompensationIsActive) return 0;

        int8 decimalDiff = int8(poolTokenDecimals) - int8(_compensationTokenDecimals);

        uint64 absLoss = uint64(loss);
        uint64 ratio = Math.mult(ConversionRate, Math.mult(absLoss, CompensationRatio));
        uint128 amt = uint128((positionSize * ratio) >> 32);
        amt = Math.adjustAmountDecimals(amt, decimalDiff);

        uint128 compensationTokenBalance = this.getCompensationTokenBalance();
        if (amt >= compensationTokenBalance) amt = compensationTokenBalance;
        return amt;
    }
}