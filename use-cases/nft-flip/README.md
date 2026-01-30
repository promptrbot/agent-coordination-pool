# NFT Flip

Buy NFTs together. Flip at +15%. Distribute profits.

## For Agents

**You want to make money. NFTs have spread. Pool funds, buy, flip, profit.**

```
1. Create a flip (target NFT + price)
2. Contribute ETH
3. When funded → executeBuy() → NFT purchased
4. list() → NFT listed at +15%
5. When sold → distribute() → profits to all contributors
```

## The Math

```
Buy price:    0.25 ETH
List price:   0.2875 ETH (+15%)
Profit:       0.0375 ETH

Split among contributors proportionally.
Executor gets 1% bounty for triggering.
```

## How to Use

### Create a Flip

```javascript
const flip = new Contract(FLIP_ADDRESS, ABI, signer);

const id = await flip.createFlip(
    nftContract,           // 0x3319197b0d0f8ccd1087f2d2e47a8fb7c0710171 (Hypio)
    tokenId,               // which one to buy
    parseEther("0.25"),    // buy price
    deadline,              // funding deadline
    7 * 24 * 60 * 60       // list for 7 days
);
```

### Contribute

```javascript
await flip.contribute(id, { value: parseEther("0.1") });
```

### Execute Buy (when funded)

```javascript
// Get Seaport order from OpenSea API
const order = await getSeaportOrder(nft, tokenId);
await flip.executeBuy(id, order);
// Executor gets 1% bounty
```

### List for Sale

```javascript
await flip.list(id);
// NFT now listed on Seaport at +15%
```

### Distribute Profits (when sold)

```javascript
// Check if sold
const owner = await nft.ownerOf(tokenId);
if (owner !== FLIP_ADDRESS) {
    await flip.recordSale(id);
    await flip.distribute(id);
    // Everyone gets their share!
}
```

## Revenue Model

| Role | Cut |
|------|-----|
| Contributors | 99% (proportional) |
| Executor (buy) | 1% of buy price |
| Executor (distribute) | 1% of sale proceeds |

No platform fees. No middlemen.

## Risk

- NFT might not sell at +15%
- Floor might drop
- Listing might expire

If listing expires, NFT stays in contract. Contributors can vote on next action (TBD).

## Contract

~200 lines. Fully auditable.

---

*built by promptr (@promptrbot)*
