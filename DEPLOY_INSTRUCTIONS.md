# Frontend Deployment Instructions

## Current Status

✅ Frontend built and ready
✅ Code pushed to GitHub (commit f82b813)
❌ Awaiting Vercel deployment

## Quick Deploy (Recommended)

### Option 1: Vercel Dashboard (5 minutes)
1. Go to [vercel.com/new](https://vercel.com/new)
2. Import `promptrbot/agent-coordination-pool`
3. Set **Root Directory**: `frontend`
4. Click **Deploy**
5. Copy the deployment URL for ClawdKitchen submission

### Option 2: Vercel CLI
```bash
cd ~/projects/agent-coordination-pool/frontend
vercel --token <YOUR_VERCEL_TOKEN> --prod
```

Get token from: [vercel.com/account/tokens](https://vercel.com/account/tokens)

## What's Built

- ✅ Next.js 15 with TypeScript
- ✅ RainbowKit wallet connection
- ✅ Pool creation UI
- ✅ Contribution UI
- ✅ Pool viewing with stats
- ✅ Tailwind CSS styling
- ✅ Production build tested (`npm run build` passes)

## Contract Integration

Uses verified ACP contract:
- **Address**: `0x6bD736859470e02f12536131Ae842ad036dE84C4`
- **Network**: Base
- **BaseScan**: https://basescan.org/address/0x6bD736859470e02f12536131Ae842ad036dE84C4

## After Deployment

1. Copy the Vercel URL (e.g., `https://acp-frontend-xyz.vercel.app`)
2. Update ClawdKitchen submission:
   - project_name: Agent Coordination Pool
   - github_url: https://github.com/promptrbot/agent-coordination-pool
   - vercel_url: <YOUR_VERCEL_URL>
   - contract_address: 0x6bD736859470e02f12536131Ae842ad036dE84C4
3. Test the frontend:
   - Connect wallet
   - Create a test pool
   - Contribute to it
   - View pool details

## Troubleshooting

**Build fails**: Already tested - builds successfully locally
**Missing dependencies**: `npm install` in `frontend/` directory
**Contract not loading**: Check Base RPC is accessible

---

**Ready for deployment - just need Vercel access! 🚀**
