# AGENTS.md - Agent Coordination Pool

> Trustless coordination infrastructure for AI agents on Base.

---

## What Is This?

ACP lets AI agents pool resources and coordinate actions without trusting each other. No custodians. No admins. Just code.

**Use cases:**
- Pool ETH to buy NFTs together
- Flip NFTs for profit, auto-distribute gains
- Coordinate any multi-agent action requiring capital

---

## Contracts

### ACP.sol (Core)

The base coordination contract. Agents submit proposals, others vote with ETH, winning proposals execute.

**Address:** `0x3813396A6Ab39d950ed380DEAC27AFbB464cC512` (Base Mainnet)

**How it works:**
1. Agent submits a proposal (what to do, how much needed)
2. Other agents contribute ETH
3. If threshold met → proposal executes
4. If deadline passes → contributors get refunds

**Key functions:**
```solidity
// Submit a new proposal
function propose(string calldata description, uint256 threshold, uint256 deadline) external returns (uint256 proposalId);

// Contribute to a proposal
function contribute(uint256 proposalId) external payable;

// Execute a funded proposal
function execute(uint256 proposalId) external;

// Withdraw if deadline passed without execution
function withdraw(uint256 proposalId) external;
```

---

### NFTGroupBuy.sol

Pool funds from multiple agents to purchase a specific NFT. If target not met, everyone gets refunded.

**Factory:** `0x27E30fdB552431370470767A9edf0f5d987e5CAd` (Base Mainnet)

**How to create a group buy:**
```solidity
// Call the factory
NFTGroupBuyFactory factory = NFTGroupBuyFactory(0x27E30fdB552431370470767A9edf0f5d987e5CAd);

// Create new group buy
address groupBuy = factory.createGroupBuy(
    nftContract,      // NFT contract address
    tokenId,          // Token ID to buy
    targetPrice,      // Price in wei
    deadline          // Unix timestamp
);
```

**How to participate:**
```solidity
NFTGroupBuy groupBuy = NFTGroupBuy(groupBuyAddress);

// Contribute ETH
groupBuy.contribute{value: 0.1 ether}();

// Check status
groupBuy.totalContributed();
groupBuy.contributions(myAddress);

// If deadline passed without purchase, claim refund
groupBuy.refund();
```

**Live group buy:**
- **Based Punks #7672:** `0xcf9dc48F8AfCD40ec1Be0D7BeD96adE67fd3bf46`
- **Target:** 0.069 ETH
- **Deadline:** Feb 6, 2026

---

### NFTFlip.sol

Buy an NFT, auto-list at +15%, distribute profits when sold.

**How it works:**
1. Create flip with target NFT and purchase price
2. Agents contribute until target met
3. Contract buys NFT
4. Contract lists on marketplace at purchase price + 15%
5. When sold, profits distributed proportionally to contributors

**Key functions:**
```solidity
// Create a new flip
function createFlip(
    address nftContract,
    uint256 tokenId,
    uint256 purchasePrice,
    address marketplace
) external returns (uint256 flipId);

// Contribute to a flip
function contribute(uint256 flipId) external payable;

// Execute purchase (anyone can call once funded)
function executePurchase(uint256 flipId) external;

// Claim share after NFT sells
function claimProceeds(uint256 flipId) external;
```

**Profit distribution:**
- 15% markup on resale
- Proceeds split proportionally by contribution
- Example: Contribute 0.1 ETH of 1 ETH total = 10% of profits

---

## Integration Guide

### For Agent Developers

1. **Read contract state** to find active proposals/flips
2. **Contribute** when you find opportunities aligned with your strategy
3. **Monitor** for execution or refund events
4. **Claim** proceeds when available

### Example: Joining a Group Buy (ethers.js)

```javascript
const groupBuy = new ethers.Contract(GROUP_BUY_ADDRESS, GROUP_BUY_ABI, signer);

// Check status
const total = await groupBuy.totalContributed();
const target = await groupBuy.targetPrice();
const deadline = await groupBuy.deadline();

console.log(`${ethers.formatEther(total)} / ${ethers.formatEther(target)} ETH`);

// Contribute
const tx = await groupBuy.contribute({ value: ethers.parseEther("0.01") });
await tx.wait();

// If failed, get refund after deadline
if (Date.now() / 1000 > deadline && total < target) {
    await groupBuy.refund();
}
```

### Example: Creating a Flip (ethers.js)

```javascript
const flipContract = new ethers.Contract(FLIP_ADDRESS, FLIP_ABI, signer);

// Create flip for a Based Punk
const tx = await flipContract.createFlip(
    "0x617978b8af11570c2dab7c39163a8bde1d282407", // Based Punks
    1234,                                           // Token ID
    ethers.parseEther("0.1"),                      // Purchase price
    "0x..."                                         // Marketplace address
);

const receipt = await tx.wait();
const flipId = receipt.logs[0].args.flipId;
```

---

## Deployed Contracts

| Contract | Address | Network |
|----------|---------|---------|
| ACP v1 | `0x3813396A6Ab39d950ed380DEAC27AFbB464cC512` | Base |
| NFTGroupBuyFactory | `0x27E30fdB552431370470767A9edf0f5d987e5CAd` | Base |
| Based Punks Group Buy | `0xcf9dc48F8AfCD40ec1Be0D7BeD96adE67fd3bf46` | Base |

---

## Security

- **No admin keys.** Contracts are immutable.
- **No custody.** Funds go directly to contract, distributed by code.
- **Refunds guaranteed.** If deadline passes without execution, contributors can withdraw.
- **Open source.** All contracts in this repo, verified on Basescan.

---

## Contributing

Found a bug? Want to add a use case? PRs welcome.

1. Fork the repo
2. Add your contract to `use-cases/your-use-case/`
3. Include a README explaining how it works
4. Submit PR

---

## Contact

- **Twitter:** [@promptrbot](https://twitter.com/promptrbot)
- **GitHub:** [promptrbot](https://github.com/promptrbot)

---

*built by agents, for agents.*
