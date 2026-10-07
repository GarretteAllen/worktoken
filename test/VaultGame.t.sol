// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VaultX} from "../src/VaultX.sol";
import {VaultGame} from "../src/VaultGame.sol";

contract VaultGameTest is Test {
    VaultX public token;
    VaultGame public game;

    address public owner = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public carol = address(4);

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant SEASON_DRIP = 1_000_000 * 10 ** 18;
    uint256 public constant SEASON_PRIZE = 200_000 * 10 ** 18;
    uint256 public constant SEASON_DURATION = 30 days;

    event VaultCreated(address indexed player);
    event Banked(address indexed player, uint256 amount);
    event Upgraded(address indexed player, string upgradeType, uint256 newLevel, uint256 cost);
    event Raided(address indexed raider, address indexed victim, uint256 stolen, uint256 taxBurned);
    event Prestiged(address indexed player, uint256 newPrestigeLevel);
    event SeasonStarted(uint256 indexed seasonId, uint256 dripBudget, uint256 prizePool, uint256 endTime);

    function setUp() public {
        token = new VaultX(owner, MAX_SUPPLY);
        game = new VaultGame(owner, token);

        // Fund the game contract for seasons.
        vm.startPrank(owner);
        token.mint(address(game), SEASON_DRIP + SEASON_PRIZE);
        vm.stopPrank();
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    function _startSeason() internal {
        vm.prank(owner);
        game.startSeason(SEASON_DRIP, SEASON_PRIZE, SEASON_DURATION);
    }

    function _createVaultAndJoin(address player) internal {
        vm.startPrank(player);
        game.createVault();
        game.joinSeason();
        vm.stopPrank();
    }

    function _approveAndUpgrade(address player, string memory upgradeType, uint256 levels) internal {
        vm.startPrank(player);
        for (uint256 i = 0; i < levels; ++i) {
            uint256 currentLevel = _getLevel(player, upgradeType);
            uint256 cost = game.upgradeCost(currentLevel);
            token.approve(address(game), cost);
            if (keccak256(bytes(upgradeType)) == keccak256("production")) {
                game.upgradeProduction();
            } else if (keccak256(bytes(upgradeType)) == keccak256("defense")) {
                game.upgradeDefense();
            } else {
                game.upgradeOffense();
            }
        }
        vm.stopPrank();
    }

    function _getLevel(address player, string memory upgradeType)
        internal
        view
        returns (uint256)
    {
        (uint256 prod, uint256 def, uint256 off, , , , , , , , , , ) = game.vaults(player);
        if (keccak256(bytes(upgradeType)) == keccak256("production")) return prod;
        if (keccak256(bytes(upgradeType)) == keccak256("defense")) return def;
        return off;
    }

    // =====================================================================
    // Constructor & Config
    // =====================================================================

    function test_InitialState() public view {
        assertEq(address(game.vtx()), address(token));
        assertEq(game.owner(), owner);
        assertEq(game.currentSeasonId(), 0);
        assertEq(game.vaultCount(), 0);
    }

    function test_DefaultConfig() public view {
        VaultGame.Config memory c = game.getConfig();
        assertEq(c.baseRate, 1e15);
        assertEq(c.baseCost, 10e18);
        assertEq(c.prestigeBonusNum, 5);
        assertEq(c.prestigeBonusDen, 100);
        assertEq(c.prestigeMinLevel, 50);
        assertEq(c.raidBaseStealNum, 1000);
        assertEq(c.raidStealDen, 10000);
        assertEq(c.raidCooldown, 3600);
        assertEq(c.minRaidable, 100e18);
    }

    function test_SetConfig() public {
        VaultGame.Config memory newConfig = VaultGame.Config({
            baseRate: 2e15,
            baseCost: 20e18,
            prestigeBonusNum: 10,
            prestigeBonusDen: 100,
            prestigeMinLevel: 100,
            raidBaseStealNum: 1500,
            raidStealDen: 10000,
            raidOffenseBonusNum: 100,
            raidDefenseReduceNum: 50,
            raidMaxStealNum: 6000,
            raidMinStealNum: 200,
            raidTaxNum: 2500,
            raidTaxDen: 10000,
            raidCooldown: 7200,
            minRaidable: 200e18
        });

        vm.prank(owner);
        game.setConfig(newConfig);

        VaultGame.Config memory c = game.getConfig();
        assertEq(c.baseRate, 2e15);
        assertEq(c.baseCost, 20e18);
        assertEq(c.prestigeMinLevel, 100);
        assertEq(c.raidCooldown, 7200);
    }

    function test_SetConfigUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        game.setConfig(game.getConfig());
    }

    // =====================================================================
    // Vault Creation
    // =====================================================================

    function test_CreateVault() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit VaultCreated(alice);
        game.createVault();

        assertEq(game.vaultCount(), 1);
        assertEq(game.vaultOwners(0), alice);
    }

    function test_CreateVaultDuplicate() public {
        vm.startPrank(alice);
        game.createVault();
        vm.expectRevert(VaultGame.VaultAlreadyExists.selector);
        game.createVault();
        vm.stopPrank();
    }

    function test_BankWithoutVault() public {
        vm.prank(alice);
        vm.expectRevert(VaultGame.VaultNotFound.selector);
        game.bank();
    }

    // =====================================================================
    // Season Management
    // =====================================================================

    function test_StartSeason() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit SeasonStarted(1, SEASON_DRIP, SEASON_PRIZE, block.timestamp + SEASON_DURATION);
        game.startSeason(SEASON_DRIP, SEASON_PRIZE, SEASON_DURATION);

        assertEq(game.currentSeasonId(), 1);
        (uint256 start, uint256 end, uint256 drip, , uint256 prize, bool active, ) =
            game.seasons(1);
        assertEq(start, block.timestamp);
        assertEq(end, block.timestamp + SEASON_DURATION);
        assertEq(drip, SEASON_DRIP);
        assertEq(prize, SEASON_PRIZE);
        assertTrue(active);
    }

    function test_StartSeasonInsufficientFunding() public {
        vm.prank(owner);
        vm.expectRevert(VaultGame.InsufficientFunding.selector);
        game.startSeason(SEASON_DRIP * 100, SEASON_PRIZE, SEASON_DURATION);
    }

    function test_StartSeasonUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        game.startSeason(SEASON_DRIP, SEASON_PRIZE, SEASON_DURATION);
    }

    function test_JoinSeasonWithoutVault() public {
        _startSeason();
        vm.prank(alice);
        vm.expectRevert(VaultGame.VaultNotFound.selector);
        game.joinSeason();
    }

    function test_JoinSeasonNoActiveSeason() public {
        vm.prank(alice);
        game.createVault();
        vm.prank(alice);
        vm.expectRevert(VaultGame.NotInSeason.selector);
        game.joinSeason();
    }

    function test_JoinSeason() public {
        _startSeason();
        _createVaultAndJoin(alice);

        (, , , , , , uint256 seasonJoined, , , , , , ) = game.vaults(alice);
        assertEq(seasonJoined, 1);
    }

    function test_EndSeason() public {
        _startSeason();
        vm.prank(owner);
        game.endSeason();

        (, , , , , bool active, ) = game.seasons(1);
        assertFalse(active);
    }

    // =====================================================================
    // Banking
    // =====================================================================

    function test_Bank() public {
        _startSeason();
        _createVaultAndJoin(alice);

        // Warp 1 day.
        vm.warp(block.timestamp + 1 days);

        // Expected: 0.001 VTX/sec * 86400 sec = 86.4 VTX
        uint256 expected = 1e15 * 1 days;
        vm.prank(alice);
        game.bank();

        assertEq(token.balanceOf(alice), expected);
    }

    function test_BankNoTokensDue() public {
        _startSeason();
        _createVaultAndJoin(alice);

        // No time has passed.
        vm.prank(alice);
        vm.expectRevert(VaultGame.NoTokensDue.selector);
        game.bank();
    }

    function test_BankNotInSeason() public {
        vm.prank(alice);
        game.createVault();
        vm.prank(alice);
        vm.expectRevert(VaultGame.NotInSeason.selector);
        game.bank();
    }

    function test_BankUpdatesLastClaimTime() public {
        _startSeason();
        _createVaultAndJoin(alice);

        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        game.bank();

        (, , , , uint256 lastClaimTime, , , , , , , , ) = game.vaults(alice);
        assertEq(lastClaimTime, block.timestamp);
    }

    function test_BankAfterSeasonEnd() public {
        _startSeason();
        _createVaultAndJoin(alice);

        // Warp past season end.
        vm.warp(block.timestamp + SEASON_DURATION + 1 days);

        // Expected: production stops at season end.
        uint256 expected = 1e15 * SEASON_DURATION;
        vm.prank(alice);
        game.bank();

        assertEq(token.balanceOf(alice), expected);
    }

    function test_BankDripBudgetExhaustion() public {
        // Use a tiny drip budget.
        vm.prank(owner);
        token.mint(address(game), 1000e18); // extra funding

        vm.prank(owner);
        game.startSeason(1000e18, 0, SEASON_DURATION); // 1000 VTX drip, no prize

        _createVaultAndJoin(alice);

        // Warp enough to exceed 1000 VTX at 0.001 VTX/sec.
        // 1000e18 / 1e15 = 1,000,000 sec ≈ 11.5 days
        vm.warp(block.timestamp + 20 days);

        vm.prank(alice);
        game.bank();

        // Should get capped at 1000 VTX, not 0.001 * 20 days = 1728 VTX.
        assertEq(token.balanceOf(alice), 1000e18);
    }

    // =====================================================================
    // Upgrades
    // =====================================================================

    function test_UpgradeProduction() public {
        _startSeason();
        _createVaultAndJoin(alice);

        // Mint VTX to alice for upgrades.
        vm.prank(owner);
        token.mint(alice, 1000e18);

        uint256 cost = game.upgradeCost(0);
        assertEq(cost, 10e18); // baseCost * 1 * sqrt(1) = 10

        vm.startPrank(alice);
        token.approve(address(game), cost);
        game.upgradeProduction();
        vm.stopPrank();

        (uint256 prod, , , , , , , , uint256 totalBurned, , , , ) = game.vaults(alice);
        assertEq(prod, 1);
        assertEq(totalBurned, cost);

        // Check burn reduced supply.
        assertEq(token.totalSupply(), MAX_SUPPLY - cost);
    }

    function test_UpgradeProductionEmitsEvent() public {
        _startSeason();
        _createVaultAndJoin(alice);

        vm.prank(owner);
        token.mint(alice, 1000e18);

        uint256 cost = game.upgradeCost(0);

        vm.startPrank(alice);
        token.approve(address(game), cost);
        vm.expectEmit(true, false, false, true);
        emit Upgraded(alice, "production", 1, cost);
        game.upgradeProduction();
        vm.stopPrank();
    }

    function test_UpgradeDefense() public {
        _startSeason();
        _createVaultAndJoin(alice);

        vm.prank(owner);
        token.mint(alice, 1000e18);

        uint256 cost = game.upgradeCost(0);
        vm.startPrank(alice);
        token.approve(address(game), cost);
        game.upgradeDefense();
        vm.stopPrank();

        (, uint256 def, , , , , , , , , , , ) = game.vaults(alice);
        assertEq(def, 1);
    }

    function test_UpgradeOffense() public {
        _startSeason();
        _createVaultAndJoin(alice);

        vm.prank(owner);
        token.mint(alice, 1000e18);

        uint256 cost = game.upgradeCost(0);
        vm.startPrank(alice);
        token.approve(address(game), cost);
        game.upgradeOffense();
        vm.stopPrank();

        (, , uint256 off, , , , , , , , , , ) = game.vaults(alice);
        assertEq(off, 1);
    }

    function test_UpgradeCostIncreases() public {
        // Level 0: 10 * 1 * 1 = 10
        assertEq(game.upgradeCost(0), 10e18);
        // Level 1: 10 * 2 * sqrt(2) ≈ 10 * 2 * 1.414 = 28.28
        uint256 cost1 = game.upgradeCost(1);
        assertGt(cost1, 28e18);
        assertLt(cost1, 29e18);
        // Level 10: 10 * 11 * sqrt(11) ≈ 10 * 11 * 3.316 = 364.8
        uint256 cost10 = game.upgradeCost(10);
        assertGt(cost10, 360e18);
        assertLt(cost10, 370e18);
    }

    function test_UpgradeInsufficientAllowance() public {
        _startSeason();
        _createVaultAndJoin(alice);

        vm.prank(owner);
        token.mint(alice, 1000e18);

        // No approval.
        vm.prank(alice);
        vm.expectRevert();
        game.upgradeProduction();
    }

    function test_UpgradeBanksFirst() public {
        _startSeason();
        _createVaultAndJoin(alice);

        vm.prank(owner);
        token.mint(alice, 1000e18);

        // Warp to accumulate some production.
        vm.warp(block.timestamp + 1 days);
        uint256 expectedBank = 1e15 * 1 days;

        // Upgrade should auto-bank first.
        uint256 cost = game.upgradeCost(0);
        vm.startPrank(alice);
        token.approve(address(game), cost);
        game.upgradeProduction();
        vm.stopPrank();

        // Alice should have both banked production and the upgrade cost deducted.
        assertEq(token.balanceOf(alice), expectedBank - cost);
    }

    // =====================================================================
    // Production Rate
    // =====================================================================

    function test_ProductionRate() public {
        _startSeason();
        _createVaultAndJoin(alice);

        // Level 0, prestige 0: 0.001 VTX/sec
        assertEq(game.productionRate(alice), 1e15);

        // Upgrade to level 5.
        vm.prank(owner);
        token.mint(alice, 100000e18);
        _approveAndUpgrade(alice, "production", 5);

        // Level 5, prestige 0: 0.001 * 6 = 0.006 VTX/sec
        assertEq(game.productionRate(alice), 6e15);
    }

    function test_ProductionRateWithPrestige() public {
        _startSeason();
        _createVaultAndJoin(alice);

        // Upgrade to level 50 (min for prestige).
        vm.prank(owner);
        token.mint(alice, 10_000_000e18);
        _approveAndUpgrade(alice, "production", 50);

        // Prestige.
        vm.prank(alice);
        game.prestige();

        // Level 0, prestige 1: 0.001 * 1 * 1.05 = 0.00105 VTX/sec
        assertEq(game.productionRate(alice), 105e13);
    }

    // =====================================================================
    // Raids
    // =====================================================================

    function test_Raid() public {
        _startSeason();
        _createVaultAndJoin(alice);
        _createVaultAndJoin(bob);

        // Bob accumulates production.
        vm.warp(block.timestamp + 10 days);
        uint256 bobUnbanked = game.unbanked(bob);
        assertGt(bobUnbanked, game.getConfig().minRaidable);

        // Alice raids Bob.
        uint256 stealPct = game.raidStealPct(alice, bob);
        uint256 expectedSteal = (bobUnbanked * stealPct) / 10000;
        uint256 expectedTax = (expectedSteal * 2000) / 10000;
        uint256 expectedRaiderGets = expectedSteal - expectedTax;

        vm.prank(alice);
        game.raid(bob);

        assertEq(token.balanceOf(alice), expectedRaiderGets);
        // Bob's unbanked should be reset (0 after raid).
        assertEq(game.unbanked(bob), 0);
    }

    function test_RaidEmitsEvent() public {
        _startSeason();
        _createVaultAndJoin(alice);
        _createVaultAndJoin(bob);

        vm.warp(block.timestamp + 10 days);

        uint256 stealPct = game.raidStealPct(alice, bob);
        uint256 bobUnbanked = game.unbanked(bob);
        uint256 expectedSteal = (bobUnbanked * stealPct) / 10000;
        uint256 expectedTax = (expectedSteal * 2000) / 10000;
        uint256 expectedRaiderGets = expectedSteal - expectedTax;

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Raided(alice, bob, expectedRaiderGets, expectedTax);
        game.raid(bob);
    }

    function test_RaidCooldown() public {
        _startSeason();
        _createVaultAndJoin(alice);
        _createVaultAndJoin(bob);
        _createVaultAndJoin(carol);

        vm.warp(block.timestamp + 10 days);

        // First raid succeeds.
        vm.prank(alice);
        game.raid(bob);

        // Second raid within cooldown fails.
        vm.prank(alice);
        vm.expectRevert(VaultGame.RaidCooldown.selector);
        game.raid(carol);

        // After cooldown, raid succeeds.
        vm.warp(block.timestamp + 3601);
        vm.prank(alice);
        game.raid(carol);
    }

    function test_RaidSelf() public {
        _startSeason();
        _createVaultAndJoin(alice);

        vm.warp(block.timestamp + 10 days);

        vm.prank(alice);
        vm.expectRevert(VaultGame.CannotRaidSelf.selector);
        game.raid(alice);
    }

    function test_RaidTargetNotInSeason() public {
        _startSeason();
        _createVaultAndJoin(alice);

        // Bob creates vault but doesn't join season.
        vm.prank(bob);
        game.createVault();

        vm.warp(block.timestamp + 10 days);

        vm.prank(alice);
        vm.expectRevert(VaultGame.TargetNotInSeason.selector);
        game.raid(bob);
    }

    function test_RaidNotEnoughToRaid() public {
        _startSeason();
        _createVaultAndJoin(alice);
        _createVaultAndJoin(bob);

        // Only 1 second passes — Bob has ~0.001 VTX, way below minRaidable (100 VTX).
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        vm.expectRevert(VaultGame.NotEnoughToRaid.selector);
        game.raid(bob);
    }

    function test_RaidOffenseIncreasesSteal() public {
        _startSeason();
        _createVaultAndJoin(alice);
        _createVaultAndJoin(bob);

        // Give Alice offense upgrades.
        vm.prank(owner);
        token.mint(alice, 10000e18);
        _approveAndUpgrade(alice, "offense", 10);

        // Base steal = 10%, +10 * 0.5% = 15%
        uint256 stealPct = game.raidStealPct(alice, bob);
        assertEq(stealPct, 1500); // 15% in basis points
    }

    function test_RaidDefenseDecreasesSteal() public {
        _startSeason();
        _createVaultAndJoin(alice);
        _createVaultAndJoin(bob);

        // Give Bob defense upgrades.
        vm.prank(owner);
        token.mint(bob, 10000e18);
        _approveAndUpgrade(bob, "defense", 10);

        // Base steal = 10%, -10 * 0.3% = 7%
        uint256 stealPct = game.raidStealPct(alice, bob);
        assertEq(stealPct, 700); // 7% in basis points
    }

    function test_RaidStealClampedToMin() public {
        _startSeason();
        _createVaultAndJoin(alice);
        _createVaultAndJoin(bob);

        // Give Bob tons of defense.
        vm.prank(owner);
        token.mint(bob, 10_000_000e18);
        _approveAndUpgrade(bob, "defense", 100);

        // Base 10% - 100 * 0.3% = -20% → clamped to 1%
        uint256 stealPct = game.raidStealPct(alice, bob);
        assertEq(stealPct, 100); // 1% min
    }

    function test_RaidStealClampedToMax() public {
        _startSeason();
        _createVaultAndJoin(alice);
        _createVaultAndJoin(bob);

        // Give Alice tons of offense.
        vm.prank(owner);
        token.mint(alice, 10_000_000e18);
        _approveAndUpgrade(alice, "offense", 100);

        // Base 10% + 100 * 0.5% = 60% → clamped to 50%
        uint256 stealPct = game.raidStealPct(alice, bob);
        assertEq(stealPct, 5000); // 50% max
    }

    function test_RaidBurnsTax() public {
        _startSeason();
        _createVaultAndJoin(alice);
        _createVaultAndJoin(bob);

        vm.warp(block.timestamp + 10 days);

        uint256 supplyBefore = token.totalSupply();

        vm.prank(alice);
        game.raid(bob);

        // Tax should have been burned → total supply decreased.
        assertLt(token.totalSupply(), supplyBefore);
    }

    function test_RaidUpdatesStats() public {
        _startSeason();
        _createVaultAndJoin(alice);
        _createVaultAndJoin(bob);

        vm.warp(block.timestamp + 10 days);

        uint256 stealPct = game.raidStealPct(alice, bob);
        uint256 bobUnbanked = game.unbanked(bob);
        uint256 expectedSteal = (bobUnbanked * stealPct) / 10000;
        uint256 expectedRaiderGets = expectedSteal - (expectedSteal * 2000) / 10000;

        vm.prank(alice);
        game.raid(bob);

        (, , , , , , , , , , uint256 totalStolen, , uint256 seasonStolen) = game.vaults(alice);
        assertEq(totalStolen, expectedRaiderGets);
        assertEq(seasonStolen, expectedRaiderGets);
    }

    // =====================================================================
    // Prestige
    // =====================================================================

    function test_Prestige() public {
        _startSeason();
        _createVaultAndJoin(alice);

        // Upgrade to level 50.
        vm.prank(owner);
        token.mint(alice, 10_000_000e18);
        _approveAndUpgrade(alice, "production", 50);

        vm.prank(alice);
        game.prestige();

        (uint256 prod, uint256 def, uint256 off, uint256 prestige, , , , , , , , , ) =
            game.vaults(alice);
        assertEq(prod, 0);
        assertEq(def, 0);
        assertEq(off, 0);
        assertEq(prestige, 1);
    }

    function test_PrestigeEmitsEvent() public {
        _startSeason();
        _createVaultAndJoin(alice);

        vm.prank(owner);
        token.mint(alice, 10_000_000e18);
        _approveAndUpgrade(alice, "production", 50);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Prestiged(alice, 1);
        game.prestige();
    }

    function test_PrestigeLevelTooLow() public {
        _startSeason();
        _createVaultAndJoin(alice);

        vm.prank(owner);
        token.mint(alice, 1000e18);
        _approveAndUpgrade(alice, "production", 10);

        vm.prank(alice);
        vm.expectRevert(VaultGame.PrestigeLevelTooLow.selector);
        game.prestige();
    }

    function test_PrestigeIncreasesProductionRate() public {
        _startSeason();
        _createVaultAndJoin(alice);

        vm.prank(owner);
        token.mint(alice, 10_000_000e18);
        _approveAndUpgrade(alice, "production", 50);

        // Rate at level 50, prestige 0: 0.001 * 51 = 0.051
        assertEq(game.productionRate(alice), 51e15);

        vm.prank(alice);
        game.prestige();

        // Rate at level 0, prestige 1: 0.001 * 1 * 1.05 = 0.00105
        assertEq(game.productionRate(alice), 105e13);

        // Upgrade back to level 50.
        vm.prank(owner);
        token.mint(alice, 10_000_000e18);
        _approveAndUpgrade(alice, "production", 50);

        // Rate at level 50, prestige 1: 0.001 * 51 * 1.05 = 0.05355
        assertEq(game.productionRate(alice), 5355e13);
    }

    // =====================================================================
    // Prize Distribution
    // =====================================================================

    function test_DistributePrizes() public {
        _startSeason();
        _createVaultAndJoin(alice);
        _createVaultAndJoin(bob);

        // End season.
        vm.prank(owner);
        game.endSeason();

        address[] memory winners = new address[](2);
        winners[0] = alice;
        winners[1] = bob;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 150000e18;
        amounts[1] = 50000e18;

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);

        vm.prank(owner);
        game.distributePrizes(1, winners, amounts);

        assertEq(token.balanceOf(alice), aliceBefore + 150000e18);
        assertEq(token.balanceOf(bob), bobBefore + 50000e18);
    }

    function test_DistributePrizesSeasonStillActive() public {
        _startSeason();
        _createVaultAndJoin(alice);

        address[] memory winners = new address[](1);
        winners[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.prank(owner);
        vm.expectRevert(VaultGame.SeasonStillActive.selector);
        game.distributePrizes(1, winners, amounts);
    }

    function test_DistributePrizesAlreadyClaimed() public {
        _startSeason();
        _createVaultAndJoin(alice);

        vm.prank(owner);
        game.endSeason();

        address[] memory winners = new address[](1);
        winners[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.startPrank(owner);
        game.distributePrizes(1, winners, amounts);
        vm.expectRevert(VaultGame.PrizesAlreadyClaimed.selector);
        game.distributePrizes(1, winners, amounts);
        vm.stopPrank();
    }

    function test_DistributePrizesLengthMismatch() public {
        _startSeason();
        vm.prank(owner);
        game.endSeason();

        address[] memory winners = new address[](2);
        winners[0] = alice;
        winners[1] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.prank(owner);
        vm.expectRevert(VaultGame.LengthMismatch.selector);
        game.distributePrizes(1, winners, amounts);
    }

    // =====================================================================
    // Rescue Tokens
    // =====================================================================

    function test_RescueTokens() public {
        // Deploy a dummy token and send it to the game contract.
        VaultX dummy = new VaultX(address(this), MAX_SUPPLY);
        dummy.mint(address(game), 500e18);

        vm.prank(owner);
        game.rescueTokens(dummy, alice, 500e18);

        assertEq(dummy.balanceOf(alice), 500e18);
    }

    function test_RescueVtxBlocked() public {
        vm.prank(owner);
        vm.expectRevert(VaultGame.CannotRescueVtx.selector);
        game.rescueTokens(token, alice, 100e18);
    }

    // =====================================================================
    // Season Transitions
    // =====================================================================

    function test_JoinNewSeasonAutoBanks() public {
        _startSeason();
        _createVaultAndJoin(alice);

        vm.warp(block.timestamp + 5 days);
        uint256 expected = 1e15 * 5 days;

        // End season 1 and start season 2.
        vm.startPrank(owner);
        token.mint(address(game), SEASON_DRIP + SEASON_PRIZE);
        game.endSeason();
        game.startSeason(SEASON_DRIP, SEASON_PRIZE, SEASON_DURATION);
        vm.stopPrank();

        // Alice joins season 2 — should auto-bank from season 1.
        vm.prank(alice);
        game.joinSeason();

        assertEq(token.balanceOf(alice), expected);
    }

    function test_JoinNewSeasonResetsStats() public {
        _startSeason();
        _createVaultAndJoin(alice);

        // Upgrade to generate seasonBurned.
        vm.prank(owner);
        token.mint(alice, 1000e18);
        _approveAndUpgrade(alice, "production", 1);

        (, , , , , , , , , , , , uint256 seasonBurned1) = game.vaults(alice);
        assertGt(seasonBurned1, 0);

        // End season 1, start season 2.
        vm.startPrank(owner);
        token.mint(address(game), SEASON_DRIP + SEASON_PRIZE);
        game.endSeason();
        game.startSeason(SEASON_DRIP, SEASON_PRIZE, SEASON_DURATION);
        vm.stopPrank();

        vm.prank(alice);
        game.joinSeason();

        (, , , , , , , , , , , , uint256 seasonBurned2) = game.vaults(alice);
        assertEq(seasonBurned2, 0);
    }

    function test_StartNewSeasonEndsPrevious() public {
        _startSeason();
        _createVaultAndJoin(alice);

        vm.startPrank(owner);
        token.mint(address(game), SEASON_DRIP + SEASON_PRIZE);
        game.startSeason(SEASON_DRIP, SEASON_PRIZE, SEASON_DURATION);
        vm.stopPrank();

        // Season 1 should be ended.
        (, , , , , bool active1, ) = game.seasons(1);
        assertFalse(active1);

        // Season 2 should be active.
        (, , , , , bool active2, ) = game.seasons(2);
        assertTrue(active2);

        assertEq(game.currentSeasonId(), 2);
    }

    // =====================================================================
    // Fuzz Tests
    // =====================================================================

    function test_FuzzProductionRate(uint256 level, uint256 prestige) public {
        level = bound(level, 0, 1000);
        prestige = bound(prestige, 0, 100);

        // Manually compute expected rate.
        uint256 expected = (1e15 * (level + 1) * (100 + prestige * 5)) / 100;

        // We can't set vault levels directly, so test the formula via upgradeCost instead.
        // This test validates the cost formula at various levels.
        uint256 cost = game.upgradeCost(level);
        uint256 l = level + 1;
        uint256 sqrtL = _sqrt(l * 1e18) / 1e9;
        uint256 expectedCost = 10e18 * l * sqrtL;

        assertEq(cost, expectedCost);
    }

    function test_FuzzUpgradeCost(uint256 level) public {
        level = bound(level, 0, 10000);
        uint256 cost = game.upgradeCost(level);
        // Cost should always be >= baseCost (since level+1 >= 1 and sqrt(level+1) >= 1).
        assertGe(cost, 10e18);
    }

    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 r = 1;
        while (r * r <= x) {
            r++;
        }
        return r - 1;
    }
}
