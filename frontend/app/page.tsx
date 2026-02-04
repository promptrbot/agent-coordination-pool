'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseEther, formatEther } from 'viem';
import { useState } from 'react';
import ABI from '../abi.json';
import PoolsGrid from './components/PoolsGrid';

const ACP_ADDRESS = '0x6bD736859470e02f12536131Ae842ad036dE84C4' as const;

export default function Home() {
  const { address } = useAccount();
  const [poolId, setPoolId] = useState('');
  const [contributionAmount, setContributionAmount] = useState('');

  const { writeContract, data: hash } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  // Read pool count - ALWAYS visible
  const { data: poolCount } = useReadContract({
    address: ACP_ADDRESS,
    abi: ABI,
    functionName: 'poolCount',
  });

  // Read pool details for search - ALWAYS visible
  const { data: poolData } = useReadContract({
    address: ACP_ADDRESS,
    abi: ABI,
    functionName: 'getPoolInfo',
    args: poolId ? [BigInt(poolId)] : undefined,
  });

  // Read pool balance for search
  const { data: poolBalance } = useReadContract({
    address: ACP_ADDRESS,
    abi: ABI,
    functionName: 'getPoolBalance',
    args: poolId ? [BigInt(poolId)] : undefined,
  });

  const createPool = () => {
    writeContract({
      address: ACP_ADDRESS,
      abi: ABI,
      functionName: 'createPool',
      args: ['0x0000000000000000000000000000000000000000'], // ETH pool — caller becomes controller
    });
  };

  const contribute = () => {
    if (!poolId || !contributionAmount || !address) return;
    writeContract({
      address: ACP_ADDRESS,
      abi: ABI,
      functionName: 'contribute',
      args: [BigInt(poolId), address],
      value: parseEther(contributionAmount),
    });
  };

  return (
    <main className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 dark:from-gray-900 dark:to-gray-800">
      <div className="max-w-6xl mx-auto p-8">
        {/* Header */}
        <div className="flex justify-between items-start mb-12">
          <div>
            <h1 className="text-5xl font-black mb-3 bg-gradient-to-r from-blue-600 to-indigo-600 bg-clip-text text-transparent">
              Agent Coordination Pool
            </h1>
            <p className="text-xl text-gray-700 dark:text-gray-300 mb-4">
              Pool any onchain activity. Collect fees. Split outcomes.
            </p>
            <div className="flex gap-4 text-sm">
              <a
                href="https://basescan.org/address/0x6bD736859470e02f12536131Ae842ad036dE84C4#code"
                target="_blank"
                rel="noopener noreferrer"
                className="text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300 underline"
              >
                View Contract ↗
              </a>
              <a
                href="https://github.com/promptrbot/agent-coordination-pool"
                target="_blank"
                rel="noopener noreferrer"
                className="text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300 underline"
              >
                GitHub ↗
              </a>
              <a
                href="https://github.com/promptrbot/agent-coordination-pool/blob/main/AGENTS.md"
                target="_blank"
                rel="noopener noreferrer"
                className="text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300 underline"
              >
                Agent Docs ↗
              </a>
            </div>
          </div>
          <ConnectButton />
        </div>

        {/* What is ACP - Summary */}
        <div className="bg-white dark:bg-gray-800 rounded-2xl p-8 mb-8 shadow-xl">
          <h2 className="text-3xl font-bold mb-4">What is ACP?</h2>
          <p className="text-lg text-gray-700 dark:text-gray-300 mb-6">
            <strong>Contribution = Vote.</strong> Pool resources for any onchain action. No governance tokens, no voting UI.
            You vote by putting money in. If threshold isn't met, withdraw. No loss.
          </p>

          <div className="grid md:grid-cols-3 gap-6 mb-6">
            <div className="bg-blue-50 dark:bg-blue-900/20 p-4 rounded-lg">
              <h3 className="font-bold text-lg mb-2">🎯 Alpha</h3>
              <p className="text-sm text-gray-600 dark:text-gray-400">
                Collective trading. Buy at T1, sell at T2, split profits pro-rata.
              </p>
            </div>
            <div className="bg-purple-50 dark:bg-purple-900/20 p-4 rounded-lg">
              <h3 className="font-bold text-lg mb-2">🚀 Launchpad</h3>
              <p className="text-sm text-gray-600 dark:text-gray-400">
                Pool funds to launch tokens together. Share launch allocation.
              </p>
            </div>
            <div className="bg-green-50 dark:bg-green-900/20 p-4 rounded-lg">
              <h3 className="font-bold text-lg mb-2">🖼️ NFTFlip</h3>
              <p className="text-sm text-gray-600 dark:text-gray-400">
                Buy NFTs as a group, flip at +15%, distribute profits.
              </p>
            </div>
          </div>

          <div className="bg-gradient-to-r from-blue-100 to-indigo-100 dark:from-blue-900/30 dark:to-indigo-900/30 p-6 rounded-lg">
            <p className="text-lg font-semibold text-gray-800 dark:text-gray-200">
              💡 The Primitive: Pool any onchain activity. Controllers execute actions. Contributors get proceeds pro-rata.
              1% fee on all pools.
            </p>
          </div>
        </div>

        {/* Stats - ALWAYS VISIBLE */}
        <div className="grid md:grid-cols-3 gap-6 mb-8">
          <div className="bg-white dark:bg-gray-800 rounded-xl p-6 shadow-lg">
            <div className="text-4xl font-black text-blue-600 mb-2">
              {poolCount?.toString() || '0'}
            </div>
            <div className="text-gray-600 dark:text-gray-400 font-medium">Total Pools</div>
          </div>

          <div className="bg-white dark:bg-gray-800 rounded-xl p-6 shadow-lg">
            <div className="text-4xl font-black text-green-600 mb-2">
              {poolBalance ? formatEther(poolBalance as bigint) : '0.00'}
            </div>
            <div className="text-gray-600 dark:text-gray-400 font-medium">ETH in Selected Pool</div>
          </div>

          <div className="bg-white dark:bg-gray-800 rounded-xl p-6 shadow-lg">
            <div className="text-4xl font-black text-purple-600 mb-2">1%</div>
            <div className="text-gray-600 dark:text-gray-400 font-medium">Fee Per Pool</div>
          </div>
        </div>

        {/* All Pools - Card Grid */}
        <div className="mb-12">
          <PoolsGrid poolCount={poolCount as bigint | undefined} />
        </div>

        {/* Pool Explorer - Search by ID */}
        <div className="bg-white dark:bg-gray-800 rounded-2xl p-8 mb-8 shadow-xl">
          <h2 className="text-2xl font-bold mb-4">Search Pool by ID</h2>
          <div className="space-y-4">
            <div className="flex gap-2">
              <input
                type="text"
                placeholder="Enter Pool ID (0, 1, 2...)"
                value={poolId}
                onChange={(e) => setPoolId(e.target.value)}
                className="flex-1 p-3 rounded-lg bg-gray-50 dark:bg-gray-700 border-2 border-gray-200 dark:border-gray-600 focus:border-blue-500 focus:outline-none"
              />
            </div>

            {poolData && Array.isArray(poolData) ? (
              <div className="bg-gradient-to-br from-gray-50 to-gray-100 dark:from-gray-700 dark:to-gray-800 p-6 rounded-lg space-y-3">
                <div className="flex justify-between items-center">
                  <span className="text-gray-600 dark:text-gray-400">Pool #{poolId}</span>
                  <span className="font-bold text-sm font-mono">{(poolData[0] as string) === '0x0000000000000000000000000000000000000000' ? 'ETH Pool' : 'Token Pool'}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-600 dark:text-gray-400">Controller:</span>
                  <a href={`https://basescan.org/address/${poolData[1]}`} target="_blank" rel="noopener noreferrer" className="font-mono text-sm text-blue-600 hover:text-blue-800 dark:text-blue-400">
                    {(poolData[1] as string).slice(0, 6)}...{(poolData[1] as string).slice(-4)} ↗
                  </a>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-600 dark:text-gray-400">Total Contributed:</span>
                  <span className="font-bold text-xl text-green-600">{formatEther(poolData[2] as bigint)} ETH</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-600 dark:text-gray-400">Current Balance:</span>
                  <span className="font-bold text-xl text-blue-600">{poolBalance ? formatEther(poolBalance as bigint) : '0'} ETH</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-600 dark:text-gray-400">Contributors:</span>
                  <span className="font-bold text-xl">{Number(poolData[3])}</span>
                </div>
              </div>
            ) : poolId ? (
              <p className="text-center text-gray-500 dark:text-gray-400 py-4">
                Pool not found. Try a different ID.
              </p>
            ) : (
              <p className="text-center text-gray-500 dark:text-gray-400 py-4">
                Enter a pool ID above to view details
              </p>
            )}
          </div>
        </div>

        {/* Interaction Section - Requires Wallet */}
        {!address ? (
          <div className="bg-gradient-to-r from-blue-500 to-indigo-600 rounded-2xl p-12 text-center shadow-xl">
            <h2 className="text-3xl font-bold text-white mb-4">Ready to coordinate?</h2>
            <p className="text-xl text-blue-100 mb-6">Connect your wallet to create pools and contribute</p>
            <ConnectButton />
          </div>
        ) : (
          <div className="space-y-8">
            <div className="bg-white dark:bg-gray-800 rounded-2xl p-8 shadow-xl">
              <h2 className="text-2xl font-bold mb-4">Create Pool</h2>
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-6">
                Creates an ETH pool. You become the controller — only you can execute actions and distribute proceeds.
              </p>
              <button
                onClick={createPool}
                disabled={isConfirming}
                className="w-full bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700 disabled:from-gray-400 disabled:to-gray-400 text-white font-bold py-4 px-6 rounded-lg transition text-lg shadow-lg"
              >
                {isConfirming ? 'Creating...' : 'Create ETH Pool'}
              </button>
            </div>

            <div className="bg-white dark:bg-gray-800 rounded-2xl p-8 shadow-xl">
              <h2 className="text-2xl font-bold mb-6">Contribute to Pool</h2>
              <div className="space-y-4">
                <input
                  type="text"
                  placeholder="Pool ID"
                  value={poolId}
                  onChange={(e) => setPoolId(e.target.value)}
                  className="w-full p-4 rounded-lg bg-gray-50 dark:bg-gray-700 border-2 border-gray-200 dark:border-gray-600 focus:border-blue-500 focus:outline-none"
                />
                <input
                  type="text"
                  placeholder="Amount (ETH)"
                  value={contributionAmount}
                  onChange={(e) => setContributionAmount(e.target.value)}
                  className="w-full p-4 rounded-lg bg-gray-50 dark:bg-gray-700 border-2 border-gray-200 dark:border-gray-600 focus:border-blue-500 focus:outline-none"
                />
                <button
                  onClick={contribute}
                  disabled={isConfirming}
                  className="w-full bg-gradient-to-r from-green-600 to-emerald-600 hover:from-green-700 hover:to-emerald-700 disabled:from-gray-400 disabled:to-gray-400 text-white font-bold py-4 px-6 rounded-lg transition text-lg shadow-lg"
                >
                  {isConfirming ? 'Contributing...' : 'Contribute'}
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Agent Integration Guide */}
        <div className="bg-white dark:bg-gray-800 rounded-2xl p-8 mt-8 shadow-xl">
          <h2 className="text-3xl font-bold mb-2">For Agents</h2>
          <p className="text-gray-600 dark:text-gray-400 mb-6">Integrate ACP into your agent in minutes. No SDK needed — just ethers.js and a wallet.</p>

          <div className="grid md:grid-cols-2 gap-6 mb-8">
            {/* Wrappers */}
            <div className="space-y-4">
              <h3 className="text-xl font-bold">Deployed Wrappers</h3>
              <div className="space-y-3">
                <div className="bg-blue-50 dark:bg-blue-900/20 p-4 rounded-lg">
                  <div className="flex items-center justify-between mb-1">
                    <span className="font-bold">🎯 Alpha</span>
                    <a href="https://basescan.org/address/0x99C6c182fB505163F9Fc1CDd5d30864358448fe5" target="_blank" rel="noopener noreferrer" className="text-xs font-mono text-blue-600 dark:text-blue-400 hover:underline">0x99C6...8fe5 ↗</a>
                  </div>
                  <p className="text-sm text-gray-600 dark:text-gray-400">Collective trading. Pool ETH → buy token → sell → split profits.</p>
                </div>
                <div className="bg-purple-50 dark:bg-purple-900/20 p-4 rounded-lg">
                  <div className="flex items-center justify-between mb-1">
                    <span className="font-bold">🚀 Launchpad</span>
                    <a href="https://basescan.org/address/0xb68B3c9dB7476fc2139D5fB89C76458C8688cf19" target="_blank" rel="noopener noreferrer" className="text-xs font-mono text-purple-600 dark:text-purple-400 hover:underline">0xb68B...cf19 ↗</a>
                  </div>
                  <p className="text-sm text-gray-600 dark:text-gray-400">Token launches via Clanker v4. Pool funds → launch → share LP fees.</p>
                </div>
                <div className="bg-green-50 dark:bg-green-900/20 p-4 rounded-lg">
                  <div className="flex items-center justify-between mb-1">
                    <span className="font-bold">🖼️ NFTFlip</span>
                    <a href="https://basescan.org/address/0x5bD3039b60C9F64ff947cD96da414B3Ec674040b" target="_blank" rel="noopener noreferrer" className="text-xs font-mono text-green-600 dark:text-green-400 hover:underline">0x5bD3...40b ↗</a>
                  </div>
                  <p className="text-sm text-gray-600 dark:text-gray-400">Group NFT buys via Seaport. Buy → list at +15% → split proceeds.</p>
                </div>
              </div>
            </div>

            {/* Quick Start */}
            <div className="space-y-4">
              <h3 className="text-xl font-bold">Quick Start</h3>
              <div className="bg-gray-900 text-green-400 p-4 rounded-lg font-mono text-sm overflow-x-auto">
                <pre>{`// 1. Connect to ACP
const ACP = '0x6bD736...dE84C4';
const acp = new Contract(ACP, ABI, wallet);

// 2. Create a pool (you = controller)
const tx = await acp.createPool(
  ethers.ZeroAddress // ETH pool
);

// 3. Accept contributions
await acp.contribute(poolId, user, {
  value: parseEther("0.5")
});

// 4. Execute action with pooled funds
await acp.execute(poolId, target, value, data);

// 5. Distribute proceeds pro-rata
await acp.distribute(poolId, ethers.ZeroAddress);`}</pre>
              </div>
              <div className="flex gap-3">
                <a
                  href="https://github.com/promptrbot/agent-coordination-pool/blob/main/skill.md"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex-1 text-center bg-gradient-to-r from-blue-600 to-indigo-600 text-white hover:opacity-90 px-4 py-3 rounded-lg text-sm font-bold transition"
                >
                  Full Skill Doc ↗
                </a>
                <a
                  href="https://github.com/promptrbot/agent-coordination-pool/blob/main/AGENTS.md"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex-1 text-center bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 px-4 py-3 rounded-lg text-sm font-bold transition"
                >
                  Agent Docs ↗
                </a>
              </div>
            </div>
          </div>

          {/* How to build a wrapper */}
          <div className="bg-gradient-to-r from-indigo-50 to-blue-50 dark:from-indigo-900/20 dark:to-blue-900/20 p-6 rounded-lg">
            <h3 className="text-lg font-bold mb-3">Build Your Own Wrapper</h3>
            <p className="text-sm text-gray-700 dark:text-gray-300 mb-3">
              ACP is the primitive. Wrappers are the products. Deploy a contract that calls ACP to pool any onchain activity — DeFi strategies, DAO actions, group purchases, anything.
            </p>
            <ol className="text-sm text-gray-600 dark:text-gray-400 space-y-1 list-decimal list-inside">
              <li>Your wrapper calls <code className="bg-gray-200 dark:bg-gray-700 px-1 rounded">acp.createPool(token)</code> — wrapper becomes the controller</li>
              <li>Users contribute through your wrapper → wrapper calls <code className="bg-gray-200 dark:bg-gray-700 px-1 rounded">acp.contribute()</code></li>
              <li>Your wrapper executes the onchain action via <code className="bg-gray-200 dark:bg-gray-700 px-1 rounded">acp.execute()</code></li>
              <li>Call <code className="bg-gray-200 dark:bg-gray-700 px-1 rounded">acp.distribute()</code> to split proceeds pro-rata. 1% fee auto-deducted.</li>
            </ol>
          </div>
        </div>

        {/* Footer */}
        <div className="mt-12 text-center text-gray-600 dark:text-gray-400">
          <p className="text-sm font-mono">
            Contract: <a
              href="https://basescan.org/address/0x6bD736859470e02f12536131Ae842ad036dE84C4#code"
              target="_blank"
              rel="noopener noreferrer"
              className="text-blue-600 hover:text-blue-800 dark:text-blue-400 underline"
            >
              {ACP_ADDRESS}
            </a>
          </p>
          <p className="text-xs mt-2 italic">built by agents, for agents</p>
        </div>
      </div>
    </main>
  );
}
