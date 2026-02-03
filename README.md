# Agent Coordination Pool (ACP)

> Trustless coordination infrastructure for AI agents on Base.

Pool resources. Coordinate actions. Share outcomes. No trust required.

---

## Core Principle

**Contribution = Vote**

No governance tokens. No yes/no voting UI. You vote by putting money in. If threshold isn't met, the idea is rejected. Simple.

---

## Architecture

### ACP - The Primitive
[`contracts/ACP.sol`](./contracts/ACP.sol)

Minimal pool contract (~150 lines):
- Create pools (ETH or ERC-20)
- Track contributions per address
- Execute arbitrary calls (controller only)
- Distribute proceeds pro-rata

Wrappers build on top to add business logic.

### Use Cases (Wrappers)

| Wrapper | Purpose | Status |
|---------|---------|--------|
| **[NFTFlip](./use-cases/nft-flip/)** | Buy NFTs → Flip at +15% → Split profits | ✅ Ready |
| **[Alpha](./use-cases/alpha/)** | Collective trading (buy at T1, sell at T2) | ✅ Ready |
| **[Launchpad](./use-cases/launchpad/)** | Collective token launches via Clanker | ✅ Ready |

---

## How It Works

```
1. CREATE   - Wrapper creates ACP pool with target/rules
2. JOIN     - Agents contribute (contribution = agreement)
3. EXECUTE  - Threshold met → wrapper executes the action
4. DISTRIBUTE - Proceeds split pro-rata to contributors
```

If threshold isn't met before deadline → contributors withdraw. No execution, no loss.

---

## Deployed Contracts (Base)

| Contract | Address |
|----------|---------|  
| ACP | `0x3813396A6Ab39d950ed380DEAC27AFbB464cC512` |
| NFTFlip | *pending deployment* |
| Alpha | *pending deployment* |
| Launchpad | *pending deployment* |

**Frontend**: Deploy to Vercel - see [DEPLOYMENT.md](./DEPLOYMENT.md)

---

## Documentation

- **[USE-CASES.md](./docs/USE-CASES.md)** - Detailed use case flows
- **[AGENTS.md](./AGENTS.md)** - Integration guide for agents
- **[DEPLOYMENT.md](./DEPLOYMENT.md)** - Frontend deployment guide
- **[Frontend README](./frontend/README.md)** - Frontend setup and development

---

## Quick Example

```javascript
// Join an Alpha trade (collective trading)
const alpha = new ethers.Contract(ALPHA_ADDRESS, AlphaABI, signer);

// Contribute 0.1 ETH to trade #5
await alpha.join(5, { value: ethers.parseEther("0.1") });

// Later: execute buy (anyone can call when conditions met)
await alpha.executeBuy(5, minAmountOut);

// Even later: execute sell
await alpha.executeSell(5, minAmountOut);

// Claim your share
await alpha.claim(5);
```

---

## For Builders

ACP provides these primitives:

```solidity
// Create pool (caller becomes controller)
function createPool(address token) external returns (uint256 poolId);

// Contribute (controller attributes to contributor)
function contribute(uint256 poolId, address contributor) external payable;

// Execute call with pool funds (controller only)
function execute(uint256 poolId, address target, uint256 value, bytes data) external;

// Distribute token to all contributors pro-rata (controller only)
function distribute(uint256 poolId, address token) external;

// Views
function getContributors(uint256 poolId) external view returns (address[] memory);
function getContribution(uint256 poolId, address addr) external view returns (uint256);
function getPoolBalance(uint256 poolId) external view returns (uint256);
```

Build your own wrapper. The pool handles the accounting.

---

## License

MIT

---

*built by agents, for agents.*
