# VaultX (VTX) Pre-Production Checklist

This document tracks everything that must be completed before deploying VaultX to Polygon mainnet for production use. Treat it as a living checklist; update it as decisions are made.

## 1. Tokenomics & Legal

| # | Task | Owner | Status | Notes |
|---|------|-------|--------|-------|
| 1.1 | Finalize max total supply | | | Default is 1,000,000,000 VTX. This is immutable after deploy. |
| 1.2 | Finalize allocation percentages and recipient addresses | | | Treasury, rewards, liquidity, team, reserve, etc. |
| 1.3 | Confirm team vesting schedule | | | Start timestamp, cliff length, total duration. |
| 1.4 | Decide whether any allocations are revocable | | | Default is revocable for team. |
| 1.5 | Legal review of token distribution (jurisdiction-dependent) | | | Securities, tax, and gaming-regulation considerations. |
| 1.6 | Confirm ticker symbol `VTX` is available on target exchanges/aggregators | | | Check CoinMarketCap, CoinGecko, DEXs. |

## 2. Smart Contract Hardening

| # | Task | Owner | Status | Notes |
|---|------|-------|--------|-------|
| 2.1 | Finalize contract source code | | | `VaultX.sol` and `TokenVesting.sol` frozen. |
| 2.2 | Run full test suite on final code | | | `forge test` should pass with 0 warnings. |
| 2.3 | External security audit | | | Recommend at least one firm familiar with ERC-20/game tokens. |
| 2.4 | Fix any audit findings and re-run tests | | | |
| 2.5 | Verify no unused errors, events, or functions remain | | | Remove dead code. |
| 2.6 | Confirm contract sizes are well under limits | | | Current: VaultX ~6.3KB, TokenVesting ~2.8KB. |
| 2.7 | Document all custom errors and events | | | See `README.md` or autogenerate docs. |

## 3. Deployment Infrastructure

| # | Task | Owner | Status | Notes |
|---|------|-------|--------|-------|
| 3.1 | Create a Safe multisig for `VAULTX_ADMIN` | | | Recommended: 2-of-3 or 3-of-5 signers. |
| 3.2 | Fund deployer wallet with MATIC for mainnet gas | | | Also fund the Safe with a small amount for future admin txs. |
| 3.3 | Set up Polygon RPC endpoint | | | Use a reliable provider (Alchemy, Infura, QuickNode). |
| 3.4 | Obtain Polygonscan API key | | | Required for `--verify` in Foundry. |
| 3.5 | Fill out `.env` with production values | | | Do not commit `.env`. |
| 3.6 | Verify all `.env` recipient addresses are correct and controlled | | | Double-check each address by the owner. |

## 4. Testnet Dress Rehearsal (Amoy)

| # | Task | Owner | Status | Notes |
|---|------|-------|--------|-------|
| 4.1 | Deploy to Amoy using the production deployment script | | | `make deploy-amoy` |
| 4.2 | Verify contracts on Amoy Polygonscan | | | Confirm source matches. |
| 4.3 | Simulate all admin flows | | | Mint, pause/unpause, burn, grant/revoke roles. |
| 4.4 | Simulate vesting flows | | | Create schedule, release at cliff, revoke unvested. |
| 4.5 | Test multisig as admin on Amoy | | | Make sure the Safe can execute admin functions. |
| 4.6 | Record deployed Amoy addresses and ABIs | | | Save to a private runbook. |
| 4.7 | Have at least one independent person review the deployed contracts | | | E.g., verify on Polygonscan manually. |

## 5. Mainnet Deployment

| # | Task | Owner | Status | Notes |
|---|------|-------|--------|-------|
| 5.1 | Choose a quiet, low-gas window for deployment | | | Avoid high congestion periods. |
| 5.2 | Run final dry-run simulation locally | | | `forge script ... --dry-run` or anvil fork. |
| 5.3 | Deploy to Polygon mainnet with `--broadcast --verify` | | | `make deploy-polygon` |
| 5.4 | Confirm contracts are verified on Polygonscan | | | Both `VaultX` and `TokenVesting`. |
| 5.5 | Save mainnet contract addresses and deployment transaction hashes | | | |
| 5.6 | Confirm initial token balances match the allocation plan | | | Treasury, rewards, liquidity, vesting contract. |

## 6. Post-Deployment Lockdown

| # | Task | Owner | Status | Notes |
|---|------|-------|--------|-------|
| 6.1 | Revoke unnecessary `MINTER_ROLE` and `PAUSER_ROLE` from deployer EOA | | | Leave only the Safe multisig with admin roles. |
| 6.2 | Verify the Safe multisig holds `DEFAULT_ADMIN_ROLE` | | | |
| 6.3 | Confirm team vesting schedule is created and funded | | | Tokens transferred to `TokenVesting`. |
| 6.4 | Confirm no unaccounted tokens were minted | | | Total supply == sum of all allocations. |
| 6.5 | Store final deployment artifacts securely | | | `.env`, broadcast JSON, ABIs, runbook. |

## 7. Launch Preparations

| # | Task | Owner | Status | Notes |
|---|------|-------|--------|-------|
| 7.1 | Seed initial liquidity (if planned) | | | DEX pool, market maker, etc. |
| 7.2 | Submit token info to CoinGecko / CoinMarketCap | | | Requires contract address, logo, socials. |
| 7.3 | Publish token contract addresses on official channels | | | Website, Discord, docs. |
| 7.4 | Set up monitoring for large transfers or unusual activity | | | Optional for v1. |
| 7.5 | Prepare a bug bounty / immunefi program (optional) | | | For higher confidence at scale. |
| 7.6 | Draft player-facing docs for token utility | | | Rewards, vesting claims, future staking. |

## 8. Governance & Future Roadmap

| # | Task | Owner | Status | Notes |
|---|------|-------|--------|-------|
| 8.1 | Decide how future minting will be controlled | | | Only up to max supply via `MINTER_ROLE`. |
| 8.2 | Plan staking contract design | | | Separate from the ERC-20. |
| 8.3 | Plan marketplace / NFT asset integration | | | Separate contracts. |
| 8.4 | Decide on a treasury management framework | | | Multisig, DAO, or both. |

---

## Quick Reference: Production `.env` values

```
POLYGON_RPC_URL=
POLYGONSCAN_API_KEY=
PRIVATE_KEY=
VAULTX_ADMIN=<Safe multisig address>
VAULTX_TREASURY=
VAULTX_REWARDS=
VAULTX_LIQUIDITY=
VAULTX_TEAM=
VAULTX_MAX_SUPPLY=1000000000000000000000000000
VAULTX_TREASURY_ALLOCATION=200000000000000000000000000
VAULTX_REWARDS_ALLOCATION=300000000000000000000000000
VAULTX_LIQUIDITY_ALLOCATION=100000000000000000000000000
VAULTX_TEAM_ALLOCATION=100000000000000000000000000
VAULTX_VESTING_START=<mainnet deploy timestamp or later>
VAULTX_VESTING_CLIFF=31536000
VAULTX_VESTING_DURATION=126230400
```

---

## Definition of Done

Production is ready when:

- [ ] All items above are completed or explicitly deferred with owner sign-off.
- [ ] Contracts are deployed and verified on Polygon mainnet.
- [ ] Admin roles are held only by the Safe multisig.
- [ ] No EOA or deployer retains `MINTER_ROLE`, `PAUSER_ROLE`, or `DEFAULT_ADMIN_ROLE`.
- [ ] Initial token balances match the published tokenomics plan.
