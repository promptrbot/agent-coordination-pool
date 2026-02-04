'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseEther, formatEther } from 'viem';
import { useState } from 'react';
import ABI from '../abi.json';

const ACP_ADDRESS = '0x6bD736859470e02f12536131Ae842ad036dE84C4' as const;

export default function Home() {
  const { address } = useAccount();
  const [poolId, setPoolId] = useState('');
  const [contributionAmount, setContributionAmount] = useState('');
  const [createTarget, setCreateTarget] = useState('');
  const [createName, setCreateName] = useState('');

  const { writeContract, data: hash } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  // Read pool count - ALWAYS visible
  const { data: poolCount } = useReadContract({
    address: ACP_ADDRESS,
    abi: ABI,
    functionName: 'poolCount',
  });

  // Read pool details - ALWAYS visible
  const { data: poolData } = useReadContract({
    address: ACP_ADDRESS,
    abi: ABI,
    functionName: 'pools',
    args: poolId ? [BigInt(poolId)] : undefined,
  });

  const createPool = () => {
    if (!createTarget || !createName) return;
    writeContract({
      address: ACP_ADDRESS,
      abi: ABI,
      functionName: 'createPool',
      args: ['0x0000000000000000000000000000000000000000', parseEther(createTarget), createName, 100], // ETH pool with 1% fee
    });
  };

  const contribute = () => {
    if (!poolId || !contributionAmount) return;
    writeContract({
      address: ACP_ADDRESS,
      abi: ABI,
      functionName: 'contributeETH',
      args: [BigInt(poolId)],
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
              {poolData && Array.isArray(poolData) ? formatEther(poolData[1] as bigint) : '0.00'}
            </div>
            <div className="text-gray-600 dark:text-gray-400 font-medium">ETH in Selected Pool</div>
          </div>

          <div className="bg-white dark:bg-gray-800 rounded-xl p-6 shadow-lg">
            <div className="text-4xl font-black text-purple-600 mb-2">1%</div>
            <div className="text-gray-600 dark:text-gray-400 font-medium">Fee Per Pool</div>
          </div>
        </div>

        {/* Pool Explorer - ALWAYS VISIBLE */}
        <div className="bg-white dark:bg-gray-800 rounded-2xl p-8 mb-8 shadow-xl">
          <h2 className="text-2xl font-bold mb-4">Explore Pools</h2>
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
                  <span className="text-gray-600 dark:text-gray-400">Name:</span>
                  <span className="font-bold text-xl">{poolData[4] as string}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-600 dark:text-gray-400">Total Raised:</span>
                  <span className="font-bold text-xl text-green-600">{formatEther(poolData[1] as bigint)} ETH</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-600 dark:text-gray-400">Target:</span>
                  <span className="font-bold text-xl">{formatEther(poolData[2] as bigint)} ETH</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-600 dark:text-gray-400">Status:</span>
                  <span className={`font-bold text-xl ${poolData[3] === 1 ? 'text-green-600' : poolData[3] === 2 ? 'text-blue-600' : 'text-red-600'}`}>
                    {poolData[3] === 1 ? 'Active' : poolData[3] === 2 ? 'Executed' : 'Cancelled'}
                  </span>
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
              <h2 className="text-2xl font-bold mb-6">Create Pool</h2>
              <div className="space-y-4">
                <input
                  type="text"
                  placeholder="Pool Name"
                  value={createName}
                  onChange={(e) => setCreateName(e.target.value)}
                  className="w-full p-4 rounded-lg bg-gray-50 dark:bg-gray-700 border-2 border-gray-200 dark:border-gray-600 focus:border-blue-500 focus:outline-none"
                />
                <input
                  type="text"
                  placeholder="Target (ETH)"
                  value={createTarget}
                  onChange={(e) => setCreateTarget(e.target.value)}
                  className="w-full p-4 rounded-lg bg-gray-50 dark:bg-gray-700 border-2 border-gray-200 dark:border-gray-600 focus:border-blue-500 focus:outline-none"
                />
                <button
                  onClick={createPool}
                  disabled={isConfirming}
                  className="w-full bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700 disabled:from-gray-400 disabled:to-gray-400 text-white font-bold py-4 px-6 rounded-lg transition text-lg shadow-lg"
                >
                  {isConfirming ? 'Creating...' : 'Create Pool'}
                </button>
              </div>
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
