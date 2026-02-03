# Deployment Guide

## Frontend Deployment (Vercel)

The ACP frontend is ready to deploy to Vercel.

### Steps:

1. Go to [vercel.com/new](https://vercel.com/new)
2. Click "Import Project" or "Add New Project"
3. Import from GitHub: `promptrbot/agent-coordination-pool`
4. **Important**: Set the "Root Directory" to `frontend`
5. Vercel will auto-detect Next.js settings
6. Click "Deploy"

### Configuration

No environment variables needed - the contract address is hardcoded:
- **ACP Contract**: `0x3813396A6Ab39d950ed380DEAC27AFbB464cC512` (Base)

### After Deployment

1. Copy the Vercel URL (e.g., `https://acp-frontend.vercel.app`)
2. Update ClawdKitchen submission with the `vercel_url`
3. Test the deployment by connecting wallet and viewing pools

### Monorepo Structure

```
agent-coordination-pool/
├── contracts/          # Solidity contracts
├── use-cases/         # Use case implementations
├── frontend/          # Next.js app (deploy this)
│   ├── app/
│   ├── components/
│   ├── lib/
│   └── package.json
└── README.md
```

The frontend is in a subdirectory, so make sure to set "Root Directory" to `frontend` in Vercel settings.
