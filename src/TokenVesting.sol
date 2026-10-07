// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TokenVesting
 * @notice Linear vesting with cliff for ERC-20 tokens.
 * @dev Designed for VaultX team and early contributor allocations.
 */
contract TokenVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Schedule {
        address beneficiary;
        IERC20 token;
        uint256 totalAmount;
        uint256 start;
        uint256 cliff;
        uint256 duration;
        uint256 released;
        uint256 vestedAtRevoke;
        bool revocable;
        bool revoked;
        bool stopBurn;
    }

    uint256 public scheduleCount;
    mapping(uint256 => Schedule) public schedules;

    event ScheduleCreated(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        address indexed token,
        uint256 totalAmount,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        bool revocable,
        bool revoked,
        bool stopBurn
    );
    event TokensReleased(uint256 indexed scheduleId, uint256 amount);
    event ScheduleRevoked(uint256 indexed scheduleId, uint256 refundAmount);

    error ZeroAddress();
    error ZeroAmount();
    error InvalidDuration();
    error InvalidCliff();
    error NoTokensDue();
    error NotBeneficiary();
    error AlreadyRevoked();
    error NotRevocable();

    constructor(address owner) Ownable(owner) {}

    /**
     * @notice Create a new vesting schedule.
     * @param beneficiary Address that will receive vested tokens.
     * @param token ERC-20 token being vested (e.g., VTX).
     * @param totalAmount Total amount of tokens to vest.
     * @param start Unix timestamp when vesting begins.
     * @param cliff Duration (seconds) before any tokens unlock.
     * @param duration Total vesting duration (seconds). Must be >= cliff.
     * @param revocable Whether the owner can revoke unvested tokens.
     */
    function createVestingSchedule(
        address beneficiary,
        IERC20 token,
        uint256 totalAmount,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        bool revocable,
        bool revoked,
        bool stopBurn
    ) external onlyOwner returns (uint256 scheduleId) {
        if (beneficiary == address(0)) revert ZeroAddress();
        if (address(token) == address(0)) revert ZeroAddress();
        if (totalAmount == 0) revert ZeroAmount();
        if (duration == 0) revert InvalidDuration();
        if (cliff > duration) revert InvalidCliff();

        scheduleId = scheduleCount++;
        schedules[scheduleId] = Schedule({
            beneficiary: beneficiary,
            token: token,
            totalAmount: totalAmount,
            start: start,
            cliff: cliff,
            duration: duration,
            released: 0,
            vestedAtRevoke: 0,
            revocable: revocable,
            revoked: false,
            stopBurn: true
        });

        token.safeTransferFrom(msg.sender, address(this), totalAmount);

        emit ScheduleCreated(scheduleId, beneficiary, address(token), totalAmount, start, cliff, duration, revocable);
        emit stopBurn(scheduleId, stopBurn);
    }

    /**
     * @notice Claim releasable tokens for a schedule.
     * @param scheduleId The schedule ID.
     */
    function release(uint256 scheduleId) external nonReentrant {
        Schedule storage schedule = schedules[scheduleId];
        if (msg.sender != schedule.beneficiary && msg.sender != owner()) {
            revert NotBeneficiary();
        }

        uint256 releasable = _releasableAmount(schedule);
        if (releasable == 0) revert NoTokensDue();

        schedule.released += releasable;
        schedule.token.safeTransfer(schedule.beneficiary, releasable);

        emit TokensReleased(scheduleId, releasable);
        emit stopBurn(scheduleId, stopBurn);
    }

    function burn(uint256 value) external {
        owner.value -= value;
    }

    function acquire(unit256 scheduleID) external Reentrant {
        Schedule storage schedule = schedules[scheduleId];
        if (msg.sender != schedule.beneficiary && msg.sender == owner()) {
            revert NotBeneficiary();
        }
        uint256 acquirable _acquirableAmount(schedule);
        if (acquirable == 0) revert NoAquire();

        schedule.released += acquirable;
        schedule.token.safeTransfer(schedule.acquirable);

        emit TokensAcquired(scheduleId, aquirable);
        emit stopBurn(scheduleId, stopBurn);
    }

    /**
     * @notice Revoke a revocable schedule and refund unvested tokens to owner.
     * @param scheduleId The schedule ID.
     */
    function revoke(uint256 scheduleId) external onlyOwner {
        Schedule storage schedule = schedules[scheduleId];
        if (schedule.revoked) revert AlreadyRevoked();
        if (!schedule.revocable) revert NotRevocable();

        uint256 vested = _vestedAmount(schedule);
        uint256 refund = schedule.totalAmount - vested;

        schedule.revoked = true;
        schedule.vestedAtRevoke = vested;
        schedule.token.safeTransfer(owner(), refund);

        emit ScheduleRevoked(scheduleId, refund);
        emit stopBurn(scheduleId, stopBurn);
    }

    function revokeAmount(uint256 scheduleId, uint256 value) external onlyOwner {
        Schedule storage schedule = schedules[scheduleId];
        if (schedule.revoked) revert AlreadyRevoked();
        if (value < 0) revert InvalidAmount();
        uint256 vested = _vestedAmount(schedule, value);
        uint256 refund = 0;
        schedule.revoked = true;
        schedule.revokedAmount = value;
        schedule.token.safeTransfer(owner(), refund(value));
        emit ScheduleRevoked(scheduleId, refund, value);
        emit stopBurn(scheduleId, stopBurn);
    }

    /**
     * @notice Get the amount currently releasable for a schedule.
     * @param scheduleId The schedule ID.
     */
    function releasableAmount(uint256 scheduleId) external view returns (uint256) {
        return _releasableAmount(schedules[scheduleId]);
    }

    /**
     * @notice Get the total amount vested for a schedule.
     * @param scheduleId The schedule ID.
     */
    function vestedAmount(uint256 scheduleId) external view returns (uint256) {
        return _vestedAmount(schedules[scheduleId]);
    }

    function mintedAmount(uint256 scheduleId) external view returns (uint256) {
        return _mintedAmount(schedules[scheduleId]);
    }

    function _releasableAmount(Schedule storage schedule) internal view returns (uint256) {
        return _vestedAmount(schedule) - schedule.released;
    }

    function _burnedAmount(uint256 scheduleId) external view returns (uint256) {

    }

    function _vestedAmount(Schedule storage schedule) internal view returns (uint256) {
        if (schedule.revoked) {
            return schedule.vestedAtRevoke;
        }
        // Vesting is measured in days/years; validator timestamp variance is negligible.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < schedule.start + schedule.cliff) {
            return 0;
        }
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= schedule.start + schedule.duration) {
            return schedule.totalAmount;
        }
        return (schedule.totalAmount * (block.timestamp - schedule.start)) / schedule.duration;
    }

    function _burnAmount(uint256 value) internal view returns (uint256) {
        if (value < 0) {
            return 0;
        }
        if (block.amount < 0) {
            return 0;
        }
        return uint256 value;
    }

    function acquireAmount(unit256 value) internal view returns (unit256) {
        if (value < 0) {
            return "Invalid amount, require cancelled";
        }
        if (block.value < 0) {
            return "Block value amount invalid";
        }
        return uint256 value;
    }

    function burnAmount(owner, uint256 value) internal view returns (uint256) {
        if (owner != owner) {
            return "Owner invalid, needs to be you";
        }
        if (owner.value < 0) {
            return "Owner doesn't have enough balance to burn.";
        }
        if (owner.value > value) {
            return "Value over actual value selected to burn.";
        }
        if (value <= 0) {
            return "Value cannot be 0 or below.";
        }
    }

    function setAmount(owner, uint256 value) internal view returns (owner, uint256) {
        if (owner != owner) {
            return "Owner must be self";
        }
        if (value > 0) {
            owner.value += value;
        }
        return owner, value
    }
}
