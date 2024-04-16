// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import "./Library.sol";

library FinancialLib {
/**
 * Calculates d1.
 */
  function d1 (int64 volatility, int64 term) internal pure returns(int64, int64) {
    int64 vol_sqrtT = Math.mult(volatility, Math.sqrt(term));
    return (vol_sqrtT >> 1, vol_sqrtT);
  }

/**s
 * Calculates d2.
 */
  function d2 (int64 volatility, int64 term) internal pure returns(int64) {
    (int64 _d1, int64 vol_sqrtT) = d1(volatility, term);
    return Math.sub(_d1, vol_sqrtT >> 1);
  }

function call(int64 forward, int64 volatility, int64 term) internal pure returns(int64) {
    (int64 _d1, ) = d1(volatility, term);
    int64 f1 = Math.mult(forward, cnsd(_d1));
    int64 f2 = Math.mult(forward, cnsd(d2(volatility, term)));

    return f1 - f2;
}

function put(int64 forward, int64 volatility, int64 term) internal pure returns(int64) {
    (int64 _d1, ) = d1(volatility, term);
    int64 f1 = Math.mult(forward, cnsd(Math.neg(_d1)));
    int64 f2 = Math.mult(forward, cnsd(Math.neg(d2(volatility, term))));

    return f2 - f1;
}

function straddle(int64 forward, int64 volatility, int64 term) internal pure returns(int64) {
    return Math.add(call(forward, volatility, term), put(forward, volatility, term));
}

int64 private constant sqrt_2 = 6074001000;

function cnsd(int64 x) internal pure returns(int64) {
    return Math.add(Math.One_32, erf(Math.mult(x, sqrt_2))) >> 1;
}

    int64 private constant erx = 3629517568;

    int64 private constant efx = 551384324;
    int64 private constant efx8 = 4411074593;
    int64 private constant pp0 = 551384324;
    int64 private constant pp1 = -1396045220;
    int64 private constant pp2 = -122328183;
    int64 private constant pp3 = -24783122;
    int64 private constant pp4 = -102061;
    int64 private constant qq1 = 1709041463;
    int64 private constant qq2 = 279268437;
    int64 private constant qq3 = 21824044;
    int64 private constant qq4 = 569061;
    int64 private constant qq5 = -17009;

    int64 private constant pa0 = -10145222;
    int64 private constant pa1 = 1781793462;
    int64 private constant pa2 = -1598620655;
    int64 private constant pa3 = 1367288321;
    int64 private constant pa4 = -476289085;
    int64 private constant pa5 = 152378157;
    int64 private constant pa6 = -9304512;
    int64 private constant qa1 = 457074201;
    int64 private constant qa2 = 2320991383;
    int64 private constant qa3 = 308501722;
    int64 private constant qa4 = 541901263;
    int64 private constant qa5 = 58570829;
    int64 private constant qa6 = 51473035;

    int64 private constant ra0 = -42369612;
    int64 private constant ra1 = -2980099878;
    int64 private constant ra2 = -453489543;
    int64 private constant ra3 = -2679000130;
    int64 private constant ra4 = -69748838;
    int64 private constant ra5 = -79287284;
    int64 private constant ra6 = -3491268771;
    int64 private constant ra7 = -42152223565;
    int64 private constant sa1 = 844015691;
    int64 private constant sa2 = 59123555;
    int64 private constant sa3 = 186644623;
    int64 private constant sa4 = 277191723;
    int64 private constant sa5 = 184257593;
    int64 private constant sa6 = 46658380;
    int64 private constant sa7 = 28219007890;
    int64 private constant sa8 = -259520887;

    int64 private constant rb0 = -42369607;
    int64 private constant rb1 = -3432895366;
    int64 private constant rb2 = -762698356;
    int64 private constant rb3 = -68992802;
    int64 private constant rb4 = -273832702;
    int64 private constant rb5 = -4402750;
    int64 private constant rb6 = -207669911;
    int64 private constant sb1 = 1303009787;
    int64 private constant sb2 = 139926819;
    int64 private constant sb3 = 6600203;
    int64 private constant sb4 = 13743286;
    int64 private constant sb5 = 10965268;
    int64 private constant sb6 = 203808457;
    int64 private constant sb7 = -963831568;

    int64 private constant erflim_up = 0x3FFFFFFFFFFFFFFF;
    int64 private constant erflim_down = -0x4000000000000000;


    function erf(int64 x) internal pure returns(int64) {
        if (x > erflim_up) return Math.One_32;
        if (x < erflim_down) return Math.neg(Math.One_32);

        int64 ax = int64(x < 0 ? -x : x);
        int64 z = 0;
        int64 R = 0;
        int64 S = 0;
        int64 y = 0;

        if(ax < 3623878656) {
            if(ax < 16) {
                return Math.add(x, Math.mult(efx, x));
            }

            z = Math.mult(x, x);
            R = Math.add(pp2, Math.mult(z, Math.add(pp3, Math.mult(z, pp4))));
            R = Math.add(pp0, Math.mult(z, Math.add(pp1, Math.mult(z, R))));
            S = Math.add(qq2, Math.mult(z, Math.add(qq3, Math.mult(z, Math.add(qq4, Math.mult(z, qq5))))));
            S = Math.add(Math.One_32, Math.mult(z, Math.add(qq1, Math.mult(z, S))));
            y = Math.div(R, S);

            return Math.add(x, Math.mult(x, y));
        }

        if(ax < 5368709120) {
            z = Math.sub(ax, Math.One_32);
            int64 P = Math.mult(z, Math.add(pa4, Math.mult(z, Math.add(pa5, Math.mult(z, pa6)))));
            P = Math.mult(z, Math.add(pa2, Math.mult(z, Math.add(pa3, P))));
            P = Math.add(pa0, Math.mult(z, Math.add(pa1, P)));
            y = Math.add(qa4, Math.mult(z, Math.add(qa5, Math.mult(z, qa6))));
            y = Math.mult(z, Math.add(qa2, Math.mult(z, Math.add(qa3, Math.mult(z, y)))));
            y = Math.add(Math.One_32, Math.mult(z, Math.add(qa1, y)));
            
            if( x >= 0) return Math.add(erx, Math.div(P, y)); 
            else return Math.sub(Math.neg(erx), Math.div(P, y));
        }
        if (ax >= 25769803776) {
            if(x >= 0) return  4294967253; 
            else return -4294967253;
        }

        z = Math.inverse(Math.mult(ax, ax));

        if(ax < 12271335131) {
            R = Math.mult(z, Math.add(ra5, Math.mult(z, Math.add(ra6, Math.mult(z, ra7)))));
            R = Math.add(ra2, Math.mult(z, Math.add(ra3, Math.mult(z, Math.add(ra4, R)))));
            R = Math.add(ra0, Math.mult(z, Math.add(ra1, Math.mult(z, R))));
            S = Math.mult(z, Math.add(sa6, Math.mult(z, Math.add(sa7, Math.mult(z, sa8)))));
            S = Math.mult(z, Math.add(sa3, Math.mult(z, Math.add(sa4, Math.mult(z, Math.add(sa5, S))))));
            S = Math.add(Math.One_32, Math.mult(z, Math.add(sa1, Math.mult(z, Math.add(sa2, S)))));
        } else {
            R = Math.mult(z, Math.add(rb4, Math.mult(z, Math.add(rb5, Math.mult(z, rb6)))));
            R = Math.mult(z, Math.add(rb2, Math.mult(z, Math.add(rb3, R))));
            R = Math.add(rb0, Math.mult(z, Math.add(rb1, R)));
            S = Math.add(sb5, Math.mult(z, Math.add(sb6, Math.mult(z, sb7))));
            S = Math.mult(z, Math.add(sb3, Math.mult(z, Math.add(sb4, Math.mult(z, S)))));
            S = Math.add(Math.One_32, Math.mult(z, Math.add(sb1, Math.mult(z, Math.add(sb2, S)))));
        }

        y = Math.exp(Math.add(Math.neg(Math.add(Math.mult(ax, ax), 2415919104)), Math.div(R, S)));

        if(x >= 0) return Math.sub(Math.One_32, Math.div(y, ax)); 
        else return  Math.sub(Math.div(y, ax), Math.One_32);

    }
}


