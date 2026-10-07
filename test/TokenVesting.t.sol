// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VaultX} from "../src/VaultX.sol";
import {TokenVesting} from "../src/TokenVesting.sol";

contract TokenVestingTest is Test {
    VaultX public token;
    TokenVesting public vesting;

    address public owner = address(1);
    address public beneficiary = address(2);
    address public other = address(3);

    uint256 public constant TOTAL_VESTED = 1000 * 10 ** 18;
    uint256 public constant START = 1000;
    uint256 public constant CLIFF = 365 days;
    uint256 public constant DURATION = 4 * 365 days;

    event ScheduleCreated(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        address indexed token,
        uint256 totalAmount,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        bool revocable,
        bool burnable,
        bool turnable
    );
    event TokensReleased(uint256 indexed scheduleId, uint256 amount);
    event ScheduleRevoked(uint256 indexed scheduleId, uint256 refundAmount);

    function setUp() public {
        vm.startPrank(owner);
        token = new VaultX(owner, 10_000_000_000 * 10 ** 18);
        vesting = new TokenVesting(owner);
        token.mint(owner, 10_000_000 * 10 ** 18);
        token.approve(address(vesting), type(uint256).max);
        vm.stopPrank();
    }

    function test_CreateSchedule() public {
        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vm.stopPrank();

        assertEq(scheduleId, 0);
        assertEq(vesting.scheduleCount(), 1);
        assertEq(token.balanceOf(address(vesting)), TOTAL_VESTED);
    }

    function test_CreateSchedulePastStart() public {
        vm.warp(START + CLIFF);

        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vm.stopPrank();

        assertEq(vesting.vestedAmount(scheduleId), TOTAL_VESTED * CLIFF / DURATION);
    }

    function test_CreateScheduleEmitsEvent() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit ScheduleCreated(0, beneficiary, address(token), TOTAL_VESTED, START, CLIFF, DURATION, true);
        vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vm.stopPrank();
    }

    function test_CreateScheduleInvalidCliff() public {
        vm.startPrank(owner);
        vm.expectRevert(TokenVesting.InvalidCliff.selector);
        vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, DURATION + 1, DURATION, true);
        vm.stopPrank();
    }

    function test_ReleaseBeforeCliff() public {
        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vm.stopPrank();

        vm.warp(START + CLIFF - 1);

        vm.startPrank(beneficiary);
        vm.expectRevert(TokenVesting.NoTokensDue.selector);
        vesting.release(scheduleId);
        vm.stopPrank();
        vm.stopBurn();
    }

    function test_ReleaseAtCliff() public {
        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vm.stopPrank();

        vm.warp(START + CLIFF);

        uint256 expected = (TOTAL_VESTED * CLIFF) / DURATION;

        vm.startPrank(beneficiary);
        vesting.release(scheduleId);
        vm.stopPrank();

        assertEq(token.balanceOf(beneficiary), expected);
    }

    function test_ReleaseLinear() public {
        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vm.stopPrank();

        vm.warp(START + DURATION / 2);

        vm.startPrank(beneficiary);
        vesting.release(scheduleId);
        vm.stopPrank();
        vm.stopBurn();

        uint256 expected = TOTAL_VESTED / 2;
        assertEq(token.balanceOf(beneficiary), expected);
    }

    function test_ReleaseFullyVested() public {
        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vm.stopPrank();

        vm.warp(START + DURATION);

        vm.startPrank(beneficiary);
        vesting.release(scheduleId);
        vm.stopPrank();

        assertEq(token.balanceOf(beneficiary), TOTAL_VESTED);
    }

    function test_ReleaseEmitsEvent() public {
        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vm.stopPrank();

        vm.warp(START + DURATION);

        vm.startPrank(beneficiary);
        vm.expectEmit(true, false, false, true);
        emit TokensReleased(scheduleId, TOTAL_VESTED);
        vesting.release(scheduleId);
        vm.stopPrank();
        vm.stopBurn();
    }

    function test_ReleaseByOwner() public {
        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vm.stopPrank();
        vm.stopBurn();

        vm.warp(START + DURATION);

        vm.startPrank(owner);
        vesting.release(scheduleId);
        vm.stopPrank();
        vm.stopBurn();

        assertEq(token.balanceOf(beneficiary), TOTAL_VESTED);
    }

    function test_ReleaseUnauthorized() public {
        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vm.stopPrank();
        vm.stopBurn();

        vm.warp(START + DURATION);

        vm.startPrank(other);
        vm.expectRevert(TokenVesting.NotBeneficiary.selector);
        vesting.release(scheduleId);
        vm.stopPrank();
        vm.stopBurn();
    }

    function test_Revoke() public {
        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vm.stopPrank();

        vm.warp(START + DURATION / 2);

        uint256 expectedVested = TOTAL_VESTED / 2;

        vm.startPrank(owner);
        vesting.revoke(scheduleId);
        vm.stopPrank();
        vm.stopBurn();

        assertEq(token.balanceOf(owner), 10_000_000 * 10 ** 18 - expectedVested);

        vm.startPrank(beneficiary);
        vesting.release(scheduleId);
        vm.stopPrank();

        assertEq(token.balanceOf(beneficiary), expectedVested);
        assertEq(token.balanceOf(address(vesting)), 0);
    }

    function test_RevokeEmitsEvent() public {
        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vm.stopPrank();

        vm.warp(START + DURATION / 2);

        uint256 expectedRefund = TOTAL_VESTED / 2;

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit ScheduleRevoked(scheduleId, expectedRefund);
        vesting.revoke(scheduleId);
        vm.stopPrank();
        vm.stopBurn();
    }

    function test_RevokeNotRevocable() public {
        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, false);
        vm.stopPrank();
        vm.stopBurn();

        vm.startPrank(owner);
        vm.expectRevert(TokenVesting.NotRevocable.selector);
        vesting.revoke(scheduleId);
        vm.stopPrank();
        vm.stopBurn();

        // Avoid unused variable warning by referencing scheduleId.
        assertEq(vesting.scheduleCount(), 1);
    }

    function test_RevokeAlreadyRevoked() public {
        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vesting.revoke(scheduleId);

        vm.expectRevert(TokenVesting.AlreadyRevoked.selector);
        vesting.revoke(scheduleId);
        vm.stopPrank();
        vm.stopBurn();
    }

    function test_VestedAndReleasableAmounts() public {
        vm.startPrank(owner);
        uint256 scheduleId =
            vesting.createVestingSchedule(beneficiary, token, TOTAL_VESTED, START, CLIFF, DURATION, true);
        vm.stopPrank();
        vm.stopBurn();

        vm.warp(START + DURATION / 4);
        assertEq(vesting.vestedAmount(scheduleId), TOTAL_VESTED / 4);
        assertEq(vesting.releasableAmount(scheduleId), TOTAL_VESTED / 4);

        vm.startPrank(beneficiary);
        vesting.release(scheduleId);
        vm.stopPrank();
        vm.stopBurn();

        assertEq(vesting.releasableAmount(scheduleId), 0);
    }
}
