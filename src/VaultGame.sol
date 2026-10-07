// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @dev Minimal interface for burn/burnFrom (VaultX inherits ERC20Burnable).
interface IBurnableERC20 {
    function burn(uint256 value) external;
    function burnFrom(address account, uint256 value) external;
}

/**
 * @title VaultGame
 * @notice On-chain idle/incremental game with PvP raids, powered by VTX.
 * @dev Players run a Vault that drips VTX over time. They burn VTX to upgrade
 *      production, defense, and offense. Unbanked production is raidable.
 *      Seasons reset leaderboards and pay prizes to top players.
 */

interface IERC20(default);

contract VaultGame is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =====================================================================
    // Structs
    // =====================================================================

    struct Vault {
        uint256 productionLevel;
        uint256 defenseLevel;
        uint256 offenseLevel;
        uint256 prestigeLevel;
        uint256 lastClaimTime;
        uint256 lastRaidTime;
        uint256 seasonJoined;
        uint256 totalProduced;
        uint256 totalBurned;
        uint256 totalStolen;
        uint256 seasonProduced;
        uint256 seasonStolen;
        uint256 seasonBurned;
    }

    struct Season {
        uint256 startTime;
        uint256 endTime;
        uint256 dripBudget;
        uint256 drippedSoFar;
        uint256 prizePool;
        bool active;
        bool prizesClaimed;
    }

    struct Config {
        uint256 baseRate; // VTX/sec at level 0, prestige 0 (in wei)
        uint256 baseCost; // base upgrade cost (in wei)
        uint256 prestigeBonusNum; // prestige multiplier numerator
        uint256 prestigeBonusDen; // prestige multiplier denominator
        uint256 prestigeMinLevel; // min production level to prestige
        uint256 raidBaseStealNum; // base steal % numerator (basis points)
        uint256 raidStealDen; // steal denominator (10000 = basis points)
        uint256 raidOffenseBonusNum; // per-level offense bonus (bps)
        uint256 raidDefenseReduceNum; // per-level defense reduction (bps)
        uint256 raidMaxStealNum; // max steal % (bps)
        uint256 raidMinStealNum; // min steal % (bps)
        uint256 raidTaxNum; // raid tax % numerator
        uint256 raidTaxDen; // raid tax % denominator
        uint256 raidCooldown; // seconds between raids
        uint256 minRaidable; // min unbanked VTX to be raidable (wei)
    }

    // =====================================================================
    // State
    // =====================================================================

    IERC20 public immutable vtx;
    uint256 public currentSeasonId;
    mapping(uint256 => Season) public seasons;
    mapping(address => Vault) public vaults;
    address[] public vaultOwners;

    Config public config;

    // Cost exponent is 1.5. We compute (level+1)^1.5 = (level+1) * sqrt(level+1).
    // Precision scaling: multiply before divide to avoid truncation.
    // cost = baseCost * (level+1) * sqrt((level+1) * 1e36) / 1e18
    uint256 private constant COST_PRECISION = 1e36;
    uint256 private constant COST_PRECISION_SQRT = 1e18;

    // =====================================================================
    // Events
    // =====================================================================

    event VaultCreated(address indexed player);
    event Banked(address indexed player, uint256 amount);
    event Upgraded(address indexed player, string upgradeType, uint256 newLevel, uint256 cost);
    event Raided(address indexed raider, address indexed victim, uint256 stolen, uint256 taxBurned);
    event Prestiged(address indexed player, uint256 newPrestigeLevel);
    event SeasonStarted(uint256 indexed seasonId, uint256 dripBudget, uint256 prizePool, uint256 endTime);
    event SeasonEnded(uint256 indexed seasonId);
    event PrizesDistributed(uint256 indexed seasonId, address[] winners, uint256[] amounts);
    event ConfigUpdated();

    // =====================================================================
    // Errors
    // =====================================================================

    error VaultAlreadyExists();
    error VaultNotFound();
    error NotInSeason();
    error SeasonNotActive();
    error SeasonStillActive();
    error NoTokensDue();
    error DripBudgetExhausted();
    error RaidCooldown();
    error CannotRaidSelf();
    error TargetNotInSeason();
    error NotEnoughToRaid();
    error PrestigeLevelTooLow();
    error PrizesAlreadyClaimed();
    error InsufficientFunding();
    error LengthMismatch();
    error CannotRescueVtx();
    error NoVaultsToPrize();
    error ZeroAmount();

    // =====================================================================
    // Constructor
    // =====================================================================

    constructor(address _owner, IERC20 _vtx) Ownable(_owner) {
        config = Config({
            baseRate: 1e15, // 0.001 VTX/sec
            baseCost: 10e18, // 10 VTX
            prestigeBonusNum: 5, // 5%
            prestigeBonusDen: 100,
            prestigeMinLevel: 50,
            raidBaseStealNum: 1000, // 10%
            raidStealDen: 10000,
            raidOffenseBonusNum: 50, // 0.5% per level
            raidDefenseReduceNum: 30, // 0.3% per level
            raidMaxStealNum: 5000, // 50%
            raidMinStealNum: 100, // 1%
            raidTaxNum: 2000, // 20%
            raidTaxDen: 10000,
            raidCooldown: 3600, // 1 hour
            minRaidable: 100e18 // 100 VTX
        });
        vtx = _vtx;
    }

    // =====================================================================
    // Admin Functions
    // =====================================================================

    /**
     * @notice Start a new season. Game contract must be pre-funded with
     *         dripBudget + prizePool VTX.
     * @param dripBudget  Total VTX available for drip this season.
     * @param prizePool   Total VTX for end-of-season prizes.
     * @param duration    Season duration in seconds.
     */
    function startSeason(uint256 dripBudget, uint256 prizePool, uint256 duration) external onlyOwner {
        if (dripBudget == 0) revert ZeroAmount();
        if (duration == 0) revert ZeroAmount();
        if (vtx.balanceOf(address(this)) < dripBudget + prizePool) revert InsufficientFunding();

        // End previous season if still active.
        if (currentSeasonId > 0 && seasons[currentSeasonId].active) {
            seasons[currentSeasonId].active = false;
            emit SeasonEnded(currentSeasonId);
        }

        currentSeasonId++;
        seasons[currentSeasonId] = Season({
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            dripBudget: dripBudget,
            drippedSoFar: 0,
            prizePool: prizePool,
            active: true,
            prizesClaimed: false
        });

        emit SeasonStarted(currentSeasonId, dripBudget, prizePool, block.timestamp + duration);
    }

    /**
     * @notice End the current season manually.
     */
    function endSeason() external onlyOwner {
        Season storage season = seasons[currentSeasonId];
        if (!season.active) revert SeasonNotActive();

        season.active = false;
        emit SeasonEnded(currentSeasonId);
    }

    /**
     * @notice Distribute prizes for a ended season. Winners and amounts are
     *         computed off-chain from on-chain data (verifiable by anyone).
     * @param seasonId  The season to distribute prizes for.
     * @param winners   Array of winner addresses.
     * @param amounts   Array of prize amounts, parallel to winners.
     */
    function distributePrizes(uint256 seasonId, address[] calldata winners, uint256[] calldata amounts)
        external
        onlyOwner
        nonReentrant
    {
        Season storage season = seasons[seasonId];
        if (season.startTime == 0) revert NotInSeason();
        if (season.active) revert SeasonStillActive();
        if (season.prizesClaimed) revert PrizesAlreadyClaimed();
        if (winners.length != amounts.length) revert LengthMismatch();
        if (winners.length == 0) revert NoVaultsToPrize();

        season.prizesClaimed = true;

        uint256 totalPaid = 0;
        for (uint256 i = 0; i < winners.length; ++i) {
            if (amounts[i] == 0) revert ZeroAmount();
            totalPaid += amounts[i];
            vtx.safeTransfer(winners[i], amounts[i]);
        }

        emit PrizesDistributed(seasonId, winners, amounts);
    }

    /**
     * @notice Update game configuration. Owner only.
     */
    function setConfig(Config calldata newConfig) external onlyOwner {
        config = newConfig;
        emit ConfigUpdated();
    }

    /**
     * @notice Rescue stuck non-VTX tokens. VTX cannot be rescued (it is
     *         always allocated to seasons or unbanked production).
     */
    function rescueTokens(IERC20 token, address to, uint256 amount) external onlyOwner {
        if (address(token) == address(vtx)) revert CannotRescueVtx();
        token.safeTransfer(to, amount);
    }

    // =====================================================================
    // Player Functions
    // =====================================================================

    /**
     * @notice Create a new vault. One per address. Free.
     */
    function createVault() external {
        if (vaults[msg.sender].lastClaimTime != 0) revert VaultAlreadyExists();

        vaults[msg.sender] = Vault({
            productionLevel: 0,
            defenseLevel: 0,
            offenseLevel: 0,
            prestigeLevel: 0,
            lastClaimTime: 1, // sentinel: vault exists (0 means "not created")
            lastRaidTime: 0,
            seasonJoined: 0,
            totalProduced: 0,
            totalBurned: 0,
            totalStolen: 0,
            seasonProduced: 0,
            seasonStolen: 0,
            seasonBurned: 0
        });
        vaultOwners.push(msg.sender);

        emit VaultCreated(msg.sender);
    }

    /**
     * @notice Join the current season. Auto-banks any unbanked production
     *         from a previous season first.
     */
    function joinSeason() external nonReentrant {
        Vault storage vault = vaults[msg.sender];
        if (vault.lastClaimTime == 0) revert VaultNotFound();
        if (currentSeasonId == 0) revert NotInSeason();
        Season storage season = seasons[currentSeasonId];
        if (!season.active) revert SeasonNotActive();

        // Auto-bank from previous season if applicable.
        if (vault.seasonJoined != 0 && vault.seasonJoined != currentSeasonId) {
            _bankInternal(vault);
        }

        // Reset season-scoped stats.
        vault.seasonProduced = 0;
        vault.seasonStolen = 0;
        vault.seasonBurned = 0;
        vault.seasonJoined = currentSeasonId;
        vault.lastClaimTime = block.timestamp;
    }

    /**
     * @notice Claim unbanked production to your wallet.
     */
    function bank() external nonReentrant {
        Vault storage vault = vaults[msg.sender];
        if (vault.lastClaimTime == 0) revert VaultNotFound();
        if (vault.seasonJoined == 0) revert NotInSeason();

        _bankInternal(vault);
    }

    /**
     * @notice Burn VTX to increase production level.
     */
    function upgradeProduction() external nonReentrant {
        Vault storage vault = vaults[msg.sender];
        if (vault.lastClaimTime == 0) revert VaultNotFound();

        // Bank first so unbanked production is not affected by the rate change.
        if (vault.seasonJoined != 0) {
            _bankInternal(vault);
        }

        uint256 cost = _upgradeCost(vault.productionLevel);
        IBurnableERC20(address(vtx)).burnFrom(msg.sender, cost);

        vault.productionLevel += 1;
        vault.totalBurned += cost;
        vault.seasonBurned += cost;

        emit Upgraded(msg.sender, "production", vault.productionLevel, cost);
    }

    /**
     * @notice Burn VTX to increase defense level (reduces raidable %).
     */
    function upgradeDefense() external nonReentrant {
        Vault storage vault = vaults[msg.sender];
        if (vault.lastClaimTime == 0) revert VaultNotFound();

        if (vault.seasonJoined != 0) {
            _bankInternal(vault);
        }

        uint256 cost = _upgradeCost(vault.defenseLevel);
        IBurnableERC20(address(vtx)).burnFrom(msg.sender, cost);

        vault.defenseLevel += 1;
        vault.totalBurned += cost;
        vault.seasonBurned += cost;

        emit Upgraded(msg.sender, "defense", vault.defenseLevel, cost);
    }

    /**
     * @notice Burn VTX to increase offense level (increases steal %).
     */
    function upgradeOffense() external nonReentrant {
        Vault storage vault = vaults[msg.sender];
        if (vault.lastClaimTime == 0) revert VaultNotFound();

        if (vault.seasonJoined != 0) {
            _bankInternal(vault);
        }

        uint256 cost = _upgradeCost(vault.offenseLevel);
        IBurnableERC20(address(vtx)).burnFrom(msg.sender, cost);

        vault.offenseLevel += 1;
        vault.totalBurned += cost;
        vault.seasonBurned += cost;

        emit Upgraded(msg.sender, "offense", vault.offenseLevel, cost);
    }

    /**
     * @notice Raid another player's vault, stealing a portion of their
     *         unbanked production. 80% goes to you, 20% is burned as tax.
     * @param target The address of the vault to raid.
     */
    function raid(address target) external nonReentrant {
        Vault storage raider = vaults[msg.sender];
        if (raider.lastClaimTime == 0) revert VaultNotFound();
        if (target == msg.sender) revert CannotRaidSelf();
        if (currentSeasonId == 0) revert NotInSeason();
        Season storage season = seasons[currentSeasonId];
        if (!season.active) revert SeasonNotActive();
        if (raider.seasonJoined != currentSeasonId) revert NotInSeason();

        Vault storage victim = vaults[target];
        if (victim.lastClaimTime == 0) revert VaultNotFound();
        if (victim.seasonJoined != currentSeasonId) revert TargetNotInSeason();

        // Check raid cooldown.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp - raider.lastRaidTime < config.raidCooldown) revert RaidCooldown();

        // Compute victim's unbanked production.
        uint256 victimUnbanked = _unbanked(victim, seasons[victim.seasonJoined]);
        if (victimUnbanked < config.minRaidable) revert NotEnoughToRaid();

        // Compute steal percentage.
        uint256 stealPct = _raidStealPct(raider.offenseLevel, victim.defenseLevel);

        uint256 stolen = (victimUnbanked * stealPct) / config.raidStealDen;
        if (stolen == 0) revert NotEnoughToRaid();

        uint256 tax = (stolen * config.raidTaxNum) / config.raidTaxDen;
        uint256 raiderGets = stolen - tax;

        // Update victim: "claim" the stolen amount from their unbanked.
        // This advances their lastClaimTime, reducing unbanked by the full
        // stolen amount (tax + raider share).
        victim.lastClaimTime = _min(block.timestamp, seasons[victim.seasonJoined].endTime);
        seasons[victim.seasonJoined].drippedSoFar += stolen;

        // Burn the tax from the game contract's VTX balance.
        IBurnableERC20(address(vtx)).burn(tax);

        // Transfer the raider's share from the game contract.
        vtx.safeTransfer(msg.sender, raiderGets);

        // Update raider stats.
        raider.lastRaidTime = block.timestamp;
        raider.totalStolen += raiderGets;
        raider.seasonStolen += raiderGets;

        emit Raided(msg.sender, target, raiderGets, tax);
    }

    /**
     * @notice Prestige your vault: reset all levels for a permanent
     *         production multiplier. Requires productionLevel >= min.
     */
    function prestige() external nonReentrant {
        Vault storage vault = vaults[msg.sender];
        if (vault.lastClaimTime == 0) revert VaultNotFound();
        if (vault.productionLevel < config.prestigeMinLevel) revert PrestigeLevelTooLow();

        // Bank first so no production is lost.
        if (vault.seasonJoined != 0) {
            _bankInternal(vault);
        }

        vault.productionLevel = 0;
        vault.defenseLevel = 0;
        vault.offenseLevel = 0;
        vault.prestigeLevel += 1;

        emit Prestiged(msg.sender, vault.prestigeLevel);
    }

    // =====================================================================
    // View Functions
    // =====================================================================

    /**
     * @notice Get the current unbanked production for a player.
     */
    function unbanked(address player) external view returns (uint256) {
        Vault storage vault = vaults[player];
        if (vault.lastClaimTime == 0 || vault.seasonJoined == 0) return 0;
        return _unbanked(vault, seasons[vault.seasonJoined]);
    }

    /**
     * @notice Get the current production rate (VTX/sec) for a player.
     */
    function productionRate(address player) external view returns (uint256) {
        Vault storage vault = vaults[player];
        if (vault.lastClaimTime == 0) return 0;
        return _productionRate(vault);
    }

    /**
     * @notice Get the upgrade cost for a given level.
     */
    function upgradeCost(uint256 currentLevel) external view returns (uint256) {
        return _upgradeCost(currentLevel);
    }

    /**
     * @notice Get the raid steal percentage (in basis points) for a raider
     *         attacking a victim.
     */
    function raidStealPct(address raiderAddr, address victimAddr) external view returns (uint256) {
        Vault storage r = vaults[raiderAddr];
        Vault storage v = vaults[victimAddr];
        return _raidStealPct(r.offenseLevel, v.defenseLevel);
    }

    /**
     * @notice Get the total number of vaults.
     */
    function vaultCount() external view returns (uint256) {
        return vaultOwners.length;
    }

    /**
     * @notice Get the full config struct (the auto-getter returns a tuple).
     */
    function getConfig() external view returns (Config memory) {
        return config;
    }

    /**
     * @notice Get a vault's full data by index (for off-chain leaderboard
     *         iteration via multicall).
     */
    function getVaultByIndex(uint256 index) external view returns (address owner, Vault memory vault) {
        owner = vaultOwners[index];
        vault = vaults[owner];
    }

    // =====================================================================
    // Internal Functions
    // =====================================================================

    function _productionRate(Vault storage vault) internal view returns (uint256) {
        Config storage c = config;
        uint256 prestigeMult = c.prestigeBonusDen + (vault.prestigeLevel * c.prestigeBonusNum) / c.prestigeBonusDen;
        // rate = baseRate * (level + 1) * prestigeMult / prestigeBonusDen
        // To avoid precision loss: multiply baseRate * (level+1) first, then scale.
        return (c.baseRate * (vault.productionLevel + 1) * prestigeMult) / c.prestigeBonusDen;
    }

    function _upgradeCost(uint256 currentLevel) internal view returns (uint256) {
        // cost = baseCost * (level + 1)^1.5
        //      = baseCost * (level + 1) * sqrt(level + 1)
        // Using precision scaling: sqrt((level+1) * 1e18) / 1e9
        uint256 l = currentLevel + 1;
        uint256 sqrtL = Math.sqrt(l * COST_PRECISION) / COST_PRECISION_SQRT;
        return config.baseCost * l * sqrtL;
    }

    function _unbanked(Vault storage vault, Season storage season) internal view returns (uint256) {
        uint256 endTime = _min(block.timestamp, season.endTime);
        if (endTime <= vault.lastClaimTime) return 0;

        uint256 elapsed = endTime - vault.lastClaimTime;
        uint256 produced = _productionRate(vault) * elapsed;

        // Cap by remaining drip budget.
        uint256 remaining = season.dripBudget - season.drippedSoFar;
        if (produced > remaining) return remaining;
        return produced;
    }

    function _raidStealPct(uint256 offenseLevel, uint256 defenseLevel) internal view returns (uint256) {
        Config storage c = config;
        // stealPct = base + offense*bonus - defense*reduce, clamped to [min, max]
        // Casting to int256 is safe: all values are small basis-point terms.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 pct = int256(c.raidBaseStealNum)
            // forge-lint: disable-next-line(unsafe-typecast)
            + int256(offenseLevel * c.raidOffenseBonusNum)
            // forge-lint: disable-next-line(unsafe-typecast)
            - int256(defenseLevel * c.raidDefenseReduceNum);

        // forge-lint: disable-next-line(unsafe-typecast)
        if (pct < int256(uint256(c.raidMinStealNum))) return c.raidMinStealNum;
        // forge-lint: disable-next-line(unsafe-typecast)
        if (pct > int256(uint256(c.raidMaxStealNum))) return c.raidMaxStealNum;
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(pct);
    }

    function _bankInternal(Vault storage vault) internal {
        Season storage season = seasons[vault.seasonJoined];
        if (season.startTime == 0) revert NotInSeason();

        uint256 amount = _unbanked(vault, season);
        if (amount == 0) revert NoTokensDue();

        vault.lastClaimTime = _min(block.timestamp, season.endTime);
        season.drippedSoFar += amount;
        vault.totalProduced += amount;
        vault.seasonProduced += amount;

        vtx.safeTransfer(msg.sender, amount);
        emit Banked(msg.sender, amount);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
