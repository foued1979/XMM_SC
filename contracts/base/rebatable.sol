// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./owned.sol";
import "../enums.sol";
import "../interfaces/ierc20.sol";
import "../libraries/math.sol";

abstract contract Rebatable is Owned {
    /**********
     * Events *
     **********/
    event CompensationTokenChanged(uint indexed timestamp, address previousToken, address newToken);

    // Public Properties
    /// @notice The compensation token
    address public CompensationToken;

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
    uint32 private _8threshold;

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
        _8threshold = 400;
        FeeRebateThreshold = 50;

        CompensationToken = compensationToken;
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

    /// @notice Updates the thresholds for minimum fee rebate
    function changeFeeRebateThreshold(uint32 newThreshold) external onlyOwner {
        FeeRebateThreshold = newThreshold;
    }

    /// @notice Updates the thresholds for minimum fee rebate
    function changeMinFeeRebateThreshold(uint32 newThreshold) external onlyOwner {
        MinFeeRebateThreshold = newThreshold;
        _2threshold = 2 * newThreshold;
        _4threshold = 4 * newThreshold;
        _8threshold = 8 * newThreshold;
    }

    /********************
     * Internal Methods *
     ********************/
    function getRebatedFee(address user, uint128 fee) internal returns(uint128) {
        (bool success, bytes memory res) = CompensationToken.call(abi.encodeWithSelector(IERC20.balanceOf.selector, user));

        if (success) {
            uint32 balance = uint32(abi.decode(res, (uint256)) / (10 ** _compensationTokenDecimals));

            uint32 mul = uint32(balance / FeeRebateThreshold);
            if (mul > 14) { mul = 14; }

            return uint128(fee * uint128(1000 - (mul * 25))) / 1000;
        }

        return fee;
    }

    function getRebatedMinimumFee(address user, uint128 minFee) internal returns(uint128) {
        (bool success, bytes memory res) = CompensationToken.call(abi.encodeWithSelector(IERC20.balanceOf.selector, user));

        if (success) {
            uint32 balance = uint32(abi.decode(res, (uint256)) / (10 ** _compensationTokenDecimals));

            if (balance >= _8threshold) return minFee * 70 / 100;
            if (balance >= _4threshold) return minFee * 80 / 100;
            if (balance >= _2threshold) return minFee * 90 / 100;
        }

        return minFee;
    }

    function getRebatePenalty(address user, uint128 penalty) internal returns(uint128) {
        (bool success, bytes memory res) = CompensationToken.call(abi.encodeWithSelector(IERC20.balanceOf.selector, user));

        if (success) {
            uint32 balance = uint32(abi.decode(res, (uint256)) / (10 ** _compensationTokenDecimals));

            if (balance >= _4threshold) return penalty * 60 / 100;
            if (balance >= _2threshold) return penalty * 70 / 100;
            if (balance >= MinFeeRebateThreshold) return penalty * 85 / 100;
        }

        return penalty;
    }
}