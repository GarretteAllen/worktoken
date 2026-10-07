// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {VaultX} from "../src/VaultX.sol";
import {TokenVesting} from "../src/TokenVesting.sol";

/**
 * @title DeployVaultX
 * @notice Deployment script for VaultX token and TokenVesting contract.
 * @dev Run with:
 *      forge script script/DeployVaultX.s.sol --rpc-url $RPC_URL --broadcast --verify
 *      Set required env vars in .env before running.
 */
contract DeployVaultX is Script {
    function run() public {
        vm.startBroadcast();

        address deployer = msg.sender;

        address admin = vm.envOr("VAULTX_ADMIN", deployer);
        address treasury = vm.envOr("VAULTX_TREASURY", deployer);
        address rewards = vm.envOr("VAULTX_REWARDS", deployer);
        address liquidity = vm.envOr("VAULTX_LIQUIDITY", deployer);
        address team = vm.envOr("VAULTX_TEAM", deployer);

        uint256 maxSupply = vm.envOr("VAULTX_MAX_SUPPLY", uint256(1_000_000_000 * 10 ** 18));

        uint256 treasuryAllocation = vm.envOr("VAULTX_TREASURY_ALLOCATION", uint256(200_000_000 * 10 ** 18));
        uint256 rewardsAllocation = vm.envOr("VAULTX_REWARDS_ALLOCATION", uint256(300_000_000 * 10 ** 18));
        uint256 liquidityAllocation = vm.envOr("VAULTX_LIQUIDITY_ALLOCATION", uint256(100_000_000 * 10 ** 18));
        uint256 teamAllocation = vm.envOr("VAULTX_TEAM_ALLOCATION", uint256(100_000_000 * 10 ** 18));

        uint256 totalInitialAllocation = treasuryAllocation + rewardsAllocation + liquidityAllocation + teamAllocation;
        require(totalInitialAllocation <= maxSupply, "DeployVaultX: allocations exceed max supply");

        VaultX token = new VaultX(admin, maxSupply);
        console2.log("VaultX deployed at:", address(token));
        console2.log("  max supply:", maxSupply);
        console2.log("  admin:", admin);

        TokenVesting vesting = new TokenVesting(admin);
        console2.log("TokenVesting deployed at:", address(vesting));

        token.mint(treasury, treasuryAllocation);
        token.mint(rewards, rewardsAllocation);
        token.mint(liquidity, liquidityAllocation);

        console2.log("Minted allocations:");
        console2.log("  treasury:", treasuryAllocation);
        console2.log("  rewards:", rewardsAllocation);
        console2.log("  liquidity:", liquidityAllocation);

        if (teamAllocation > 0) {
            token.mint(admin, teamAllocation);
            token.approve(address(vesting), teamAllocation);

            uint256 vestingStart = vm.envOr("VAULTX_VESTING_START", uint256(block.timestamp));
            uint256 vestingCliff = vm.envOr("VAULTX_VESTING_CLIFF", uint256(365 days));
            uint256 vestingDuration = vm.envOr("VAULTX_VESTING_DURATION", uint256(4 * 365 days));

            vesting.createVestingSchedule(
                team, token, teamAllocation, vestingStart, vestingCliff, vestingDuration, true
            );

            console2.log("  team vesting:", teamAllocation);
            console2.log("    start:", vestingStart);
            console2.log("    cliff:", vestingCliff);
            console2.log("    duration:", vestingDuration);
        }

        console2.log("Total supply after deployment:", token.totalSupply());

        vm.stopBroadcast();
        vm.stopBurn();
    }
}
