# ACP - Agent Coordination Pool

## What is ACP?

ACP is the **core primitive** for pooled resource coordination. It's like a smart escrow that allows multiple parties to pool funds, execute onchain actions, and split outcomes pro-rata.

**Key concept**: Contribution = Vote. No governance tokens, no voting UI needed.

## Architecture

```
┌─────────────────────┐
│   ACP (Primitive)   │  ← Core pooling logic
└─────────────────────┘
          ↑
          │ calls
          │
┌─────────────────────┐
│  Wrapper Contracts  │  ← Product-specific logic
│  (Alpha, Launchpad, │
│   NFTFlip, etc.)    │
└─────────────────────┘
          ↑
          │ users interact with
          │
┌─────────────────────┐
│       Users         │
└─────────────────────┘
```

## Core Functions

### Creating a Pool

```solidity
function createPool(address token) external returns (uint256 poolId)
```

- `token`: address(0) for ETH, or ERC-20 address
- Returns a `poolId` you'll use for all operations
- **Caller becomes the controller** (only controller can execute/distribute)

### Contributing

```solidity
// For ETH pools
function contribute(uint256 poolId, address contributor) external payable onlyController(poolId)

// For ERC-20 pools
function contributeToken(uint256 poolId, address contributor, uint256 amount) external onlyController(poolId)
```

- Only the controller can call these
- `contributor` is the address to credit (allows wrappers to attribute correctly)

### Executing Actions

```solidity
function execute(uint256 poolId, address target, uint256 value, bytes calldata data)
    external onlyController(poolId) returns (bool success, bytes memory result)
```

- Execute arbitrary onchain actions with pool funds
- Examples: swap tokens, buy NFTs, launch tokens

### Distributing Proceeds

```solidity
// For ETH
function distribute(uint256 poolId) external onlyController(poolId)

// For ERC-20
function distributeToken(uint256 poolId, address token) external onlyController(poolId)
```

- Sends funds to contributors pro-rata based on their contributions
- Anyone in the pool can call this (not just controller)

## Fees

- Each pool can set a fee (max 1%)
- Default: 1% directed to ACP treasury (vested wallet)
- Fees are deducted during distribution

## Contract Addresses

**Base Mainnet:**
- ACP Core: `0x6bD736859470e02f12536131Ae842ad036dE84C4`
- Frontend: https://acp.vercel.app

## For Agents

When building with ACP, you typically:

1. **Deploy a wrapper contract** that becomes the controller
2. **Users interact with your wrapper**, which calls ACP
3. **Your wrapper implements the product logic** (trading, launching, NFT flipping)
4. **ACP handles pooling + distribution** (no need to reimplement)

See the specific wrapper skills for detailed examples:
- Alpha (Collective Trading)
- Launchpad (Token Launches)
- NFTFlip (Group NFT Purchases)
