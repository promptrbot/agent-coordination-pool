# Alpha - Collective Trading

## What is Alpha?

**Alpha** is a wrapper for ACP that enables collective trading strategies. Pool ETH → Buy token at T1 → Sell at T2 → Distribute profits.

**Pattern**: Contribution = agreement on the trade. No voting needed.

## Contract Address

**Base Mainnet:** (not deployed yet - wrapper in development)

## How It Works

1. **Create a trade**: Set target token, buy time, sell time, threshold
2. **Contributors send ETH** (before deadline)
3. **Buy executes** when threshold met + buyTime reached
4. **Sell executes** when sellTime reached
5. **Anyone calls claim()** to distribute proceeds pro-rata

## Agent Workflow

### 1. Creating a Trade

```solidity
function createTrade(
    address tokenOut,      // Token to buy (e.g., USDC, DEGEN)
    int24 tickSpacing,     // 50 (0.5%), 100 (1%), or 200 (2%)
    uint256 threshold,     // Min ETH needed (e.g., 1 ether)
    uint256 buyTime,       // Unix timestamp when to buy
    uint256 sellTime,      // Unix timestamp when to sell
    uint256 deadline       // Funding deadline
) external returns (uint256 tradeId)
```

**Example:**
```javascript
const buyTime = Date.now() / 1000 + 3600; // 1 hour from now
const sellTime = buyTime + 86400; // 24 hours after buy
const deadline = Date.now() / 1000 + 1800; // 30 min funding window

await alpha.createTrade(
  DEGEN_TOKEN,
  100, // 1% fee tier
  parseEther("1"), // need 1 ETH
  buyTime,
  sellTime,
  deadline
);
```

### 2. Contributing

```solidity
function contribute(uint256 tradeId) external payable
```

**Example:**
```javascript
await alpha.contribute(0, { value: parseEther("0.5") });
```

### 3. Executing Buy

```solidity
function executeBuy(uint256 tradeId) external
```

- Anyone can call when `block.timestamp >= buyTime` and threshold met
- Swaps ETH → target token via Aerodrome

### 4. Executing Sell

```solidity
function executeSell(uint256 tradeId) external
```

- Anyone can call when `block.timestamp >= sellTime`
- Swaps target token → ETH via Aerodrome

### 5. Claiming Proceeds

```solidity
function claim(uint256 tradeId) external
```

- Distributes ETH to all contributors pro-rata
- Anyone can call (triggers ACP distribution)

### 6. Withdrawing (if threshold not met)

```solidity
function withdraw(uint256 tradeId) external
```

- Returns your ETH if funding deadline passed without hitting threshold

## Reading Trade Info

```solidity
struct Trade {
    uint256 poolId;
    address tokenOut;
    int24 tickSpacing;
    uint256 threshold;
    uint256 buyTime;
    uint256 sellTime;
    uint256 deadline;
    uint256 amountBought;
    Status status; // Funding, Bought, Sold, Expired
}

function trades(uint256 tradeId) external view returns (Trade memory);
```

## DEX Integration

Alpha uses **Aerodrome SlipStream** (concentrated liquidity) for swaps.

**Common tick spacings:**
- 50: 0.5% fee tier (stable pairs)
- 100: 1% fee tier (most pairs)
- 200: 2% fee tier (volatile pairs)

## Example Use Cases

1. **Time-based swing trade**: "Buy DEGEN at 2pm, sell at 2pm tomorrow"
2. **Announcement play**: "Pool $10k ETH, buy 5 min after announcement, sell 24h later"
3. **Volatility capture**: "Buy during expected dip, sell during expected pump"

## Important Notes

- **No slippage protection in wrapper** (relies on AMM price impact)
- **Execution is permissionless** (anyone can trigger buy/sell at the right time)
- **Contributors can't cancel** after contributing (unless threshold not met)
- **Controller is the Alpha contract itself** (not an external address)

## Frontend Integration

See the main ACP frontend for interaction patterns. Typically:
1. Display all trades with status
2. Allow contributions before deadline
3. Show countdown to buy/sell times
4. Trigger execute functions when times reached
5. Claim button after sell executes
