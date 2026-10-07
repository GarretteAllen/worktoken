# VaultX (VTX)

ERC-20 token for the VaultX game economy. Deployed on Polygon PoS.

## Contracts

| Contract | Purpose |
|----------|---------|
| `VaultX` | Fixed-supply ERC-20 with role-based minting, burn, pause, and permit. |
| `TokenVesting` | Linear vesting with cliff for team and early contributor allocations. |

## Tokenomics (default placeholder)

| Allocation | Amount | % of Max Supply |
|------------|--------|-----------------|
| Treasury | 200,000,000 VTX | 20% |
| Game Rewards | 300,000,000 VTX | 30% |
| Liquidity | 100,000,000 VTX | 10% |
| Team Vesting | 100,000,000 VTX | 10% |
| Reserve/Unminted | 300,000,000 VTX | 30% |

Max supply: **1,000,000,000 VTX** (18 decimals).

## Roles

| Role | Held by | Capabilities |
|------|---------|--------------|
| `DEFAULT_ADMIN_ROLE` | Admin multisig | Grant/revoke all roles, recover control. |
| `MINTER_ROLE` | Admin + designated minters | Mint up to max supply. |
| `PAUSER_ROLE` | Admin + designated pausers | Pause/unpause transfers. |

For mainnet, the admin should be a Safe multisig.

## Development

Requires [Foundry](https://book.getfoundry.sh/).

```bash
# Build contracts
forge build

# Run tests
forge test

# Run tests with gas report
forge test --gas-report
```

## Deployment

1. Copy `.env.example` to `.env` and fill in values.
2. Fund the deployer wallet with MATIC (or Amoy testnet MATIC).
3. Run the deployment script:

### Amoy testnet

```bash
source .env
forge script script/DeployVaultX.s.sol --rpc-url $AMOY_RPC_URL --broadcast --verify
```

### Polygon mainnet

```bash
source .env
forge script script/DeployVaultX.s.sol --rpc-url $POLYGON_RPC_URL --broadcast --verify
```

## Mainnet deployment checklist

For a full pre-production checklist, see [`PRODUCTION_READINESS.md`](PRODUCTION_READINESS.md).

Quick summary:

- [ ] Confirm final tokenomics and recipient addresses.
- [ ] Create a Safe multisig for `VAULTX_ADMIN`.
- [ ] Fund deployer with mainnet MATIC.
- [ ] Run full test suite: `forge test`.
- [ ] Deploy to Amoy and simulate all admin flows.
- [ ] Obtain a Polygonscan API key for verification.
- [ ] Deploy to Polygon mainnet.
- [ ] Verify contracts on Polygonscan.
- [ ] Revoke unnecessary minter/pauser roles after initial minting.
- [ ] Publish token metadata on CoinGecko/CoinMarketCap (later).

## Next phases

- Staking contract (separate from the ERC-20).
- In-game marketplace and NFT asset contracts.
- Game reward distribution contract.
- DAO/governance tokenomics (optional).

## License

MIT
