# Implementation Plan - Final

## Status: Ready for Testing ✅

### ACP (Core) - ✅ Complete
- ETH/ERC-20 pools
- Contribution tracking
- Controller pattern (wrapper controls execution)
- Balance tracking per pool
- Distribute function for pro-rata payouts

### Alpha (Trading) - ✅ Complete
- Uses Aerodrome SlipStream (tickSpacing, not fee)
- ETH → WETH → swap → hold → swap back → distribute
- Hardcoded Base mainnet addresses

### Launchpad (Token Launches) - ✅ Complete
- **Real Clanker v4 integration**
- Uses devBuy extension to convert raised ETH to tokens
- Standard meme positions (95%/5% LP split)
- 1% static fees
- MEV protection enabled
- All LP rewards go to token creator

---

## Verified Addresses (Base Mainnet)

### Clanker v4
```solidity
address constant CLANKER = 0xE85A59c628F7d27878ACeB4bf3b35733630083a9;
address constant LOCKER = 0x63D2DfEA64b3433F4071A98665bcD7Ca14d93496;
address constant FEE_STATIC_HOOK_V2 = 0xb429d62f8f3bFFb98CdB9569533eA23bF0Ba28CC;
address constant MEV_MODULE_V2 = 0xebB25BB797D82CB78E1bc70406b13233c0854413;
address constant DEVBUY = 0x1331f0788F9c08C8F38D52c7a1152250A9dE00be;
```

### Aerodrome SlipStream
```solidity
address constant AERODROME_ROUTER = 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5;
```

### Base
```solidity
address constant WETH = 0x4200000000000000000000000000000000000006;
```

---

## Clanker Integration Details

### DeploymentConfig Structure
```
tokenConfig:
  - tokenAdmin: launch creator
  - name, symbol, image: from launch params
  - context: '{"interface":"ACP"}'
  - originatingChainId: 8453 (Base)

poolConfig:
  - hook: FeeStaticHookV2 (1% fees)
  - pairedToken: WETH
  - tickIfToken0IsClanker: -230400
  - tickSpacing: 200

lockerConfig:
  - locker: ClankerLpLockerFeeConversion
  - positions: Standard meme (95% near price, 5% wide)
  - rewards: 100% to creator

mevModuleConfig:
  - mevModule: ClankerSniperAuctionV2
  - startingFee: 66.6777%
  - endingFee: 4.1673%
  - decay: 15 seconds

extensionConfigs:
  - devBuy: all raised ETH converted to tokens
```

---

## Next Steps

1. **Deploy to Base Sepolia** - Test with fake tokens
2. **Test full flows:**
   - Alpha: create → join → buy → sell → claim
   - Launchpad: create → join → launch → claim
3. **Deploy to Base Mainnet**
4. **Build frontend**

---

## Research Sources

- Clanker SDK: https://github.com/clanker-devco/clanker-sdk
- Clanker Docs: https://clanker.gitbook.io/clanker-documentation
- Aerodrome SlipStream: https://basescan.org/address/0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5
