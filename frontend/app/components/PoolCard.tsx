'use client';

import { formatEther } from 'viem';

interface PoolData {
  poolId: number;
  name?: string;
  token: string;
  controller: string;
  totalContributed: bigint;
  balance: bigint;
  contributorsCount?: number;
  wrapperType?: 'Alpha' | 'Launchpad' | 'NFTFlip' | 'Custom';
}

interface PoolCardProps {
  pool: PoolData;
}

const WRAPPER_INFO = {
  Alpha: {
    color: 'blue',
    icon: '🎯',
    description: 'Collective trading pools',
    skillUrl: 'https://github.com/promptrbot/agent-coordination-pool/blob/main/docs/skills/alpha.md',
  },
  Launchpad: {
    color: 'purple',
    icon: '🚀',
    description: 'Token launch pools',
    skillUrl: 'https://github.com/promptrbot/agent-coordination-pool/blob/main/docs/skills/launchpad.md',
  },
  NFTFlip: {
    color: 'green',
    icon: '🖼️',
    description: 'NFT group purchase pools',
    skillUrl: 'https://github.com/promptrbot/agent-coordination-pool/blob/main/docs/skills/nftflip.md',
  },
  Custom: {
    color: 'gray',
    icon: '⚙️',
    description: 'Custom wrapper contract',
    skillUrl: 'https://github.com/promptrbot/agent-coordination-pool/blob/main/docs/skills/acp-general.md',
  },
};

export default function PoolCard({ pool }: PoolCardProps) {
  const wrapperType = pool.wrapperType || 'Custom';
  const wrapperInfo = WRAPPER_INFO[wrapperType];
  const isETH = pool.token === '0x0000000000000000000000000000000000000000';

  const colorClasses = {
    blue: 'from-blue-500 to-blue-600 border-blue-200 dark:border-blue-800',
    purple: 'from-purple-500 to-purple-600 border-purple-200 dark:border-purple-800',
    green: 'from-green-500 to-green-600 border-green-200 dark:border-green-800',
    gray: 'from-gray-500 to-gray-600 border-gray-200 dark:border-gray-800',
  };

  const bgColorClasses = {
    blue: 'bg-blue-50 dark:bg-blue-900/20',
    purple: 'bg-purple-50 dark:bg-purple-900/20',
    green: 'bg-green-50 dark:bg-green-900/20',
    gray: 'bg-gray-50 dark:bg-gray-900/20',
  };

  return (
    <div className="bg-white dark:bg-gray-800 rounded-2xl shadow-xl overflow-hidden border-2 border-gray-100 dark:border-gray-700 hover:shadow-2xl transition-shadow">
      {/* Header with gradient */}
      <div className={`bg-gradient-to-r ${colorClasses[wrapperInfo.color]} p-6 text-white`}>
        <div className="flex items-start justify-between mb-2">
          <div className="flex items-center gap-3">
            <span className="text-4xl">{wrapperInfo.icon}</span>
            <div>
              <h3 className="text-2xl font-bold">
                {pool.name || `Pool #${pool.poolId}`}
              </h3>
              <p className="text-sm opacity-90">{wrapperType}</p>
            </div>
          </div>
          <div className="bg-white/20 backdrop-blur-sm px-3 py-1 rounded-full text-sm font-mono">
            #{pool.poolId}
          </div>
        </div>
        <p className="text-sm opacity-80">{wrapperInfo.description}</p>
      </div>

      {/* Stats Grid */}
      <div className="p-6 space-y-4">
        <div className="grid grid-cols-2 gap-4">
          {/* Total Contributed */}
          <div className={`${bgColorClasses[wrapperInfo.color]} p-4 rounded-lg`}>
            <div className="text-xs text-gray-600 dark:text-gray-400 mb-1 font-medium">
              Total Pooled
            </div>
            <div className="text-2xl font-black text-gray-900 dark:text-white">
              {formatEther(pool.totalContributed)} {isETH ? 'ETH' : 'Tokens'}
            </div>
          </div>

          {/* Current Balance */}
          <div className={`${bgColorClasses[wrapperInfo.color]} p-4 rounded-lg`}>
            <div className="text-xs text-gray-600 dark:text-gray-400 mb-1 font-medium">
              Current Balance
            </div>
            <div className="text-2xl font-black text-gray-900 dark:text-white">
              {formatEther(pool.balance)} {isETH ? 'ETH' : 'Tokens'}
            </div>
          </div>

          {/* Contributors */}
          {pool.contributorsCount !== undefined && (
            <div className={`${bgColorClasses[wrapperInfo.color]} p-4 rounded-lg`}>
              <div className="text-xs text-gray-600 dark:text-gray-400 mb-1 font-medium">
                Contributors
              </div>
              <div className="text-2xl font-black text-gray-900 dark:text-white">
                {pool.contributorsCount}
              </div>
            </div>
          )}

          {/* Fees Collected (calculated) */}
          <div className={`${bgColorClasses[wrapperInfo.color]} p-4 rounded-lg`}>
            <div className="text-xs text-gray-600 dark:text-gray-400 mb-1 font-medium">
              Est. Fees (1%)
            </div>
            <div className="text-2xl font-black text-gray-900 dark:text-white">
              {formatEther(pool.totalContributed / BigInt(100))} {isETH ? 'ETH' : 'Tokens'}
            </div>
          </div>
        </div>

        {/* Links */}
        <div className="flex gap-3 pt-4 border-t border-gray-200 dark:border-gray-700">
          <a
            href={`https://basescan.org/address/${pool.controller}`}
            target="_blank"
            rel="noopener noreferrer"
            className="flex-1 text-center bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 px-4 py-2 rounded-lg text-sm font-medium transition"
          >
            View Controller ↗
          </a>
          <a
            href={wrapperInfo.skillUrl}
            target="_blank"
            rel="noopener noreferrer"
            className={`flex-1 text-center bg-gradient-to-r ${colorClasses[wrapperInfo.color]} text-white hover:opacity-90 px-4 py-2 rounded-lg text-sm font-medium transition`}
          >
            Usage Guide ↗
          </a>
        </div>

        {/* Token Info */}
        {!isETH && (
          <div className="text-xs text-gray-500 dark:text-gray-400 font-mono pt-2">
            Token: {pool.token.slice(0, 6)}...{pool.token.slice(-4)}
          </div>
        )}
      </div>
    </div>
  );
}
