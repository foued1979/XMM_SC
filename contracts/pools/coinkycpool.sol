// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "../base/xmmpool.sol";
import "../interfaces/ikyc.sol";
import "../enums.sol";

contract CoinKYCPool is XMMPool, IKYC {
    modifier isKYCed() {
        require(_isKYCed[msg.sender], "no kyc");
        _;
    }

    /// @notice The token which managed by the XMM
    address public Token;

    // The list of KYCed user
    mapping (address => bool) _isKYCed;

    constructor(address token, address owner, address compensationToken, uint8 poolTokenDecimals, uint8 compensationTokenDecimals, Terms term, uint8 fee,
     uint8 penalty, uint64 minDeposit, uint8 minWithdrawalRatio)
    XMMPool(owner, compensationToken, poolTokenDecimals, compensationTokenDecimals, term, fee, penalty, minDeposit, minWithdrawalRatio) {
        Token = token;
    }

    /// @notice Sets the KYC status for a user
    /// @param user The user address
    function updateKYCUserStatus(address user, bool status) external onlyOwner {
        _isKYCed[user] = status;
    }

    /// @notice Executes a deposit to the XMM from msg.sender
    /// @param longShort 0 if long 1 if short
    /// @param amount The amount to be deposited
    /// @param leverage The level of leverage (x1, x2, x3, x5, x7 or x10), if leverage is authorized
    function deposit(LongShort longShort, uint128 amount, Leverage leverage) external isActive isKYCed isLeveragePossible(leverage) hasMinDeposit(amount) {
        (bool success, bytes memory res) = Token.call(abi.encodeWithSelector(IERC20.balanceOf.selector, msg.sender));
        require(success, "Call err");

        uint256 balance = abi.decode(res, (uint256));
        require(balance >= amount, "Insufficient balance");

        (success, res) = Token.call(abi.encodeWithSelector(IERC20.allowance.selector, msg.sender, address(this)));

        if (success) {
            uint256 allowance = abi.decode(res, (uint256));

            require(allowance >= amount, "Insufficient allowance");
            (success, res) = Token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, msg.sender, address(this), uint256(amount)));

            if (success && abi.decode(res, (bool))) {
                uint timestamp = Utils.getTimeStamp(block.timestamp, _fixings[_fixings.length - 1].timestamp, _currentFixingUpdateInterval);
                uint128 minFee = getMinimumFee(msg.sender, timestamp, timestamp + _expiryInterval, amount);
                // The deposit can only be an increase in position
                // -> hence, we remove the minFee from the deposit
                amount = SafeMath.sub128(amount, minFee);

                Token.call(abi.encodeWithSelector(IERC20.transfer.selector, Owner, minFee));

                // We just write the deposit
                // The fee is charged when fixing is updated
                writeDeposit(msg.sender, _fixings.length - 1, timestamp, longShort, amount, minFee, leverage);
            }
        }
    }

    /// @notice Reduces a position
    /// @param positionIndex The index of the position
    /// @param amount The reduction amount. If amount is bigger than position amount, the position is closed.
    // A position that is closed leads to re-organization of existing positions.
    function reducePosition(uint32 positionIndex, uint128 amount) public override {
        if (_positions[msg.sender].length > positionIndex) {
            Position storage position = _positions[msg.sender][positionIndex];

            if (amount > position.amount) amount = position.amount;
            uint128 penalty;
            uint128 fee = getPositionFee(block.timestamp, position.startDate, position.expiry, amount, position.minFeePaid);

            // If position is offset before expected term, a penalty applies
            if (position.startDate > block.timestamp || block.timestamp < position.expiry) {
                // This penalty is the for the pool and will remain in pool liquidity
                penalty = applyPenalty(amount);
            }

            int64 rate = getRate(position.longShort, position.leverage, position.fixingIndex0);
            uint128 compensationAmt = 0;

            // If rate is positive, only a pro-rata interest is paid
            // If rate is negative, msg.sender shall pay the full amount due
            if (rate > 0) {
                uint64 proRata = Utils.getProRata(Utils.getTimeStamp(block.timestamp, StartDate, _currentFixingUpdateInterval), position, _expiryInterval);
                rate = Math.multSigned(int64(proRata), rate);
            }
            else if (isCompensable(position.longShort)) {
                compensationAmt = compensationAmt = getCompensationAmount(position.amount, rate, _poolTokenDecimals);
            } 

            if (position.longShort == LongShort.Long) {
                TotalLongPositions[uint8(position.leverage)] = SafeMath.sub128(TotalLongPositions[uint8(position.leverage)], amount);
            } else {
                TotalShortPositions[uint8(position.leverage)] = SafeMath.sub128(TotalShortPositions[uint8(position.leverage)], amount);
            }

            setRatios();

            if (position.amount <= amount) Utils.removePositionFromArray(positionIndex, _positions[msg.sender]);

            // Interest is computed on the whole amount
            int128 interest = int128((int160(uint160(amount)) * rate) >> 32);

            // We remove the penalty and fee
            uint128 totalTransfer = SafeMath.sub128(amount, penalty);
            totalTransfer = SafeMath.sub128(totalTransfer, fee);

            // We charge or we pay the interest
            if (rate < 0) totalTransfer = SafeMath.subOr0_128(totalTransfer, uint128(-interest));
            else totalTransfer = SafeMath.add128(totalTransfer, uint128(interest));

            (bool success, ) = Token.call(abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, uint256(totalTransfer)));

            if (success) {
                if (fee > 0) Token.call(abi.encodeWithSelector(IERC20.transfer.selector, Owner, uint256(fee)));
                if (compensationAmt != 0) CompensationToken.call(abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, uint256(compensationAmt)));
                emit PositionReduced(msg.sender, block.timestamp, totalTransfer);
            }
        }
    }

    function transferFee(uint128 totalShortPosition, uint128 totalLongPosition) internal override returns(uint128 feeShort, uint128 feeLong) {
        feeShort = uint128((uint136(totalShortPosition) * Fee * _currentAccrualYF / (1_000_000 * Utils.ONE_DAY_YF)));
        Token.call(abi.encodeWithSelector(IERC20.transfer.selector, Owner, uint256(feeShort)));

        feeLong = uint128((uint136(totalLongPosition) * Fee * _currentAccrualYF / (1_000_000 * Utils.ONE_DAY_YF)));
        Token.call(abi.encodeWithSelector(IERC20.transfer.selector, Owner, uint256(feeLong)));

        _accumulatedFee = SafeMath.add128(_accumulatedFee, feeShort);
        _accumulatedFee = SafeMath.add128(_accumulatedFee, feeLong);
    }
}