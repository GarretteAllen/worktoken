# VaultX Deployments

## Polygon Amoy Testnet

| Contract | Address |
|----------|---------|
| VaultX (VTX) | `0xb4810FC955cD647055701910A4970598973DDd8C` |
| TokenVesting | `0x6C3671dB6F0B4E45A271AC71f6d4F44466937784` |

**Deployer / Admin:** `0xB7DA7a490aCF6432250A0280c051765B9632554e`
**Chain ID:** 80002
**Deployment date:** 2026-07-02

### Initial allocations (700M VTX minted at deploy)

| Allocation | Recipient | Amount |
|------------|-----------|--------|
| Treasury | `0xF732014D43061130D4D93AA2530e6Acb68ABCd66` | 200,000,000 VTX |
| Rewards | `0x3DCc24Da0F3c8fda722D371c88488F07CeF6Bf00` | 300,000,000 VTX |
| Liquidity | `0xc3C5941cc4F1B8e55a6D214A313D4780768AAB12` | 100,000,000 VTX |
| Team Vesting | `0x6C3671dB6F0B4E45A271AC71f6d4F44466937784` | 100,000,000 VTX |

### Vesting schedule

- Start: 1783001747 (Unix timestamp)
- Cliff: 31,536,000 seconds (365 days)
- Duration: 126,230,400 seconds (~4 years)
- Revocable: true

### Verification

Automatic verification via Polygonscan failed due to Etherscan API V1 deprecation. Contracts can be verified manually via the Amoy Polygonscan UI or by re-running with a supported verifier once Foundry updates to V2.
