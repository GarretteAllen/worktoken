# VaultX Idle — Game Design Spec

**Status:** Draft v1
**Token:** VaultX (VTX), deployed on Polygon Amoy (testnet)
**Genre:** Idle/incremental with PvP raid layer
**Codename:** `VaultX Idle` (internal: `vaultgame`)

---

## 1. Pitch

A persistent on-chain idle game where players run a "Vault" that drips VTX over
time. Players burn VTX to upgrade production, defense, and offense. Unbanked
production is raidable by other players, creating a tension between "let it
accumulate" and "bank now before someone steals it." Seasons reset leaderboards
and pay prizes to top producers, raiders, and burners. A prestige mechanic
creates a permanent progression loop.

**Why this game:**
- The VTX burn sink is **structural and infinite** — every upgrade is a burn.
  Players will burn VTX forever chasing higher numbers. This is the single most
  important property for token sustainability.
- Idle games are the most reliably addictive genre per dollar of dev spend
  (Cookie Clicker, Melvor Idle, Adventure Capitalist — tiny teams, massive
  playtime).
- The on-chain surface is small — mostly a single game contract with a few
  functions. No real-time engine, no 3D client, no physics. A dashboard with
  numbers and buttons is the entire UI.
- Polygon's low fees make per-action on-chain calls viable (bank, upgrade,
  raid are each one tx).

---

## 2. Core Loop

```
Create Vault (free, one per address)
        │
        ▼
  Vault drips VTX over time
  (unbanked production accumulates)
        │
        ├──► BANK: claim unbanked VTX to wallet (safe, free, resets timer)
        │         └── do this often to avoid being raided
        │
        ├──► UPGRADE: burn VTX to increase production / defense / offense
        │         └── production: more VTX/sec
        │         └── defense:    less raidable when attacked
        │         └── offense:    steal more when you raid
        │
        ├──► RAID: steal unbanked VTX from another player
        │         └── 80% to you, 20% burned (raid tax)
        │         └── cooldown between raids
        │
        └──► PRESTIGE: reset levels → gain permanent multiplier
                  └── the "new game+" loop
```

The player's constant tension: **"Do I bank now (safe but I have to come back
to accumulate again) or let it ride (more efficient but raidable)?"** This is
the engagement hook. Defense upgrades reduce the cost of letting it ride,
creating a natural upgrade path.

---

## 3. Entities

### 3.1 Vault (per-player, one per address)

| Field | Type | Description |
|-------|------|-------------|
| `owner` | address | Player's wallet |
| `productionLevel` | uint256 | Determines VTX/sec drip rate |
| `defenseLevel` | uint256 | Reduces raidable % when attacked |
| `offenseLevel` | uint256 | Increases steal % when raiding |
| `prestigeLevel` | uint256 | Permanent multiplier badge |
| `lastClaimTime` | uint256 | Timestamp of last `bank()` |
| `totalProduced` | uint256 | Lifetime production (leaderboard) |
| `totalBurned` | uint256 | Lifetime VTX burned via upgrades (leaderboard) |
| `totalStolen` | uint256 | Lifetime VTX stolen via raids (leaderboard) |
| `lastRaidTime` | uint256 | Timestamp of last raid (cooldown) |
| `seasonJoined` | uint256 | Current season ID (0 = not joined) |

### 3.2 Season (global)

| Field | Type | Description |
|-------|------|-------------|
| `seasonId` | uint256 | Incrementing counter |
| `startTime` | uint256 | When the season begins |
| `endTime` | uint256 | When the season ends |
| `dripBudget` | uint256 | Total VTX allocated for drip this season |
| `prizePool` | uint256 | Total VTX for end-of-season rewards |
| `drippedSoFar` | uint256 | Running total of VTX dripped |
| `active` | bool | Whether the season is live |

---

## 4. Math

### 4.1 Production Rate

```
rate(L, P) = BASE_RATE * (L + 1) * (1 + P * PRESTIGE_BONUS)
```

- `BASE_RATE` = 0.001 VTX/sec (≈ 86.4 VTX/day at level 0)
- `L` = productionLevel
- `P` = prestigeLevel
- `PRESTIGE_BONUS` = 0.05 (5% per prestige level)

| Level | Prestige 0 | Prestige 5 | Prestige 10 |
|-------|-----------|-----------|------------|
| 0 | 86 VTX/day | 302 VTX/day | 518 VTX/day |
| 10 | 950 VTX/day | 3,327 VTX/day | 5,703 VTX/day |
| 50 | 4,406 VTX/day | 15,423 VTX/day | 26,438 VTX/day |
| 100 | 8,727 VTX/day | 30,544 VTX/day | 52,362 VTX/day |

Growth is **linear in level**, not exponential. This prevents runaway production
that would drain the season budget in days.

### 4.2 Upgrade Costs

```
costProd(L)  = BASE_COST_PROD  * (L + 1)^COST_EXP
costDefense(L) = BASE_COST_DEF * (L + 1)^COST_EXP
costOffense(L) = BASE_COST_OFF * (L + 1)^COST_EXP
```

- `BASE_COST_PROD` = 10 VTX
- `BASE_COST_DEF` = 10 VTX
- `BASE_COST_OFF` = 10 VTX
- `COST_EXP` = 1.5 (polynomial growth — not exponential, but faster than linear)

| Level → | 0→1 | 10→11 | 50→51 | 100→101 |
|---------|-----|-------|-------|---------|
| Cost | 10 | 364 | 3,691 | 10,153 |

**Time to recoup** (at prestige 0, upgrading production from L to L+1):
```
recoup = costProd(L) / (BASE_RATE * (1 + P * PRESTIGE_BONUS))
```

| Level | Recoup time |
|-------|-------------|
| 0→1 | 10 / 0.001 = 10,000s ≈ 2.8 hours |
| 10→11 | 364 / 0.011 = 33,000s ≈ 9.2 hours |
| 50→51 | 3,691 / 0.051 = 72,400s ≈ 20 hours |
| 100→101 | 10,153 / 0.101 = 100,500s ≈ 28 hours |

Early upgrades pay back in hours. Late upgrades take a day+. This creates
natural diminishing returns without a hard wall — players always *can* upgrade,
but eventually it's not worth it without prestiging.

### 4.3 Unbanked Production

```
unbanked(player) = rate(productionLevel, prestigeLevel)
                   * (block.timestamp - lastClaimTime)
```

Capped by the season's remaining drip budget. If the season budget is
exhausted, `unbanked` returns 0 and production effectively stops until the
next season.

### 4.4 Raid Math

When player A raids player B:

```
U = unbanked(B)                          // victim's unbanked production
baseSteal = 10%                          // base steal percentage
offenseBonus = A.offenseLevel * 0.5%     // max +25% at level 50
defenseReduction = B.defenseLevel * 0.3% // max -15% at level 50
stealPct = clamp(baseSteal + offenseBonus - defenseReduction, 1%, 50%)
stolen = U * stealPct
raidTax = stolen * 20%                   // burned
raiderGets = stolen * 80%               // to attacker
victimLoses = stolen                     // from unbanked
```

**Raid cooldown:** `RAID_COOLDOWN = 1 hour` (fixed for MVP; could scale with
offense level in a later version).

**Raid constraints:**
- Target must be in the same season.
- Target must have `unbanked > MIN_RAIDABLE` (e.g., 100 VTX) — prevents
  raiding empty vaults.
- Attacker must have `block.timestamp - lastRaidTime >= RAID_COOLDOWN`.
- Cannot raid yourself.

### 4.5 Prestige

```
prestigeRequirement: productionLevel >= 50
prestigeCost: 0 (free — the cost is resetting your levels)
prestigeEffect: +5% production per prestige level, permanently
```

On prestige:
- `productionLevel` → 0
- `defenseLevel` → 0 (or keep? — see design note below)
- `offenseLevel` → 0 (or keep?)
- `prestigeLevel` += 1
- `totalProduced` and `totalBurned` carry over (for leaderboards)

**Design note:** Resetting defense/offense on prestige is debatable. If they
reset, prestiging is a bigger sacrifice (you're vulnerable again) which makes
it more meaningful. If they persist, prestige is a no-brainer (always prestige
ASAP). For MVP, **reset all three** — prestige should be a real choice, not a
freebie. The permanent 5% multiplier is the reward for the sacrifice.

---

## 5. Token Flow

### 5.1 Source (VTX entering the game)

| Source | Mechanism | Bounded? |
|--------|-----------|----------|
| Season drip budget | Pre-minted from rewards pool to game contract at season start | Yes — fixed per season |
| Season prize pool | Pre-minted from rewards pool to game contract at season start | Yes — fixed per season |

The game contract holds a VTX balance. Drip and prizes are paid from this
balance. When the balance is exhausted, production stops. The game admin
(MINTER_ROLE holder) tops up the contract at the start of each season.

**This is critical:** the game contract never mints VTX on its own. It only
distributes from a pre-funded balance. This makes the emission rate hard-capped
per season and fully transparent on-chain.

### 5.2 Sink (VTX burned)

| Sink | Mechanism | Infinite? |
|------|-----------|-----------|
| Production upgrades | `costProd(L)` burned per upgrade | Yes |
| Defense upgrades | `costDefense(L)` burned per upgrade | Yes |
| Offense upgrades | `costOffense(L)` burned per upgrade | Yes |
| Raid tax | 20% of every raid's stolen amount burned | Yes |
| Entry fee (optional) | Burned on season join | Yes |

All upgrade costs are **burned** (sent to `address(0)` via `burnFrom` or
`transfer(0x0, ...)`). They do not go to the treasury or admin. This is the
core deflationary mechanism.

### 5.3 Transfer (PvP, not a sink)

| Transfer | Mechanism |
|----------|-----------|
| Raid steal | 80% of stolen VTX → attacker's wallet |
| Season prizes | End-of-season payouts to top players |

### 5.4 Net Token Flow Per Season

```
netInflation = (dripBudget + prizePool) - (upgradesBurned + raidTaxBurned + entryFeesBurned)
```

- If `netInflation < 0`: deflationary season (burns exceed mints) — good for
  token price.
- If `netInflation > 0`: inflationary season — the rewards pool shrinks.

**Target:** tune constants so that `netInflation ≈ 0` or slightly negative.
The upgrade sink is player-driven (they burn to improve), so it scales with
engagement. If players are active, burns should roughly track the drip budget.

### 5.5 Season Budget Sizing

With 300M VTX in the rewards pool and a target game lifespan of ~3 years:

```
300M VTX / 36 seasons (3 years, 30-day seasons) ≈ 8.3M VTX/season
```

Split per season:
- Drip budget: 6M VTX (72%)
- Prize pool: 2M VTX (24%)
- Reserve/ops: 0.3M VTX (4%)

At 6M VTX/season drip and a 30-day season:
```
6M / 30 days = 200,000 VTX/day total across ALL players
```

With 1,000 active players, that's 200 VTX/day per player on average — enough
to feel meaningful, not enough to make everyone rich. Early players with high
levels will earn disproportionately more, which is the incentive to upgrade.

**These numbers are starting points.** They need simulation and playtesting.
The contract should make all constants configurable by the admin (game
operator) so they can be tuned without redeploying.

---

## 6. Season Mechanics

### 6.1 Season Lifecycle

```
[Season N ends]
      │
      ▼
[Prizes distributed to top players of Season N]
      │
      ▼
[Season N+1 starts]
      ├── admin funds game contract with dripBudget + prizePool
      ├── players join (pay entry fee if configured, or free)
      ├── leaderboards reset (totalProduced/totalStolen/totalBurned this season)
      └── vaults carry over (levels, prestige — no reset)
      │
      ▼
[Season N+1 runs for 30 days]
      ├── players bank, upgrade, raid, prestige
      └── drip budget depletes
      │
      ▼
[Season N+1 ends] → loop
```

### 6.2 Leaderboards & Prizes

Three leaderboards per season, each paying from the prize pool:

| Category | Metric | Prize share |
|----------|--------|-------------|
| Top Producers | `totalProduced` this season | 40% of prize pool |
| Top Raiders | `totalStolen` this season | 30% of prize pool |
| Top Burners | `totalBurned` this season | 30% of prize pool |

Payout structure (per category): top 10 split the category's pool, weighted
by their metric. E.g., if the producer pool is 800K VTX:
- #1 gets 800K * (theirProduced / sumOfTop10Produced)

This rewards all three playstyles: pure idlers (producers), aggressive PvP
(raiders), and token-burning whales (burners — who also drive the deflationary
sink).

### 6.3 Season-Scoped Stats

Each vault tracks season-scoped stats (reset each season) for leaderboard
purposes:
- `seasonProduced`
- `seasonStolen`
- `seasonBurned`

Lifetime stats (`totalProduced`, `totalBurned`, `totalStolen`) persist across
seasons for all-time leaderboards and prestige eligibility.

---

## 7. Contract Interface

### 7.1 `VaultGame.sol` (main game contract)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract VaultGame is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Structs ---
    struct Vault {
        uint256 productionLevel;
        uint256 defenseLevel;
        uint256 offenseLevel;
        uint256 prestigeLevel;
        uint256 lastClaimTime;
        uint256 lastRaidTime;
        uint256 seasonJoined;
        // Lifetime stats
        uint256 totalProduced;
        uint256 totalBurned;
        uint256 totalStolen;
        // Season-scoped stats
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

    // --- Config (settable by owner for tuning) ---
    uint256 public BASE_RATE;           // e.g., 1e15 (0.001 VTX/sec in wei)
    uint256 public BASE_COST;           // e.g., 10e18
    uint256 public COST_EXP_NUM;        // e.g., 15 (for 1.5)
    uint256 public COST_EXP_DEN;        // e.g., 10
    uint256 public PRESTIGE_BONUS_NUM;  // e.g., 5
    uint256 public PRESTIGE_BONUS_DEN;  // e.g., 100
    uint256 public PRESTIGE_MIN_LEVEL;  // e.g., 50
    uint256 public RAID_BASE_STEAL_NUM; // e.g., 10
    uint256 public RAID_BASE_STEAL_DEN; // e.g., 100
    uint256 public RAID_OFFENSE_BONUS_NUM;   // e.g., 5
    uint256 public RAID_OFFENSE_BONUS_DEN;   // e.g., 1000
    uint256 public RAID_DEFENSE_REDUCE_NUM;  // e.g., 3
    uint256 public RAID_DEFENSE_REDUCE_DEN;  // e.g., 1000
    uint256 public RAID_MAX_STEAL_NUM;  // e.g., 50
    uint256 public RAID_MAX_STEAL_DEN;  // e.g., 100
    uint256 public RAID_MIN_STEAL_NUM;  // e.g., 1
    uint256 public RAID_MIN_STEAL_DEN;  // e.g., 100
    uint256 public RAID_TAX_NUM;        // e.g., 20
    uint256 public RAID_TAX_DEN;        // e.g., 100
    uint256 public RAID_COOLDOWN;       // e.g., 3600
    uint256 public MIN_RAIDABLE;        // e.g., 100e18

    // --- State ---
    IERC20 public immutable vtx;
    uint256 public currentSeasonId;
    mapping(uint256 => Season) public seasons;
    mapping(address => Vault) public vaults;
    address[] public vaultOwners;

    // --- Events ---
    event VaultCreated(address indexed player);
    event Banked(address indexed player, uint256 amount);
    event Upgraded(address indexed player, string upgradeType, uint256 newLevel, uint256 cost);
    event Raided(address indexed raider, address indexed victim, uint256 stolen, uint256 taxBurned);
    event Prestiged(address indexed player, uint256 newPrestigeLevel);
    event SeasonStarted(uint256 indexed seasonId, uint256 dripBudget, uint256 prizePool);
    event SeasonEnded(uint256 indexed seasonId);
    event PrizesDistributed(uint256 indexed seasonId, uint256 totalPaid);

    // --- Errors ---
    error VaultAlreadyExists();
    error VaultNotFound();
    error NotInSeason();
    error SeasonNotActive();
    error DripBudgetExhausted();
    error InsufficientUnbanked();
    error RaidCooldown();
    error CannotRaidSelf();
    error TargetNotInSeason();
    error NotEnoughToRaid();
    error PrestigeLevelTooLow();
    error SeasonStillActive();
    error PrizesAlreadyClaimed();

    // --- Functions ---
    constructor(address _owner, IERC20 _vtx) Ownable2Step(_owner);

    // Admin
    function startSeason(uint256 dripBudget, uint256 prizePool, uint256 duration) external onlyOwner;
    function endSeason() external onlyOwner;
    function distributePrizes(uint256 seasonId) external onlyOwner;
    function setConfig(/* all config params */) external onlyOwner;
    function rescueTokens(IERC20 token, address to, uint256 amount) external onlyOwner;

    // Player
    function createVault() external;
    function joinSeason() external;
    function bank() external nonReentrant;
    function upgradeProduction() external nonReentrant;
    function upgradeDefense() external nonReentrant;
    function upgradeOffense() external nonReentrant;
    function raid(address target) external nonReentrant;
    function prestige() external nonReentrant;

    // View
    function unbanked(address player) external view returns (uint256);
    function productionRate(address player) external view returns (uint256);
    function upgradeCost(uint256 currentLevel) public view returns (uint256);
    function raidStealPct(address raider, address victim) external view returns (uint256);
}
```

### 7.2 Key Implementation Notes

**`bank()` — claim unbanked production:**
1. Compute `unbanked = rate * (now - lastClaimTime)`.
2. Cap by `season.dripBudget - season.drippedSoFar` (if budget exhausted,
   `unbanked = 0`).
3. Transfer `unbanked` VTX from game contract to player.
4. Update `season.drippedSoFar += unbanked`.
5. Update `vault.lastClaimTime = now`, `vault.totalProduced += unbanked`,
   `vault.seasonProduced += unbanked`.

**`upgradeProduction()` — burn VTX to level up:**
1. Compute `cost = upgradeCost(productionLevel)`.
2. `vtx.safeTransferFrom(player, address(0), cost)` — wait, can't transfer to
   zero address. Use `vtx.burnFrom(player, cost)` if VaultX exposes burnFrom,
   or `vtx.safeTransferFrom(player, address(this), cost)` then
   `vtx.burn(cost)`. **Simplest:** require player to approve game contract,
   then game contract calls `vtx.burnFrom(player, cost)`. VaultX inherits
   `ERC20Burnable` which has `burnFrom(amount)` with allowance check. ✓
3. `vault.productionLevel += 1`, `vault.totalBurned += cost`,
   `vault.seasonBurned += cost`.

**`raid(target)` — steal unbanked VTX:**
1. Check cooldown, self-raid, season membership, minimum raidable.
2. Compute `U = unbanked(target)`.
3. Compute `stealPct` from offense/defense levels.
4. `stolen = U * stealPct`, `tax = stolen * 20%`, `raiderGets = stolen - tax`.
5. Update target's `lastClaimTime` to now (their unbanked is now reduced by
   `stolen` — effectively, we "claim" `stolen` from their unbanked and
   redirect it).
6. Burn `tax` via `vtx.burn(tax)` (from game contract balance — the tax is
   taken from the drip budget that would have gone to the victim).
7. Transfer `raiderGets` to raider from game contract balance.
8. Update `season.drippedSoFar += stolen` (the stolen amount counts against
   the drip budget — it was "produced" and distributed, just to the raider
   instead of the victim).
9. Update stats: `vault.totalStolen += raiderGets`, `vault.seasonStolen +=
   raiderGets`, `vault.lastRaidTime = now`.

**Important subtlety in raid:** The "stolen" VTX comes from the game
contract's drip budget, not from the victim's wallet. The victim never
banked it, so it was never in their wallet — it was "owed" to them by the
drip mechanic. The raid redirects that owed production to the raider. This
means the victim's wallet balance is never at risk — only their unbanked
accumulation. This is safer and simpler than actually transferring from the
victim's wallet.

**`prestige()`:**
1. Require `productionLevel >= PRESTIGE_MIN_LEVEL`.
2. Reset `productionLevel`, `defenseLevel`, `offenseLevel` to 0.
3. `prestigeLevel += 1`.
4. `lastClaimTime = now` (no production change exploit).

---

## 8. Client / Frontend

The client is a single-page dashboard. No game engine, no 3D, no physics.

### 8.1 Screens

**Main Dashboard:**
- Big number: current unbanked production (live-updating via polling or
  block-based estimation)
- Big number: production rate (VTX/sec, VTX/day)
- Buttons: BANK, UPGRADE PRODUCTION (shows cost), UPGRADE DEFENSE, UPGRADE
  OFFENSE, PRESTIGE
- Stats panel: production level, defense level, offense level, prestige
  level, lifetime produced/burned/stolen
- Season panel: days remaining, drip budget remaining, your rank

**Raid Screen:**
- List of raidable targets (other players with unbanked > MIN_RAIDABLE)
- For each: their unbanked amount, your estimated steal %, estimated haul
- Button: RAID
- Cooldown indicator

**Leaderboard Screen:**
- Top producers, top raiders, top burners (season-scoped)
- Prize projections

### 8.2 Tech

- **wagmi + viem** for on-chain interaction (React).
- **Permit-based approvals** for upgrade costs (gasless approve via
  EIP-2616 — VaultX supports this). Player signs a permit, frontend submits
  it alongside the upgrade tx. One signature instead of approve + upgrade.
- **Polling or WebSocket** for unbanked production (it's a pure function of
  `block.timestamp - lastClaimTime`, so the client can compute it locally
  and update every second without RPC calls).
- **No backend server required.** All state is on-chain. A read-only indexer
  (The Graph subgraph) is optional for leaderboards and raid target
  discovery.

### 8.3 Onboarding

- Player connects wallet (MetaMask / WalletConnect / social login via
  Privy/Coinbase Wallet).
- `createVault()` — free, one tx.
- `joinSeason()` — free for first season (bootstrap), small burn fee later.
- Player now has a vault dripping VTX. They see the number go up
  immediately. First dopamine hit within 30 seconds of connecting.

---

## 9. Smart Contract Security Notes

These are design-phase security considerations, not a full audit (that comes
after implementation):

1. **`Ownable2Step`** for the game contract (not `Ownable`) — fixes audit
   finding M-3 pattern for the new contract.
2. **`ReentrancyGuard`** on all state-mutating player functions — `bank`,
   `upgrade*`, `raid`, `prestige`.
3. **CEI ordering** in `raid`: update all state (`lastClaimTime`,
   `drippedSoFar`, stats) before external `safeTransfer` to the raider.
4. **Drip budget cap** prevents runaway minting — the game contract can
   never distribute more VTX than it holds. Even if a bug inflates
   production rates, the contract balance is the hard limit.
5. **No `mintFrom`** — the game contract never mints VTX. It only
   distributes from a pre-funded balance. This means a game contract
   exploit can drain the season budget but cannot inflate the total supply.
6. **`burnFrom` allowance** — players must approve the game contract to
   burn their VTX for upgrades. Use `ERC20Burnable.burnFrom` which checks
   allowance. Consider using `permit` + `burnFrom` in a single tx for UX.
7. **`rescueTokens`** — admin can rescue stuck tokens, but should NOT be
   able to rescue VTX that's part of the active season budget (otherwise
   admin can rug the season). Implement as: can rescue any token EXCEPT
   VTX, OR can rescue VTX only when no season is active.
8. **Integer math** — all rates and costs use the numerator/denominator
   pattern (no fixed-point libraries needed). Multiplication before
   division to preserve precision.
9. **Pause interaction** — if VaultX is paused (PAUSER_ROLE), `bank` and
   `raid` will fail because they call `vtx.transfer`. This is actually
   desirable — a paused token should freeze the game too. Document this.
10. **Front-running raids** — raids are visible in the mempool. A
    target could front-run their own raid by calling `bank()` first. This
    is acceptable (it's the "bank to safety" mechanic working as intended)
    but means raiders should use flashbots/private mempool on mainnet. On
    Polygon this is less of a concern due to fast finality.

---

## 10. Roadmap

### Phase 1: MVP (target: 4-6 weeks)
- `VaultGame.sol` contract with all core functions
- Tests (Foundry) covering: create, bank, upgrade x3, raid, prestige, season
  start/end, prize distribution, edge cases (cooldown, self-raid, budget
  exhaustion)
- Deploy to Amoy testnet
- Basic frontend (dashboard + raid screen)
- First test season with fake VTX

### Phase 2: Polish (target: 4 weeks)
- Leaderboard frontend
- The Graph subgraph for indexing
- Permit-based upgrade UX (gasless approve)
- Season auto-start/end (or admin tooling)
- Balance tuning based on testnet play

### Phase 3: Mainnet prep (target: 2-4 weeks)
- Full audit of `VaultGame.sol`
- Fix VaultX audit findings (H-1, H-2, H-3, M-2, M-3, M-4) on the token
- Move admin to multisig
- Deploy VaultX to Polygon mainnet
- Deploy VaultGame to Polygon mainnet
- Launch season 1

### Phase 4: Expansion (ongoing)
- Vault NFTs (tradeable vaults with cosmetic skins)
- Multiple vault types (different production/defense/offense base stats)
- Guilds / alliances (group raids, shared defense)
- Quests (daily/weekly objectives that reward VTX from the prize pool)
- Battle pass (season pass with cosmetic + minor gameplay rewards)

---

## 11. Open Questions

1. **Should vaults be NFTs?** Pro: tradeable, portable, "yours." Con:
   complexity, and a whale could buy a maxed vault. Decision: **no for MVP**.
   Vaults are per-address. Add NFT vaults in Phase 4 as a premium feature.

2. **Should defense/offense reset on prestige?** Current design: yes, all
   three reset. This makes prestige a real sacrifice. Revisit after
   playtesting — if it feels too punishing, keep defense/offense.

3. **Entry fee for seasons?** Current design: free for season 1 (bootstrap),
   small burn fee after. The fee is another burn sink but could deter new
   players. Decision: **free for first 3 seasons, then 100 VTX burn**.

4. **How to handle the "whale problem"?** A player who buys a lot of VTX on
   the market and burns it on upgrades will dominate production. This is
   actually fine — they're burning VTX (deflationary) and their dominance is
   limited by linear production growth and diminishing returns. The prestige
   system means a dedicated small player can eventually catch up via
   multipliers. Monitor and tune.

5. **Off-chain vs on-chain leaderboards?** On-chain is trustless but
   expensive to query (iterate all vaults). A subgraph is the standard
   solution. For MVP, compute leaderboards off-chain by reading all vaults
   via multicall. Switch to subgraph in Phase 2.

6. **What happens if the admin disappears?** The game contract holds VTX. If
   no one starts a new season, production stops and prizes are stranded.
   Mitigation: in Phase 2, add a "community-started season" mechanism where
   anyone can fund and start a season if the admin has been inactive for X
   days. Or: use a timelock-controlled admin.
