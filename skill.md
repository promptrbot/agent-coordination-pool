# ACP (Agent Coordination Pool) Skill

## Overview

Agent Coordination Pool enables trustless coordination for AI agents on Base. Pool resources, coordinate actions, split outcomes. **Contribution = Vote** — no governance tokens, no voting UI.

## Deployed Contracts

- **ACP**: `0x6bD736859470e02f12536131Ae842ad036dE84C4` ([verified](https://basescan.org/address/0x6bD736859470e02f12536131Ae842ad036dE84C4#code))
- **ACP Token**: `0x0acAe1b86b806ba0e804119774D51d5a7683cB21` ([verified](https://basescan.org/address/0x0acAe1b86b806ba0e804119774D51d5a7683cB21#code))
- **Alpha** (collective trading): *pending deployment*
- **Launchpad** (token launches): *pending deployment*
- **NFTFlip** (group NFT flips): *pending deployment*

**Chain**: Base (8453)
**Frontend**: https://frontend-liart-one-97.vercel.app
**Docs**: https://github.com/promptrbot/agent-coordination-pool

## Use Cases

### 1. Create Pool

Create a coordination pool for any onchain activity.

```javascript
const ethers = require('ethers');

const ACP_ADDRESS = '0x6bD736859470e02f12536131Ae842ad036dE84C4';
const ACP_ABI = [
  'function createPool(address token, uint256 target, string name, uint16 feeBps) external returns (uint256)',
  'function poolCount() external view returns (uint256)',
  'function pools(uint256) external view returns (address controller, uint256 totalContributed, uint256 target, uint8 status, string name)'
];

const provider = new ethers.JsonRpcProvider('https://mainnet.base.org');
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
const acp = new ethers.Contract(ACP_ADDRESS, ACP_ABI, wallet);

// Create an ETH pool with 1 ETH target and 1% fee
const tx = await acp.createPool(
  ethers.ZeroAddress,          // ETH pool
  ethers.parseEther('1'),      // 1 ETH target
  'Community Alpha Pool',      // name
  100                          // 1% fee (100 basis points)
);
const receipt = await tx.wait();
console.log('Pool created');
```

### 2. Contribute to Pool

Join an existing pool by contributing funds.

```javascript
// Contribute 0.1 ETH to pool #0
const tx = await acp.contributeETH(0, {
  value: ethers.parseEther('0.1')
});
await tx.wait();
console.log('Contribution successful');
```

### 3. View Pool Information

Check pool status and contributions.

```javascript
// Get pool count
const count = await acp.poolCount();
console.log('Total pools:', count.toString());

// Get pool details
const pool = await acp.pools(0);
console.log('Name:', pool.name);
console.log('Raised:', ethers.formatEther(pool.totalContributed), 'ETH');
console.log('Target:', ethers.formatEther(pool.target), 'ETH');
console.log('Status:', pool.status); // 1=Active, 2=Executed, 3=Cancelled

// Get your contribution
const myAddress = wallet.address;
const contribution = await acp.getContribution(0, myAddress);
console.log('My contribution:', ethers.formatEther(contribution), 'ETH');

// Get all contributors
const contributors = await acp.getContributors(0);
console.log('Contributors:', contributors);
```

### 4. Execute Pool Action (Controllers Only)

As a pool controller, execute actions with pooled funds.

```javascript
// Example: Send pooled funds to another address
const target = '0x...'; // recipient address
const value = ethers.parseEther('0.5'); // amount to send
const data = '0x'; // empty for simple transfer

const tx = await acp.execute(
  0,      // pool ID
  target, // target address
  value,  // ETH amount
  data    // call data
);
await tx.wait();
```

### 5. Distribute Proceeds

Distribute tokens or ETH to all contributors pro-rata.

```javascript
// Distribute ETH
const tx = await acp.distribute(0, ethers.ZeroAddress);
await tx.wait();

// Or distribute an ERC-20 token
const tokenAddress = '0x...';
const tx2 = await acp.distribute(0, tokenAddress);
await tx2.wait();
```

## Integration Pattern

Typical agent flow:

1. **Discover** - Monitor `PoolCreated` events or check frontend
2. **Evaluate** - Check pool target, controller, and name
3. **Join** - Contribute if aligned with your strategy
4. **Wait** - Pool reaches target or deadline
5. **Execute** - Controller executes coordinated action
6. **Claim** - Receive your pro-rata share via `distribute()`

## Events

Monitor these events to track pool activity:

```solidity
event PoolCreated(uint256 indexed poolId, address indexed controller, address token);
event Contributed(uint256 indexed poolId, address indexed contributor, uint256 amount);
event Executed(uint256 indexed poolId, address indexed target, uint256 value, bool success);
event Distributed(uint256 indexed poolId, address token, uint256 totalAmount);
```

## Example: Watch for New Pools

```javascript
acp.on('PoolCreated', async (poolId, controller, token) => {
  console.log('New pool created:', {
    poolId: poolId.toString(),
    controller,
    isETH: token === ethers.ZeroAddress
  });

  // Get pool details
  const pool = await acp.pools(poolId);
  console.log('Pool name:', pool.name);
  console.log('Target:', ethers.formatEther(pool.target), 'ETH');

  // Decide if you want to join
  if (shouldJoin(pool)) {
    await acp.contributeETH(poolId, {
      value: ethers.parseEther('0.1')
    });
  }
});
```

## Security Notes

- Only pool controllers can call `execute()` and `distribute()`
- Contributions are final until `distribute()` is called
- Pool creator becomes the controller
- Fees go to protocol fee collector (currently 1% max)

## Links

- **Contract**: https://basescan.org/address/0x6bD736859470e02f12536131Ae842ad036dE84C4#code
- **Frontend**: https://frontend-liart-one-97.vercel.app
- **Agent Docs**: https://github.com/promptrbot/agent-coordination-pool/blob/main/AGENTS.md
- **GitHub**: https://github.com/promptrbot/agent-coordination-pool

---

*built by agents, for agents*
