# Launchpad - Collective Token Launches

## What is Launchpad?

**Launchpad** is a wrapper for ACP that enables groups to launch tokens together via Clanker v4. Pool funds → Launch token → Share LP fees.

**Key benefit**: All trading fees from the Uniswap V4 pool go to contributors, not just the creator.

## Contract Address

**Base Mainnet:** `0xb68B3c9dB7476fc2139D5fB89C76458C8688cf19` ([BaseScan](https://basescan.org/address/0xb68B3c9dB7476fc2139D5fB89C76458C8688cf19))

## How It Works

1. **Create a launch**: Set token config, threshold, deadline
2. **Contributors send ETH** (before deadline)
3. **Launch executes** when threshold met
4. **LP fees accumulate** in the Uniswap V4 pool
5. **Anyone calls claimFees()** to distribute fees to contributors

## Agent Workflow

### 1. Creating a Launch

```solidity
function createLaunch(
    string memory name,
    string memory symbol,
    string memory image,        // IPFS URL for token image
    string memory metadata,     // Additional metadata
    uint256 threshold,          // Min ETH to launch
    uint256 deadline            // Funding deadline
) external returns (uint256 launchId)
```

**Example:**
```javascript
await launchpad.createLaunch(
  "Agent Meme Token",
  "AGENT",
  "ipfs://Qm...", // token image
  "Launched by community", // metadata
  parseEther("2"), // need 2 ETH
  Date.now() / 1000 + 3600 // 1 hour deadline
);
```

### 2. Contributing

```solidity
function contribute(uint256 launchId) external payable
```

**Example:**
```javascript
await launchpad.contribute(0, { value: parseEther("0.5") });
```

### 3. Executing Launch

```solidity
function executeLaunch(uint256 launchId) external
```

- Anyone can call when threshold met + deadline passed
- Deploys token via Clanker v4
- Creates Uniswap V4 pool with contributed ETH as liquidity
- LP fees directed to ACP pool (split among contributors)

### 4. Claiming LP Fees

```solidity
function claimFees(uint256 launchId) external
```

- Claims accumulated trading fees from Clanker Fee Locker
- Distributes fees to contributors pro-rata via ACP
- Anyone can call this at any time

### 5. Withdrawing (if threshold not met)

```solidity
function withdraw(uint256 launchId) external
```

- Returns your ETH if deadline passed without hitting threshold

## Reading Launch Info

```solidity
struct Launch {
    uint256 poolId;
    string name;
    string symbol;
    string image;
    string metadata;
    uint256 threshold;
    uint256 deadline;
    address deployedToken;
    Status status; // Funding, Launched, Cancelled
}

function launches(uint256 launchId) external view returns (Launch memory);
```

## Clanker Integration

Launchpad uses **Clanker v4** to deploy tokens with:
- Uniswap V4 pool creation
- LP fee distribution to contributors
- Standard ERC-20 token (no mint/burn functions)

**Clanker v4 Address (Base):** `0xE85A59c628F7d27878ACeB4bf3b35733630083a9`

**Fee Locker Address (Base):** `0x050b022C3512404508D5b5f6be312ec59070e0C5`

## LP Fees

- All trading fees from the Uniswap V4 pool accumulate in the Fee Locker
- `claimFees()` pulls accumulated fees and distributes them via ACP
- **Contributors get ongoing passive income** as long as people trade the token
- No time limit on fee claims

## Example Use Cases

1. **Community token**: "Pool $5k, launch together, share fees"
2. **Agent-launched token**: "AI agent creates token, community funds launch"
3. **Meme token**: "Group launches meme, everyone gets LP fees"

## Important Notes

- **Threshold must be met to launch** (otherwise everyone withdraws)
- **Token cannot be relaunched** if launch fails
- **LP fees are separate from initial contribution** (ongoing revenue)
- **No refunds after launch** (you get LP fee share instead)
- **Controller is the Launchpad contract itself**

## Frontend Integration

Typical flow:
1. Display all launches with funding status
2. Show countdown to deadline
3. Allow contributions before deadline
4. Trigger launch when threshold met
5. Display deployed token address
6. Show accumulated LP fees
7. Claim fees button (visible to all contributors)
