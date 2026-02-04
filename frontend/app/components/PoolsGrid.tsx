'use client';

import { useReadContract } from 'wagmi';
import { useState, useEffect } from 'react';
import PoolCard from './PoolCard';
import ABI from '../../abi.json';

const ACP_ADDRESS = '0x6bD736859470e02f12536131Ae842ad036dE84C4' as const;

interface PoolsGridProps {
  poolCount: bigint | undefined;
}

export default function PoolsGrid({ poolCount }: PoolsGridProps) {
  const [pools, setPools] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!poolCount) return;

    const count = Number(poolCount);
    if (count === 0) return;

    setLoading(true);

    // Fetch info for all pools (limit to first 20 for performance)
    const maxPools = Math.min(count, 20);
    const poolPromises = [];

    for (let i = 0; i < maxPools; i++) {
      // We'll create individual components that fetch their own data
      poolPromises.push(i);
    }

    setPools(poolPromises);
    setLoading(false);
  }, [poolCount]);

  if (!poolCount || Number(poolCount) === 0) {
    return (
      <div className="bg-white dark:bg-gray-800 rounded-2xl p-12 text-center shadow-xl">
        <p className="text-xl text-gray-600 dark:text-gray-400">
          No pools created yet. Be the first!
        </p>
      </div>
    );
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-3xl font-bold">Active Pools</h2>
        <div className="text-sm text-gray-600 dark:text-gray-400">
          Showing {pools.length} of {poolCount.toString()} pools
        </div>
      </div>

      <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
        {pools.map((poolId) => (
          <PoolCardLoader key={poolId} poolId={poolId} />
        ))}
      </div>
    </div>
  );
}

// Component that loads individual pool data
function PoolCardLoader({ poolId }: { poolId: number }) {
  const { data: poolInfo } = useReadContract({
    address: ACP_ADDRESS,
    abi: ABI,
    functionName: 'getPoolInfo',
    args: [BigInt(poolId)],
  });

  const { data: balance } = useReadContract({
    address: ACP_ADDRESS,
    abi: ABI,
    functionName: 'getPoolBalance',
    args: [BigInt(poolId)],
  });

  if (!poolInfo || !Array.isArray(poolInfo)) {
    return (
      <div className="bg-white dark:bg-gray-800 rounded-2xl p-8 shadow-xl animate-pulse">
        <div className="h-32 bg-gray-200 dark:bg-gray-700 rounded"></div>
      </div>
    );
  }

  const [token, controller, totalContributed, contributorCount] = poolInfo;

  // Try to detect wrapper type based on controller address
  // This is a simple heuristic - in production you'd maintain a registry
  const wrapperType = detectWrapperType(controller as string);

  return (
    <PoolCard
      pool={{
        poolId,
        token: token as string,
        controller: controller as string,
        totalContributed: totalContributed as bigint,
        balance: (balance as bigint) || 0n,
        contributorsCount: Number(contributorCount),
        wrapperType,
      }}
    />
  );
}

// Heuristic to detect wrapper type - in production you'd have a registry
function detectWrapperType(controller: string): 'Alpha' | 'Launchpad' | 'NFTFlip' | 'Custom' {
  // For now, return Custom for all
  // In production, you'd check against known wrapper addresses
  return 'Custom';
}
