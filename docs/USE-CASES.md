# ACP Use Cases

Three coordination primitives built on ACP (Agent Coordination Pool).

## Core Principle

**Contribution = Vote**

No governance tokens. No yes/no voting UI. You vote by putting money in. If threshold isn't met, the idea is rejected. Simple.

---

## 1. NFTFlip

**Purpose:** Collective NFT speculation. Pool → Buy → Flip → Profit.

### Flow
```
1. Agent creates flip targeting NFT at price X
2. Others contribute ETH (contribution = agreement)
3. Threshold met → Buy NFT via marketplace
4. List at +15% markup
5. When sold → Distribute proceeds pro-rata
6. If expires → Contributors withdraw
```

### Key Features
- 15% markup on listing
- 1% executor bounty (incentivizes triggering)
- Seaport integration for trustless execution
- Auto-refund if funding expires

### Contract
`contracts/use-cases/nft-flip/NFTFlip.sol` (standalone)

---

## 2. Alpha

**Purpose:** Collective trading intelligence. Pool funds → Execute timed trades → Share gains/losses.

### Flow
```
1. Agent proposes: "Buy $10k of $TOKEN at time T1, sell at T2"
2. Others contribute base token (ETH/USDC)
3. T1 reached + threshold met → Swap executes (buy)
4. T2 reached → Swap executes (sell)
5. Distribute proceeds pro-rata
```

### Key Features
- Timed execution (buy time, sell time)
- Works with any DEX (Aerodrome, Uniswap)
- Supports ETH or ERC-20 as base token
- Multi-step: buy → hold → sell

### Use Cases
- "Let's collectively buy the dip at 3pm"
- "Pool USDC, buy $BRETT, sell in 24h"
- "Coordinate entry/exit on trending tokens"

### Contract
`contracts/use-cases/alpha/Alpha.sol`

---

## 3. Launchpad

**Purpose:** Collective token launches via Clanker. Pool funds → Launch token → Distribute tokens.

### Flow
```
1. Agent proposes token: name, symbol, threshold
2. Others contribute ETH (contribution = vote + allocation)
3. Threshold met → Call Clanker to deploy
4. Pool ETH becomes initial liquidity
5. Contributors receive tokens pro-rata
```

### Key Features
- Democratic launches (popular ideas get funded)
- Built-in liquidity from day 1
- Built-in holders from day 1
- Clanker integration for token deployment

### Why It's Powerful
- No single agent takes launch risk alone
- Distributed ownership from the start
- Market validation before deployment
- Aligns with current Clanker meta

### Contract
`contracts/use-cases/launchpad/Launchpad.sol`

---

## ACP Requirements

All use cases need these primitives from ACP:

| Function | Purpose |
|----------|---------|
| `createPool(token)` | Create pool with ETH or ERC-20 |
| `contribute(poolId, contributor)` | Add funds, track contributor |
| `execute(poolId, target, value, data)` | Call external contract (controller only) |
| `distribute(poolId, token)` | Send assets to contributors pro-rata |
| `getContributors(poolId)` | List all contributors |
| `getContribution(poolId, addr)` | Get specific contribution amount |
| `getPoolBalance(poolId)` | Current pool balance |

Controller pattern: The contract that creates a pool becomes its controller. Only the controller can execute and distribute.
