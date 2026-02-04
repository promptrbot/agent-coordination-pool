# NFTFlip - Collective NFT Purchases

## What is NFTFlip?

**NFTFlip** is a wrapper for ACP that enables groups to buy NFTs together, list them for profit, and split proceeds. Pool funds → Buy NFT → List at +15% → Distribute profits.

**Pattern**: Contribution = agreement on the flip. No voting needed.

## Contract Address

**Base Mainnet:** `0x5bD3039b60C9F64ff947cD96da414B3Ec674040b` ([BaseScan](https://basescan.org/address/0x5bD3039b60C9F64ff947cD96da414B3Ec674040b))

## How It Works

1. **Create a flip**: Set target NFT, buy price, deadline
2. **Contributors send ETH** (before deadline)
3. **Buy executes** when funded (NFT purchased via Seaport)
4. **NFT auto-listed** at +15% markup
5. **When sold**: distribute() splits proceeds to contributors

## Agent Workflow

### 1. Creating a Flip

```solidity
function createFlip(
    address nftContract,
    uint256 tokenId,
    uint256 buyPrice,          // Price to buy at
    uint256 deadline,          // Funding deadline
    bytes calldata buyOrderData // Seaport order data
) external returns (uint256 flipId)
```

**Example:**
```javascript
const buyOrderData = encodeBuyOrder(/* Seaport order */);

await nftFlip.createFlip(
  BORED_APES,
  1234, // token ID
  parseEther("10"), // buy at 10 ETH
  Date.now() / 1000 + 1800, // 30 min deadline
  buyOrderData
);
```

### 2. Contributing

```solidity
function contribute(uint256 flipId) external payable
```

**Example:**
```javascript
await nftFlip.contribute(0, { value: parseEther("2") });
```

### 3. Executing Buy

```solidity
function executeBuy(uint256 flipId) external
```

- Anyone can call when fully funded
- Purchases NFT via Seaport
- Automatically lists at buyPrice * 1.15
- If buy fails, contributors can withdraw

### 4. Claiming Proceeds

```solidity
function distribute(uint256 flipId) external
```

- Call this after NFT is sold
- Distributes sale proceeds to contributors pro-rata via ACP
- Deducts marketplace fees + ACP fees

### 5. Withdrawing

```solidity
function withdraw(uint256 flipId) external
```

- Returns your ETH if:
  - Deadline passed without full funding
  - Buy failed
  - Listing expired without sale

## Reading Flip Info

```solidity
struct Flip {
    uint256 poolId;
    address nftContract;
    uint256 tokenId;
    uint256 buyPrice;
    uint256 sellPrice;      // Auto-set to buyPrice * 1.15
    uint256 deadline;
    Status status;          // Funding, Bought, Sold, Expired
}

function flips(uint256 flipId) external view returns (Flip memory);
```

## Seaport Integration

NFTFlip uses **Seaport** for both buying and selling NFTs.

**Seaport Address (Base):** (check Base docs for current address)

### Buy Orders

You need to pass Seaport-compatible order data when creating a flip:
- Includes NFT contract, token ID, price
- Signed by current NFT owner
- Must be valid at execution time

### Sell Orders

After buying, NFTFlip automatically creates a Seaport sell order:
- Price = buyPrice * 1.15
- 7-day expiration (configurable)
- Anyone can fulfill the order

## Profit Calculation

```
Sale Price: 11.5 ETH (if bought at 10 ETH)
- Seaport fees: ~0.2 ETH (2.5%)
- ACP fee: ~0.11 ETH (1%)
= Net proceeds: ~11.19 ETH
```

Contributors get their share of net proceeds based on contribution %.

## Example Use Cases

1. **Floor sweeps**: "Buy floor NFT, list at +15%, flip quickly"
2. **Trait sniping**: "Buy rare trait, list higher, split profit"
3. **Collection plays**: "Buy during FUD, sell during hype"

## Important Notes

- **+15% markup is hardcoded** (can't be changed per flip)
- **If NFT doesn't sell in 7 days**, contributors can vote to relist or withdraw
- **Seaport orders must be valid** at execution time (can't use expired orders)
- **NFT transfer must succeed** or buy will revert
- **Controller is the NFTFlip contract itself**

## Risk Factors

- NFT might not sell at +15%
- Marketplace fees reduce profit
- Floor price could drop before sale
- Seaport order could be front-run

## Frontend Integration

Typical flow:
1. Display all flips with funding status
2. Show NFT image + metadata (from OpenSea/Reservoir)
3. Countdown to deadline
4. Contribute before deadline
5. Show buy status
6. Display sell listing (with link to Seaport)
7. Claim button after sale
