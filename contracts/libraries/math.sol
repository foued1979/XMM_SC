// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

library Math {
  /*
  * Minimum value signed 32.32-bit fixed point number may have.
  */
  int64 internal constant MIN_32x32 = -0x8000000000000000;
  /*
  * Maximum value signed 32.32-bit fixed point number may have. 
  */
  int64 internal constant MAX_32x32 = 0x7FFFFFFFFFFFFFFF;
  /*
  * Maximum value unsigned 32.32-bit. 
  */
  uint64 internal constant MAX_U32x32 = 0xFFFFFFFFFFFFFFFF;
  /*
  * Maximum value unsigned 128-bit fixed point number may have. 
  */
  uint128 internal constant MAX_128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
  /*
  * Maximum value unsigned 128-bit fixed point number may have. 
  */
  uint224 internal constant MAX_224 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
  /*
  * One
  */
  uint64 internal constant One_32 = 0x100000000;
  uint128 internal constant One_64 = 0x10000000000000000;

  function max(int8 x, int8 l) internal pure returns(uint8) {
    return x > l ? uint8(x) : uint8(l);
  }

  /**
  * @notice Calculates x + y for unsigned integer
  */
  function add(uint64 x, uint64 y) internal pure returns(uint64)
  {
    unchecked {
      uint64 res = x + y;
      require (res >= x && res >= y);
      return res;
    }
  }

  function addSigned(int64 x, int64 y) internal pure returns(int64)
  {
    unchecked {
      int96 res = int96(x) + y;
      require (res >= MIN_32x32 && res <= MAX_32x32);
      return int64(res);
    }
  }

  /**
  * @notice Calculates x - y.
  */
  function sub(uint64 x, uint64 y) internal pure returns (uint64) {
    unchecked {
      require (x > y);
      return x - y;
    }
  }

  /**
  * @notice Calculates x - y.
  */
  function subSigned(uint64 x, uint64 y) internal pure returns (int64) {
    unchecked {
      int128 res = int128(uint128(x)) - int128(uint128(y));
      require (res >= MIN_32x32 && res <= MAX_32x32);
      return int64(res);
    }
  }

  function absSub(uint64 x, uint64 y) internal pure returns (uint64) {
    unchecked {
      if (x > y) {
        return x - y;
      } else {
        return y - x;
      }
    }
  }

  /**
  * @notice Calculates x * y rounding down.
  */
  function mult(uint64 x, uint64 y) internal pure returns (uint64) {
    unchecked {
      uint128 res = (uint128(x) * y) >> 32;

      require (res >= 0 && res <= MAX_U32x32, "Overflow");
      return uint64(res);
    }
  }

  /**
  * @notice Calculates x / y rounding towards zero.
  */
  function div(uint64 x, uint64 y) internal pure returns (uint64) {
    unchecked {
      require (y != 0);

      uint96 res = (uint96(x) << 32) / y;

      require (res <= MAX_U32x32);
      return uint64(res);
    }
  }

  /**
  * @notice Calculates 1 / x rounding towards zero.
  */
  function inverse(uint64 x) internal pure returns (uint64) {
    unchecked {
      require (x != 0);

      uint128 res = One_64 / x;

      require (res <= MAX_U32x32);
      return uint64(res);
    }
  }

  /**
  * @notice Calculates the arithmetic average of x and y.
  */
  function avg (uint64 x, uint64 y) internal pure returns (uint64) {
    unchecked {
      return add(x, y) >> 1;
    }
  }
}