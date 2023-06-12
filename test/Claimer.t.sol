// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import { Claimer } from "src/Claimer.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SD59x18 } from "prb-math/SD59x18.sol";

import { PrizePoolStub } from "./stub/PrizePoolStub.sol";
import { VaultStub } from "./stub/VaultStub.sol";
import { LinearVRGDALib } from "src/lib/LinearVRGDALib.sol";

contract ClaimerTest is Test {
    uint256 public constant MINIMUM_FEE = 0.0001e18;
    uint256 public constant MAXIMUM_FEE = 2**128;
    uint256 public constant TIME_TO_REACH_MAX = 86400;
    uint256 public constant ESTIMATED_PRIZES = 1000;
    uint256 public constant SMALLEST_PRIZE_SIZE = 1e18;
    uint256 public constant UNSOLD_100_SECONDS_IN_FEE = 100893106284719;
    uint256 public constant SOLD_ONE_100_SECONDS_IN_FEE = 95351966415391;
    uint64 public constant MAX_FEE_PERCENTAGE_OF_PRIZE = 0.5e18;

    Claimer public claimer;
    PrizePoolStub public prizePool;
    VaultStub public vault;

    SD59x18 public decayConstant;
    uint256 public ahead1_fee; // = 0.000090909090909090e18;

    address winner1 = 0x690B9A9E9aa1C9dB991C7721a92d351Db4FaC990;
    address winner2 = 0x4008Ed96594b645f057c9998a2924545fAbB6545;
    address winner3 = 0x796486EBd82E427901511d130Ece93b94f06a980;
    address winner4 = 0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE;
    address winner5 = 0x9ebC8E61f87A301fF25a606d7C06150f856F24E2;
    address winner6 = 0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5;

    function setUp() public {
        vm.warp(TIME_TO_REACH_MAX * 100);
        prizePool = new PrizePoolStub();
        vault = new VaultStub();
        claimer = new Claimer(prizePool, MINIMUM_FEE, MAXIMUM_FEE, TIME_TO_REACH_MAX, ud2x18(MAX_FEE_PERCENTAGE_OF_PRIZE));
        decayConstant = LinearVRGDALib.getDecayConstant(LinearVRGDALib.getMaximumPriceDeltaScale(MINIMUM_FEE, MAXIMUM_FEE, TIME_TO_REACH_MAX));
        ahead1_fee = LinearVRGDALib.getVRGDAPrice(MINIMUM_FEE, 0, 1, LinearVRGDALib.getPerTimeUnit(ESTIMATED_PRIZES, TIME_TO_REACH_MAX), decayConstant);
    }

    function testConstructor() public {
        assertEq(address(claimer.prizePool()), address(prizePool));
        assertEq(claimer.minimumFee(), MINIMUM_FEE);
        assertEq(claimer.decayConstant().unwrap(), decayConstant.unwrap());
    }

    function testClaimPrizes_single() public {
        address[] memory winners = [winner1];
        uint32[][] memory prizeIndices = newPrizeIndices(1, 1);
        mockPrizePool(1, -100, 0);
        mockClaimPrizes(1, winners, prizeIndices, uint96(UNSOLD_100_SECONDS_IN_FEE), address(this), 100);
        (uint256 claimCount, uint256 totalFees) = claimer.claimPrizes(vault, 1, winners, prizeIndices, address(this));
        assertEq(claimCount, 1, "Number of prizes claimed");
        assertEq(totalFees, UNSOLD_100_SECONDS_IN_FEE, "Total fees");
    }

    function testClaimPrizes_multiple() public {
        address[] memory winners = [winner1, winner2];
        uint32[][] memory prizeIndices = newPrizeIndices(2, 1);
        mockPrizePool(1, -100, 0);
        mockClaimPrizes(1, winners, prizeIndices, (uint96(UNSOLD_100_SECONDS_IN_FEE) + uint96(SOLD_ONE_100_SECONDS_IN_FEE)) / 2, address(this), 100);
        (uint256 claimCount, uint256 totalFees) = claimer.claimPrizes(vault, 1, winners, prizeIndices, address(this));
        assertEq(claimCount, 2, "Number of prizes claimed");
        assertEq(totalFees, UNSOLD_100_SECONDS_IN_FEE + SOLD_ONE_100_SECONDS_IN_FEE, "Total fees");
    }

    function testClaimPrizes_maxFee() public {
        address[] memory winners = [winner1];
        uint32[][] memory prizeIndices = newPrizeIndices(1, 1);
        mockPrizePool(1, -1, 0);
        mockLastCompletedDrawStartedAt(-80000); // much time has passed, meaning the fee is large
        mockClaimPrizes(1, winners, prizeIndices, uint96(0.5e18), address(this), 100);
        (uint256 claimCount, uint256 totalFees) = claimer.claimPrizes(1, winners, prizeIndices, address(this));
        assertEq(claimCount, 1, "Number of prizes claimed");
        assertEq(totalFees, 0.5e18, "Total fees");
    }

    function testClaimPrizes_veryLongElapsedTime() public {
        address[] memory winners = [winner1];
        uint32[][] memory prizeIndices = newPrizeIndices(1, 1);
        mockPrizePool(1, -1, 0);
        mockLastCompletedDrawStartedAt(-1_000_000); // a long time has passed, meaning the fee should be capped (and there should be no EXP_OVERFLOW!)
        mockClaimPrizes(1, winners, prizeIndices, uint96(0.5e18), address(this), 100);
        (uint256 claimCount, uint256 totalFees) = claimer.claimPrizes(vault, 1, winners, prizeIndices, address(this));
        assertEq(claimCount, 1, "Number of prizes claimed");
        assertEq(totalFees, 0.5e18, "Total fees");
    }

    function testComputeTotalFees_zero() public {
        mockPrizePool(1, -100, 0);
        assertEq(claimer.computeTotalFees(0), 0);
    }

    function testComputeTotalFees_one() public {
        mockPrizePool(1, -100, 0);
        assertEq(claimer.computeTotalFees(1), UNSOLD_100_SECONDS_IN_FEE);
    }

    function testComputeTotalFees_two() public {
        mockPrizePool(1, -100, 0);
        assertEq(claimer.computeTotalFees(2), UNSOLD_100_SECONDS_IN_FEE + SOLD_ONE_100_SECONDS_IN_FEE);
    }

    function testComputeMaxFee() public {
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.calculatePrizeSize.selector, 2), abi.encodePacked(SMALLEST_PRIZE_SIZE));
        assertEq(claimer.computeMaxFee(), 0.5e18);
    }

    function mockPrizePool(
        uint256 drawId,
        int256 drawEndedRelativeToNow,
        uint256 claimCount
    ) public {
        uint numberOfTiers = 2;
        vm.mockCall(address(prizePool), abi.encodeWithSignature("getLastCompletedDrawId()"), abi.encodePacked(drawId));
        vm.mockCall(address(prizePool), abi.encodeWithSignature("estimatedPrizeCount()"), abi.encodePacked(ESTIMATED_PRIZES));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.drawPeriodSeconds.selector), abi.encodePacked(TIME_TO_REACH_MAX));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.numberOfTiers.selector), abi.encodePacked(numberOfTiers));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.calculatePrizeSize.selector, numberOfTiers), abi.encodePacked(SMALLEST_PRIZE_SIZE));
        mockLastCompletedDrawAwardedAt(drawEndedRelativeToNow);
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.claimCount.selector), abi.encodePacked(claimCount));
    }

    function mockLastCompletedDrawAwardedAt(int256 drawEndedRelativeToNow) public {
        vm.mockCall(
            address(prizePool),
            abi.encodeWithSelector(prizePool.lastCompletedDrawAwardedAt.selector),
            abi.encodePacked(int256(block.timestamp) + drawEndedRelativeToNow)
        );
    }

    function newWinners(address winner) public view returns (address[] memory) {
        address[] memory winners = new address[](1);
        winners[0] = winner;
        return winners;
    }

    function newPrizeIndices(uint32 addressCount, uint32 prizeCount) public view returns (uint32[][] memory) {
        uint32[][] memory prizeIndices = new uint32[][](addressCount);
        for (uint256 i = 0; i < addressCount; i++) {
            prizeIndices[i] = new uint32[](prizeCount);
        }
        return prizeIndices;
    }

    function mockClaimPrizes(
        uint8 _tier,
        address[] memory _winners,
        uint32[][] memory _prizeIndices,
        uint96 _fee,
        address _feeRecipient,
        uint256 _result
    ) public {
        vm.mockCall(address(vault), abi.encodeWithSelector(vault.claimPrizes.selector, _tier, _winners, _prizeIndices, _fee, _feeRecipient), abi.encodePacked(_result));
    }

}
