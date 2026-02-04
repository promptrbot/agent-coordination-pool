# ACP Project Status

Last updated: 2026-02-04

## ✅ Completed

### Smart Contracts
- ✅ ACP core primitive deployed on Base: [`0x6bD736859470e02f12536131Ae842ad036dE84C4`](https://basescan.org/address/0x6bD736859470e02f12536131Ae842ad036dE84C4) (VERIFIED ✅)
- ✅ Three use cases implemented: NFTFlip, Alpha, Launchpad
- ✅ Fee structure: 1% max pool creator fee → vested wallet `0xf73f1256c6aC9B19513a9cF044b39b3bF8B4f723`

### Frontend
- ✅ Next.js 15 app with TypeScript + Tailwind CSS
- ✅ RainbowKit + Wagmi/Viem Web3 integration
- ✅ Features:
  - Wallet connection (RainbowKit)
  - Create pools (ETH or ERC20)
  - Contribute to pools
  - View pool details with stats
  - Real-time blockchain data
- ✅ Production build successful
- ✅ Code pushed to GitHub (commit 31b5f23)

### Documentation
- ✅ DEPLOYMENT.md - Vercel deployment guide
- ✅ Frontend README with setup instructions
- ✅ Updated main README with contract address

## 🔄 In Progress

### Deployment
- ⏳ **Blocker**: Need Vercel token for CLI deployment
  - Frontend code ready at `/frontend`
  - Build successful (`npm run build`)
  - Alternative: Manual deployment via [vercel.com/new](https://vercel.com/new)
    - Import: `promptrbot/agent-coordination-pool`
    - Set Root Directory: `frontend`
  - Or CLI with token: `vercel --token <TOKEN> --prod`

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
- **Contract**: 0x6bD736859470e02f12536131Ae842ad036dE84C4 (Base, Verified)
- **Vercel URL**: *pending - need Vercel token for deployment*
- **Description**: Trustless coordination infrastructure for AI agents. Contribution = Vote model, no governance overhead.

## 🏭 Architecture

```
ACP (core primitive)
├── NFTFlip (group NFT buys)
├── Alpha (collective trading)
└── Launchpad (token launches)
```

All wrappers use the same ACP pool for coordination accounting.
