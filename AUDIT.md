# VaultX (VTX) — Security Audit Report

**Date:** 2026-07-06
**Auditor:** Devin (automated, model-assisted)
**Scope:** `src/VaultX.sol`, `src/TokenVesting.sol`, `script/DeployVaultX.s.sol`
**Target chain:** Polygon Amoy (testnet), with Polygon mainnet intent
**Compiler:** Solidity 0.8.20, optimizer 200 runs
**OpenZeppelin:** v5.2.0 (current, audited upstream)
**Deployed addresses:** see `DEPLOYMENTS.md`

## Executive Summary

The code is competently written, leans almost entirely on audited OpenZeppelin v5.2.0
primitives, and the test suite (33 tests, all passing) covers the happy paths and the
obvious revert paths. There are **no classic smart-contract vulnerabilities** (no
reentrancy-on-state, no overflow, no unchecked-return, no front-runnable mint-to-zero).
The arithmetic is sound, the checks-effects-interactions ordering in `revoke` is
correct, and the `_update` override properly funnels every transfer (including mint
and burn) through the pause gate.

The real risk surface is **centralization and operational hygiene**, not logic bugs.
The deployed token gives a single EOA god-mode over 30% of the unminted supply plus a
global transfer freeze, and the team vesting is revocable by that same EOA. For a
mainnet launch this needs to be addressed before it is fair to call the token "secure."

| Severity | Count |
|----------|-------|
| High | 3 |
| Medium | 5 |
| Low / Informational | 9 |

---

## High Severity

### H-1 — Single EOA holds DEFAULT_ADMIN + MINTER + PAUSER on a live token
`VaultX` constructor grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, and `PAUSER_ROLE`
all to one `admin` (`src/VaultX.sol:34-36`). Per `DEPLOYMENTS.md`, that admin is an
EOA (`0xB7DA…554e`), not a multisig or timelock.

Consequences of a single compromised admin key:
- Mint up to **300M VTX** (the remaining 30% of `maxSupply` after the 700M initial
  allocation) to any address, in a single tx, no delay.
- Pause all transfers globally, locking every holder's balance.
- Grant MINTER/PAUSER to any new address (e.g., an attacker-controlled one) instantly,
  then renounce — making the compromise permanent.

This is the single largest risk in the system. **Recommendations:**
- Move `DEFAULT_ADMIN_ROLE` behind a timelock (e.g., OpenZeppelin
  `TimelockController`) and/or a multisig (e.g., Safe). Minimum 2-of-3 or 3-of-5.
- Separate the three roles onto different accounts/contracts so compromise of one
  does not yield all powers.
- Consider `AccessControlDefaultAdminRules` for a 2-step, delayed admin transfer
  (prevents the "fat-finger loses admin forever" and "key compromise → instant new
  admin" failures).

### H-2 — Team vesting is `revocable=true` with the same admin as owner
In `script/DeployVaultX.s.sol:62-64` the team schedule is created with
`revocable: true`, and `TokenVesting` is constructed with `owner = admin`
(`script/DeployVaultX.s.sol:42`). The owner can call `revoke()` at any time and
refund themselves the entire unvested portion (`src/TokenVesting.sol:124-137`).

For the team allocation this means the vesting is **not actually locked** — the same
EOA that holds god-mode on the token can claw back the team's unvested 100M VTX at
will. If that key is compromised, the attacker can revoke and steal the unvested team
tokens.

**Recommendations:**
- Make the team schedule `revocable: false` (the team accepted the vesting; lock it).
- Or set the `TokenVesting` owner to a separate, more conservative multisig/timelock
  than the token admin.
- At minimum, document explicitly that team tokens are admin-revocable.

### H-3 — Contracts are not source-verified on Polygonscan
`DEPLOYMENTS.md` states verification failed due to the Etherscan V1 deprecation. Until
the bytecode is publicly verified, users and integrators cannot confirm the on-chain
contract matches the source you audited. This is a trust prerequisite for any real
deployment, and it is trivial for a malicious deployer to ship a different bytecode
than the repo source.

**Recommendation:** Re-verify via a V2-compatible verifier (Sourcify, Blockscout, or
the updated Foundry etherscan plugin). Do not advertise the token until verified.

---

## Medium Severity

### M-1 — `mintBatch` has unbounded loop (gas-limit DoS)
`mintBatch` (`src/VaultX.sol:60-68`) iterates `length` times with no upper bound. A
sufficiently large array will exceed the block gas limit and revert. Because each
iteration also re-runs the full `mint` checks (zero-address, zero-amount, maxSupply),
gas per element is non-trivial.

This is a self-DoS only (the caller pays the gas and reverts), but it can be
weaponized if `mintBatch` is ever callable via a router/automation that accepts
externally-supplied arrays. **Recommendation:** add a `require(length <= MAX_BATCH)`
constant (e.g., 200) and document it.

### M-2 — Pause blocks minting and burning (likely unintended)
The `_update` override (`src/VaultX.sol:84-86`) routes every `_update` — including
`_mint` (`_update(address(0), to, ...)`) and `_burn` (`_update(from, address(0),
...)`) — through `ERC20Pausable._update`, which enforces `whenNotPaused`.

So when `pause()` is called:
- All transfers halt (intended).
- **All minting halts** — rewards/emissions/grants stop flowing. For a game economy
  this is usually *not* what you want during a security incident; you typically want
  to keep emitting while freezing transfers.
- **All burning halts** — users can't even exit by burning.

If freezing minting is intended, document it. If not, override `_mint`/`_burn` (or
split the pause check) so minting by `MINTER_ROLE` is exempt. The current test
`test_PauseAndUnpause` only checks `transfer`, so this side effect is untested.

### M-3 — `TokenVesting` uses single-step ownership (`Ownable`, not `Ownable2Step`)
`TokenVesting` inherits `Ownable` (`src/TokenVesting.sol:14`). `transferOwnership` is
one-step: a typo in the address permanently strands ownership of a contract that may
hold 100M+ VTX across many schedules. There is also no way to recover from a lost
owner key.

**Recommendation:** switch to `Ownable2Step` (accept/decline pattern). Cheap, no
downside.

### M-4 — `revoke()` is not `nonReentrant` (inconsistent with `release()`)
`release()` is guarded by `nonReentrant` (`src/TokenVesting.sol:105`); `revoke()` is
not (`src/TokenVesting.sol:124`). The checks-effects-interactions ordering in
`revoke` is correct (`revoked = true` and `vestedAtRevoke` are set *before* the
external `safeTransfer`), so I do not see an exploitable path with the standard
VaultX token. **But** `TokenVesting` is token-agnostic — the `token` field accepts
any `IERC20`. A malicious or fee-on-transfer token's `transfer` could reenter
`revoke` (blocked by `AlreadyRevoked`) or `release` (which would then run under a
fresh non-reentrant lock with already-updated `vestedAtRevoke`). The math happens to
stay consistent, but this is fragile and depends on exact field ordering.

**Recommendation:** add `nonReentrant` to `revoke()` for defense-in-depth and
consistency. Costs ~2k gas, removes a class of reasoning.

### M-5 — Fee-on-transfer / deflationary tokens break accounting
`createVestingSchedule` records `totalAmount` as the nominal amount pulled via
`safeTransferFrom` (`src/TokenVesting.sol:96`), but does not verify the contract's
actual received balance. With a fee-on-transfer token, the contract receives less than
`totalAmount`, yet `_vestedAmount` and `release` compute against `totalAmount` —
`release` will revert when the balance runs out partway through vesting.

VaultX itself is a plain ERC20 with no fees, so this does not affect the current
deployment. But the vesting contract is written generically. **Recommendation:**
either (a) document that only standard non-fee ERC20s are supported, or (b) measure
`balanceBefore`/`balanceAfter` in `createVestingSchedule` and store the
actually-received amount as `totalAmount`.

---

## Low / Informational

### L-1 — Burned tokens are re-mintable (circulating cap, not lifetime cap)
`maxSupply` checks `totalSupply() + amount > maxSupply` (`src/VaultX.sol:47`). Since
`burn` reduces `totalSupply`, the contract can mint back up to `maxSupply` after burns
— so cumulative lifetime minting can exceed `maxSupply`, while circulating supply
never does. This is a legitimate design choice (common in game economies with
sink/source mechanics), but it is not documented and many readers will assume
`maxSupply` means "total ever minted." **Recommendation:** clarify in the natspec and
README whether burns open up re-mint headroom.

### L-2 — `mintBatch` lacks a dedicated event
Each element emits `Minted` via the inner `mint()` call, but there is no `MintedBatch`
event correlating the batch. Off-chain indexers can still reconstruct, but a batch
event (with `recipients`, `amounts`) improves auditability of large distributions.
Informational.

### L-3 — `mintBatch` all-or-nothing on bad entries
A single zero address or zero amount in the array reverts the entire batch (because
`mint` reverts and the whole tx rolls back). This is safe (atomic) but a UX footgun
for operators — one bad row voids a 200-row distribution. Consider pre-validating and
skipping, or returning the count of successful mints, depending on desired semantics.

### L-4 — `release()` callable by owner (forced distribution)
`release` allows `msg.sender == owner()` (`src/TokenVesting.sol:107`). The tokens
always go to `schedule.beneficiary`, so it is not theft, but the owner can force a
vesting realization event on a beneficiary who may not want it yet (tax/UX
implications). If this is intentional convenience, document it; otherwise restrict to
beneficiary (or beneficiary + approved delegate).

### L-5 — No beneficiary redirection
There is no way to change a schedule's beneficiary. For non-revocable schedules, if a
beneficiary loses their key, the tokens are permanently locked. Consider a
`transferBeneficiary(scheduleId, newBeneficiary)` callable by the beneficiary, or by
owner for revocable schedules.

### L-6 — No token rescue / sweep
If tokens (VTX or anything else) are sent directly to `TokenVesting` outside
`createVestingSchedule`, they are stuck forever — there is no `rescue`/`sweep`.
Recommend a `rescueERC20(token, to)` that cannot touch tokens that are accounted for
in active schedules (or that simply sweeps non-vesting tokens). Same applies to
`VaultX` itself (less critical since it's the token contract, but accidental
ETH/tokens sent to it are locked).

### L-7 — No explicit `scheduleId` bounds check in `release`/`revoke`
Passing an out-of-range `scheduleId` reads the zero slot. I traced both paths:
`release` → `_vestedAmount` returns 0 → `NoTokensDue` revert; `revoke` →
`revocable == false` → `NotRevocable` revert. So it is safe, but it relies on the
silent-zero behavior. An explicit `if (scheduleId >= scheduleCount) revert` is
clearer and future-proofs against refactors that change the zero-slot semantics.

### L-8 — Deployment script defaults all roles/allocations to the deployer
`DeployVaultX.s.sol:21-25` falls back to `deployer` for `admin`, `treasury`,
`rewards`, `liquidity`, and `team` if env vars are unset. If someone runs the script
without a complete `.env`, **all 700M VTX get minted to the deployer EOA and the
deployer becomes god-admin.** The Amoy deployment used correct env vars, but the
defaults are a footgun for the mainnet run.

**Recommendation:** `require(vm.envAddress("VAULTX_ADMIN") != address(0), ...)` etc.
— fail loudly if any critical env var is missing, rather than silently funneling
everything to the deployer.

### L-9 — Vesting "cliff" semantics are catch-up, not fresh-start
`_vestedAmount` (`src/TokenVesting.sol:172`) is linear from `start`, and the cliff
(`src/TokenVesting.sol:165`) only gates the *return* to 0 before `start + cliff`. At
the cliff moment, the beneficiary receives the full `totalAmount * cliff / duration`
catch-up in one claim (verified by `test_ReleaseAtCliff`). This is a valid and common
pattern, but some users expect "nothing until cliff, then linear from cliff."
Document the actual behavior to avoid beneficiary disputes.

---

## Things That Are Correct (worth noting)

- **Reentrancy on `release`**: guarded by `nonReentrant`; state (`released +=`)
  updated before external `safeTransfer`. Correct.
- **`revoke` CEI ordering**: `revoked` and `vestedAtRevoke` set before the external
  transfer. Correct.
- **Overflow**: 0.8.20 checked arithmetic; `totalSupply() + amount` cannot silently
  wrap. Correct.
- **`_update` override**: properly declares `override(ERC20, ERC20Pausable)` and
  calls `super._update`. Correct.
- **Zero-address/zero-amount guards**: present on `mint`,
  `createVestingSchedule`, constructor. Correct.
- **`maxSupply` immutable**: set once in constructor, cannot be raised later.
  Correct.
- **Permit / EIP-712**: uses OZ `ERC20Permit` with chainId in domain separator → no
  cross-chain replay. Correct.
- **No upgradeability / no proxy**: token is immutable, no admin-upgrade rug vector.
  Good for a token.
- **OpenZeppelin v5.2.0**: current release, no known advisories against the modules
  used.

---

## Recommended Priority Order

1. **H-3** Verify the contract on Polygonscan (do this before anything else — it's
   cheap and removes the biggest trust barrier).
2. **H-1** Move admin to a multisig + timelock; split MINTER/PAUSER/DEFAULT_ADMIN
   onto different signers.
3. **H-2** Make team vesting `revocable: false`, or give `TokenVesting` a separate,
   more secure owner.
4. **M-3** Switch `TokenVesting` to `Ownable2Step`.
5. **M-2** Decide and document whether pause should freeze minting; if not, exempt
   `MINTER_ROLE` mints.
6. **M-4** Add `nonReentrant` to `revoke()`.
7. **M-1** Cap `mintBatch` length.
8. **L-8** Make deployment script fail on missing env vars.
9. The remaining L-/I- items are documentation and UX hardening.

---

## Verdict

**Logic: sound. No exploitable bug found in the contract code itself.** The risk
profile is dominated by key management and operational defaults. As deployed on Amoy
(a testnet) this is fine. Before a mainnet launch, items H-1, H-2, and H-3 should be
resolved, and M-2/M-3/M-4 are strongly advised.
