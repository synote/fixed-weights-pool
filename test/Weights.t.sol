pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {WeightMath} from "../src/WeightMath.sol";

uint256 constant amountIn = 1 ether;
uint256 constant amountOut = 1 ether;
uint256 constant reserveIn = 100 ether;
uint256 constant reserveOut = 100 ether;
uint256 constant weightIn = 0.6 ether;
uint256 constant weightOut = 0.4 ether;
uint256 constant invariant = 100 ether;

uint256 constant ACCEPTABLE_RELATIVE_SWAP_ERROR = 50000;
uint256 constant ACCEPTABLE_RELATIVE_INVARIANT_ERROR = 20000;

contract WeightInvariantTest is Test {

    function testGetInvariant() public {
        uint256[] memory reserves = new uint256[](2);
        reserves[0] = reserveIn;
        reserves[1] = reserveOut;

        uint256[] memory weights = new uint256[](2);
        weights[0] = weightIn;
        weights[1] = weightOut;

        uint256 reserveTwoToken = WeightMath.calcInvariant(reserves[0], reserves[1], weights[0], weights[1]);
        // console.log("Liquidity of reserves: ", reserveTwoToken);
        assertEq(reserveTwoToken, 99999999999999999785);
    }

    function testAmountOut() public {
        uint256[] memory reserves = new uint256[](2);
        uint256[] memory weights = new uint256[](2);
        reserves[0] = 1000 ether;
        reserves[1] = 1000 ether;

        weights[0] = 0.5 ether;
        weights[1] = 0.5 ether;

        uint256 out = WeightMath.calcAmountOut(10 ether, reserves[0], reserves[1], weights[0], weights[1]);
        // 9.9 ether
        assertEq(out, 9900990099009900000);
    }
}