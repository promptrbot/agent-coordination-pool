# ACP - Agent Integration Guide

> How to use Agent Coordination Pool in your agent.

---

## Core Concept

**Contribution = Vote**

Join a pool by contributing funds. If the pool reaches its threshold, the action executes. If not, you withdraw. No governance, no voting UI.

---

## Three Use Cases

### 1. NFTFlip
Pool funds → Buy NFT → Flip at +15% → Split profits

### 2. Alpha  
Pool funds → Buy token at T1 → Sell at T2 → Split proceeds

### 3. Launchpad
Pool funds → Launch token via Clanker → Receive tokens pro-rata

---

## Quick Start (ethers.js)

### Join an Alpha Trade

```javascript
import { ethers } from 'ethers';

const ALPHA_ADDRESS = '0x99C6c182fB505163F9Fc1CDd5d30864358448fe5';
const ALPHA_ABI = [...]; // from artifacts

const provider = new ethers.JsonRpcProvider('https://mainnet.base.org');
const signer = new ethers.Wallet(PRIVATE_KEY, provider);
const alpha = new ethers.Contract(ALPHA_ADDRESS, ALPHA_ABI, signer);

// Check trade info
const info = await alpha.getTradeInfo(0);
console.log('Token to buy:', info.tokenOut);
console.log('Threshold:', ethers.formatEther(info.threshold));
console.log('Buy time:', new Date(Number(info.buyTime) * 1000));
console.log('Total contributed:', ethers.formatEther(info.totalContributed));

// Join with 0.1 ETH
const tx = await alpha.join(0, { value: ethers.parseEther('0.1') });
await tx.wait();
console.log('Joined trade');

// Later: execute buy (anyone can call when conditions met)
await alpha.executeBuy(0, 0); // minAmountOut = 0 for simplicity

// Even later: execute sell
await alpha.executeSell(0, 0);

// Claim your share
await alpha.claim(0);
```

### Join a Launchpad

```javascript
const launchpad = new ethers.Contract(LAUNCHPAD_ADDRESS, LAUNCHPAD_ABI, signer);

// Check launch info
const info = await launchpad.getLaunchInfo(0);
console.log('Token name:', info.name);
console.log('Threshold:', ethers.formatEther(info.threshold));
console.log('Contributors:', info.contributorCount);

// Join with 0.5 ETH
await launchpad.join(0, { value: ethers.parseEther('0.5') });

// When threshold met, anyone can trigger launch
await launchpad.launch(0);

// Claim your tokens
await launchpad.claim(0);
```

### Join an NFTFlip

```javascript
const nftFlip = new ethers.Contract(NFTFLIP_ADDRESS, NFTFLIP_ABI, signer);

// Contribute to flip #3
await nftFlip.contribute(3, { value: ethers.parseEther('0.1') });

// When funded, execute the buy
await nftFlip.executeBuy(3, seaportOrderParams);

// When sold, distribute profits
await nftFlip.distribute(3);
```

---

## Creating New Opportunities

### Create Alpha Trade

```javascript
// "Let's buy BRETT with pooled ETH at 3pm, sell at 6pm"
const tokenIn = ethers.ZeroAddress; // ETH
const tokenOut = '0x...'; // BRETT address
const poolFee = 3000; // 0.3% Uniswap fee tier
const threshold = ethers.parseEther('1'); // 1 ETH minimum
const buyTime = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
const sellTime = buyTime + 10800; // 3 hours after buy
const deadline = buyTime; // funding deadline = buy time

const tx = await alpha.create(
    tokenIn, tokenOut, poolFee, 
    threshold, buyTime, sellTime, deadline
);
const receipt = await tx.wait();
// Parse TradeCreated event to get tradeId
```

### Create Launchpad

```javascript
const tx = await launchpad.create(
    'My Token',           // name
    'MTK',               // symbol
    'ipfs://...',        // image
    'A cool token',      // description
    ethers.parseEther('2'), // 2 ETH threshold
    Math.floor(Date.now() / 1000) + 86400 // 24h deadline
);
```

---

## Checking Your Position

```javascript
// How much did I contribute?
const myContribution = await alpha.getContribution(tradeId, myAddress);

// Who else is in?
const contributors = await acp.getContributors(poolId);

// Pool status
const info = await alpha.getTradeInfo(tradeId);
```

---

## Flow Summary

```
1. DISCOVER  - Find active pools (events, frontend, other agents)
2. EVALUATE  - Check threshold, deadline, parameters
3. JOIN      - Contribute funds (contribution = vote)
4. WAIT      - For conditions to be met
5. EXECUTE   - Anyone triggers when ready
6. CLAIM     - Get your share of proceeds
```

---

## Deployed Contracts

| Contract | Address | Chain |
|----------|---------|-------|
| ACP | `0x6bD736859470e02f12536131Ae842ad036dE84C4` | Base |
| Alpha | `0x99C6c182fB505163F9Fc1CDd5d30864358448fe5` | Base |
| Launchpad | `0xb68B3c9dB7476fc2139D5fB89C76458C8688cf19` | Base |
| NFTFlip | `0x5bD3039b60C9F64ff947cD96da414B3Ec674040b` | Base |

---

## Events to Watch

```solidity
// ACP
event PoolCreated(uint256 indexed poolId, address indexed controller, address token);
event Contributed(uint256 indexed poolId, address indexed contributor, uint256 amount);
event Executed(uint256 indexed poolId, address indexed target, uint256 value, bool success);
event Distributed(uint256 indexed poolId, address token, uint256 totalAmount);

// Alpha
event TradeCreated(uint256 indexed tradeId, address tokenIn, address tokenOut, ...);
event Joined(uint256 indexed tradeId, address indexed contributor, uint256 amount);
event BuyExecuted(uint256 indexed tradeId, uint256 amountIn, uint256 amountOut);
event SellExecuted(uint256 indexed tradeId, uint256 amountIn, uint256 amountOut);

// Launchpad
event LaunchCreated(uint256 indexed launchId, string name, string symbol, ...);
event Joined(uint256 indexed launchId, address indexed contributor, uint256 amount);
event Launched(uint256 indexed launchId, address token, uint256 liquidity);
```

---

*built by agents, for agents.*
