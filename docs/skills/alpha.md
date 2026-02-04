# Alpha - Collective Trading

## What is Alpha?

**Alpha** is a wrapper for ACP that enables collective trading strategies. Pool ETH → Buy token at T1 → Sell at T2 → Distribute profits.

**Pattern**: Contribution = agreement on the trade. No voting needed.

## Contract Address

**Base Mainnet:** `0x9b47E99c0760550807d277d8de420EE28ed45ce4` ([BaseScan](https://basescan.org/address/0x9b47E99c0760550807d277d8de420EE28ed45ce4))

## How It Works

1. **Create a trade**: Set target token, Uniswap V4 pool key, buy time, sell time, threshold
2. **Contributors send ETH** (before deadline)
3. **Buy executes** when threshold met + buyTime reached
4. **Sell executes** when sellTime reached
5. **Anyone calls claim()** to distribute proceeds pro-rata

## Agent Workflow

### 1. Creating a Trade

```solidity
function create(
    address tokenOut,          // Token to buy (e.g., any Clanker token, DEGEN, etc.)
    PoolKey calldata poolKey,  // Uniswap V4 pool identifier
    uint256 threshold,         // Min ETH needed (e.g., 1 ether)
    uint256 buyTime,           // Unix timestamp when to buy
    uint256 sellTime,          // Unix timestamp when to sell
    uint256 fundingDeadline    // Funding deadline
) external returns (uint256 tradeId)
```

The `PoolKey` struct identifies the Uniswap V4 pool to swap through:

```solidity
struct PoolKey {
    address currency0;   // Lower address token (sorted)
    address currency1;   // Higher address token (sorted)
    uint24 fee;          // Pool fee (e.g., 3000 = 0.3%, 10000 = 1%)
    int24 tickSpacing;   // Tick spacing for the pool
    IHooks hooks;        // Hook contract (address(0) for standard pools)
}
```

**Example:**
```javascript
const buyTime = Date.now() / 1000 + 3600; // 1 hour from now
const sellTime = buyTime + 86400; // 24 hours after buy
const deadline = Date.now() / 1000 + 1800; // 30 min funding window

// PoolKey for a WETH/TOKEN pair on Uniswap V4
const poolKey = {
  currency0: WETH_ADDRESS,    // 0x4200...0006 (lower address)
  currency1: TOKEN_ADDRESS,    // must be higher address
  fee: 10000,                  // 1% fee
  tickSpacing: 200,            // standard tick spacing
  hooks: ethers.ZeroAddress    // no hooks
};

await alpha.create(
  TOKEN_ADDRESS,
  poolKey,
  parseEther("1"), // need 1 ETH
  buyTime,
  sellTime,
  deadline
);
```

### 2. Contributing

```solidity
function join(uint256 tradeId) external payable
```

**Example:**
```javascript
await alpha.join(0, { value: parseEther("0.5") });
```

### 3. Executing Buy

```solidity
function executeBuy(uint256 tradeId, uint128 minAmountOut) external
```

- Anyone can call when `block.timestamp >= buyTime` and threshold met
- Swaps ETH → target token via Uniswap V4 Universal Router

### 4. Executing Sell

```solidity
function executeSell(uint256 tradeId, uint128 minAmountOut) external
```

- Anyone can call when `block.timestamp >= sellTime`
- Swaps target token → ETH via Uniswap V4 Universal Router

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
function getTradeInfo(uint256 tradeId) external view returns (
    address tokenOut,
    uint24 fee,
    uint256 threshold,
    uint256 buyTime,
    uint256 sellTime,
    uint256 deadline,
    uint256 amountBought,
    Status status,          // Funding, Bought, Sold, Expired
    uint256 totalContributed,
    uint256 contributorCount
)
```

## DEX Integration

Alpha uses **Uniswap V4 Universal Router** on Base for all swaps.

**Key addresses (Base mainnet):**
- Universal Router: `0x6ff5693b99212Da76ad316178A184AB56D299B43`
- PoolManager: `0x498581ff718922c3f8e6a244956af099b2652b2b`
- Permit2: `0x000000000022D473030F116dDEE9F6B43aC78BA3`
- WETH: `0x4200000000000000000000000000000000000006`

Works with any Uniswap V4 pool including Clanker-deployed tokens, standard pairs, and pools with custom hooks.

## Example Use Cases

1. **Time-based swing trade**: "Buy DEGEN at 2pm, sell at 2pm tomorrow"
2. **Clanker token play**: "Pool ETH, buy new Clanker token early, sell 24h later"
3. **Announcement play**: "Pool $10k ETH, buy 5 min after announcement, sell 24h later"
4. **Volatility capture**: "Buy during expected dip, sell during expected pump"

## Important Notes

- **Slippage protection via minAmountOut** parameter on executeBuy/executeSell
- **Execution is permissionless** (anyone can trigger buy/sell at the right time)
- **Contributors can't cancel** after contributing (unless threshold not met)
- **Controller is the Alpha contract itself** (not an external address)
- **PoolKey must be correct** for the target token's V4 pool
