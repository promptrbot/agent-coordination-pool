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

  // Read pool count
  const { data: poolCount } = useReadContract({
    address: ACP_ADDRESS,
    abi: ABI,
    functionName: 'poolCount',
  });

  // Read pool details
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
    <main className="min-h-screen p-8">
      <div className="max-w-4xl mx-auto">
        <div className="flex justify-between items-center mb-8">
          <div>
            <h1 className="text-4xl font-bold mb-2">Agent Coordination Pool</h1>
            <p className="text-gray-600 dark:text-gray-400">Trustless coordination on Base</p>
          </div>
          <ConnectButton />
        </div>

        {!address ? (
          <div className="text-center py-16">
            <p className="text-xl text-gray-600 dark:text-gray-400">Connect your wallet to interact with pools</p>
          </div>
        ) : (
          <div className="space-y-8">
            <div className="bg-gray-100 dark:bg-gray-800 p-6 rounded-lg">
              <h2 className="text-2xl font-bold mb-4">Create Pool</h2>
              <div className="space-y-4">
                <input
                  type="text"
                  placeholder="Pool Name"
                  value={createName}
                  onChange={(e) => setCreateName(e.target.value)}
                  className="w-full p-3 rounded bg-white dark:bg-gray-700 border border-gray-300 dark:border-gray-600"
                />
                <input
                  type="text"
                  placeholder="Target (ETH)"
                  value={createTarget}
                  onChange={(e) => setCreateTarget(e.target.value)}
                  className="w-full p-3 rounded bg-white dark:bg-gray-700 border border-gray-300 dark:border-gray-600"
                />
                <button
                  onClick={createPool}
                  disabled={isConfirming}
                  className="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white font-bold py-3 px-6 rounded transition"
                >
                  {isConfirming ? 'Creating...' : 'Create Pool'}
                </button>
              </div>
            </div>

            <div className="bg-gray-100 dark:bg-gray-800 p-6 rounded-lg">
              <h2 className="text-2xl font-bold mb-4">Contribute to Pool</h2>
              <div className="space-y-4">
                <input
                  type="text"
                  placeholder="Pool ID"
                  value={poolId}
                  onChange={(e) => setPoolId(e.target.value)}
                  className="w-full p-3 rounded bg-white dark:bg-gray-700 border border-gray-300 dark:border-gray-600"
                />
                <input
                  type="text"
                  placeholder="Amount (ETH)"
                  value={contributionAmount}
                  onChange={(e) => setContributionAmount(e.target.value)}
                  className="w-full p-3 rounded bg-white dark:bg-gray-700 border border-gray-300 dark:border-gray-600"
                />
                <button
                  onClick={contribute}
                  disabled={isConfirming}
                  className="w-full bg-green-600 hover:bg-green-700 disabled:bg-gray-400 text-white font-bold py-3 px-6 rounded transition"
                >
                  {isConfirming ? 'Contributing...' : 'Contribute'}
                </button>
              </div>
            </div>

            {poolData && Array.isArray(poolData) ? (
              <div className="bg-gray-100 dark:bg-gray-800 p-6 rounded-lg">
                <h2 className="text-2xl font-bold mb-4">Pool Details</h2>
                <div className="space-y-2">
                  <p><strong>Name:</strong> {poolData[4] as string}</p>
                  <p><strong>Total Raised:</strong> {formatEther(poolData[1] as bigint)} ETH</p>
                  <p><strong>Target:</strong> {formatEther(poolData[2] as bigint)} ETH</p>
                  <p><strong>Status:</strong> {poolData[3] === 1 ? 'Active' : poolData[3] === 2 ? 'Executed' : 'Cancelled'}</p>
                </div>
              </div>
            ) : null}

            <div className="text-center text-gray-600 dark:text-gray-400">
              <p>Total Pools: {poolCount?.toString() || '0'}</p>
              <p className="text-sm mt-2">Contract: {ACP_ADDRESS}</p>
            </div>
          </div>
        )}
      </div>
    </main>
  );
}
