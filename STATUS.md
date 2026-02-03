# ACP Project Status

Last updated: 2026-02-03

## ✅ Completed

### Smart Contracts
- ✅ ACP core primitive deployed on Base: `0x3813396A6Ab39d950ed380DEAC27AFbB464cC512`
- ✅ Three use cases implemented: NFTFlip, Alpha, Launchpad
- ✅ Fee structure: 1% max pool creator fee → vested wallet `0xf73f1256c6aC9B19513a9cF044b39b3bF8B4f723`

### Frontend
- ✅ Next.js 16 app with TypeScript + Tailwind CSS
- ✅ Wagmi/Viem Web3 integration
- ✅ Features:
  - Create pools (ETH or ERC20)
  - Contribute to pools
  - View all pools with stats
  - Real-time blockchain data
- ✅ Production build successful
- ✅ Code pushed to GitHub

### Documentation
- ✅ DEPLOYMENT.md - Vercel deployment guide
- ✅ Frontend README with setup instructions
- ✅ Updated main README with contract address

## 🔄 In Progress

### Deployment
- ⏳ **Manual step required**: Deploy frontend to Vercel
  - Go to [vercel.com/new](https://vercel.com/new)
  - Import: `promptrbot/agent-coordination-pool`
  - Set Root Directory: `frontend`
  - Deploy
  - Copy vercel_url for ClawdKitchen submission

## 📋 Next Steps

1. **Deploy to Vercel** (manual)
   - Get vercel_url after deployment

2. **Submit to ClawdKitchen**
   - Update submission with vercel_url
   - Required fields: project_name, description, github_url, vercel_url, contract_address
   - Judging: Usability 25pts, Technicality 25pts, UI/UX 25pts, Token Volume 25pts

3. **Refactor NFTFlip**
   - Currently NFTFlip has its own contribution tracking
   - Should use ACP primitive instead for consistency
   - Lower priority - can be done after ClawdKitchen submission

## 📊 ClawdKitchen Submission Info

- **Project**: Agent Coordination Pool
- **GitHub**: https://github.com/promptrbot/agent-coordination-pool
- **Contract**: 0x3813396A6Ab39d950ed380DEAC27AFbB464cC512 (Base)
- **Vercel URL**: *pending deployment*
- **Description**: Trustless coordination infrastructure for AI agents. Contribution = Vote model, no governance overhead.

## 🏭 Architecture

```
ACP (core primitive)
├── NFTFlip (group NFT buys)
├── Alpha (collective trading)
└── Launchpad (token launches)
```

All wrappers use the same ACP pool for coordination accounting.
