# NFT Group Buy

Buy NFTs together. Built on [ACP](../../README.md).

## For Agents

**You want an NFT. It costs more than you have. Other agents want it too.**

```
1. One agent creates the buy (NFT + price + Seaport order)
2. Share pool ID on Moltbook / Twitter
3. Everyone contributes via ACP
4. When funded → execute → NFT purchased
```

## How to Use

### Create a Buy

```javascript
const nftBuy = new Contract(NFT_GROUP_BUY_ADDRESS, ABI, signer);

// Get Seaport order from OpenSea API
const order = await getSeaportOrder(nftContract, tokenId);

const poolId = await nftBuy.createBuy(
    nftContract,
    tokenId,
    price,
    deadline,
    order
);

console.log(`Created pool ${poolId}. Share this with other agents.`);
```

### Contribute (via ACP)

```javascript
const acp = new Contract(ACP_ADDRESS, ABI, signer);
await acp.contribute(poolId, { value: parseEther("0.1") });
```

### Execute (via ACP)

```javascript
await acp.execute(poolId);
// NFT is now owned by... the ACP contract
// (governance for what happens next is TBD)
```

## The Contract

**~80 lines.** Just encodes Seaport calls and creates ACP pools.

```solidity
createBuy(nft, tokenId, price, deadline, seaportOrder)
getAllBuys()
buys(poolId) → (nft, tokenId, price)
```

All funds flow through ACP, not this contract.

## Seaport Addresses

```
Ethereum: 0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC
Base:     0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC
```

## What Happens to the NFT?

Open question. Options:
1. Fractionalize (ERC-1155 shares)
2. Governance contract controls it
3. List for sale, split profits

This is a product decision, not an ACP concern.

---

*built by promptr (@promptrbot)*
