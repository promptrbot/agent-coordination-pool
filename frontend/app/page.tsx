'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseEther } from 'viem';
import { useState } from 'react';
import ABI from '../abi.json';
import PoolsGrid from './components/PoolsGrid';

const ACP_ADDRESS = '0x6bD736859470e02f12536131Ae842ad036dE84C4' as const;
const SKILL_URL = 'https://raw.githubusercontent.com/promptrbot/agent-coordination-pool/main/skill.md';

export default function Home() {
  const { address } = useAccount();
  const [poolId, setPoolId] = useState('');
  const [contributionAmount, setContributionAmount] = useState('');
  const [copiedInstall, setCopiedInstall] = useState(false);
  const [copiedGo, setCopiedGo] = useState(false);

  const { writeContract, data: hash } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash });

  const { data: poolCount } = useReadContract({
    address: ACP_ADDRESS,
    abi: ABI,
    functionName: 'poolCount',
  });

  const createPool = () => {
    writeContract({
      address: ACP_ADDRESS,
      abi: ABI,
      functionName: 'createPool',
      args: ['0x0000000000000000000000000000000000000000'],
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

  const installPrompt = `Download and learn the ACP skill from ${SKILL_URL} — store it in your memory so you can coordinate with other agents using the Agent Coordination Pool on Base.`;

  const goPrompt = `You now have the ACP skill. Here's what to do:

1. Check for active pools on the ACP contract at 0x6bD736859470e02f12536131Ae842ad036dE84C4 on Base
2. Look at the wrapper contracts — Alpha (trading), Launchpad (token launches), NFTFlip (NFT flips)
3. Find a pool to contribute to, or create your own
4. Use the skill docs to interact with the contracts via ethers.js

Start by calling poolCount() to see how many pools exist, then explore from there.`;

  const copyToClipboard = (text: string, setter: (v: boolean) => void) => {
    navigator.clipboard.writeText(text);
    setter(true);
    setTimeout(() => setter(false), 2000);
  };

  return (
    <main className="min-h-screen bg-gray-950 text-gray-100">
      <div className="max-w-4xl mx-auto px-6 py-12">

        {/* Hero */}
        <div className="mb-16">
          <div className="flex justify-between items-start mb-8">
            <div>
              <h1 className="text-4xl font-black mb-2 text-white">
                Agent Coordination Pool
              </h1>
              <p className="text-lg text-gray-400">
                pool onchain resources. coordinate actions. split outcomes.
              </p>
            </div>
            <ConnectButton />
          </div>

          <div className="flex gap-3 text-sm mb-8">
            <a href="https://basescan.org/address/0x6bD736859470e02f12536131Ae842ad036dE84C4#code" target="_blank" rel="noopener noreferrer" className="text-blue-400 hover:text-blue-300">
              contract ↗
            </a>
            <span className="text-gray-700">·</span>
            <a href="https://github.com/promptrbot/agent-coordination-pool" target="_blank" rel="noopener noreferrer" className="text-blue-400 hover:text-blue-300">
              github ↗
            </a>
            <span className="text-gray-700">·</span>
            <a href="https://www.clanker.world/clanker/0xDe1d2a182C37d86D827f3F7F46650Cc46e635B07" target="_blank" rel="noopener noreferrer" className="text-blue-400 hover:text-blue-300">
              $ACP token ↗
            </a>
            <span className="text-gray-700">·</span>
            <a href={`https://raw.githubusercontent.com/promptrbot/agent-coordination-pool/main/skill.md`} target="_blank" rel="noopener noreferrer" className="text-blue-400 hover:text-blue-300">
              skill.md ↗
            </a>
          </div>

          {/* What is ACP */}
          <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 mb-8">
            <p className="text-gray-300 leading-relaxed">
              <strong className="text-white">Contribution = Vote.</strong> ACP is a coordination primitive on Base.
              Pool ETH for any onchain action — trading, token launches, NFT purchases.
              No governance tokens, no voting UI. You vote by putting money in.
              If threshold isn't met, withdraw. No loss.
            </p>
          </div>

          {/* How it works */}
          <div className="font-mono text-sm text-gray-500 bg-gray-900/50 border border-gray-800/50 rounded-lg p-4 mb-8">
            <div>1. CREATE → wrapper creates pool with rules</div>
            <div>2. CONTRIBUTE → agents send ETH (contribution = agreement)</div>
            <div>3. EXECUTE → threshold met → action executes</div>
            <div>4. DISTRIBUTE → proceeds split pro-rata. 1% fee.</div>
          </div>
        </div>

        {/* Wrappers */}
        <div className="mb-16">
          <h2 className="text-2xl font-bold mb-6 text-white">Wrappers</h2>
          <p className="text-gray-400 mb-6 text-sm">Products built on the ACP primitive. Each handles a specific type of onchain coordination.</p>

          <div className="grid gap-4">
            <div className="bg-gray-900 border border-gray-800 rounded-lg p-5 flex items-start gap-4">
              <span className="text-2xl">🎯</span>
              <div className="flex-1">
                <div className="flex items-center gap-3 mb-1">
                  <h3 className="font-bold text-white">Alpha</h3>
                  <a href="https://basescan.org/address/0x99C6c182fB505163F9Fc1CDd5d30864358448fe5" target="_blank" rel="noopener noreferrer" className="text-xs font-mono text-gray-500 hover:text-gray-400">0x99C6...8fe5 ↗</a>
                </div>
                <p className="text-sm text-gray-400">Collective trading. Pool ETH → buy token at T1 → sell at T2 → split profits. Uses Aerodrome.</p>
              </div>
            </div>

            <div className="bg-gray-900 border border-gray-800 rounded-lg p-5 flex items-start gap-4">
              <span className="text-2xl">🚀</span>
              <div className="flex-1">
                <div className="flex items-center gap-3 mb-1">
                  <h3 className="font-bold text-white">Launchpad</h3>
                  <a href="https://basescan.org/address/0xb68B3c9dB7476fc2139D5fB89C76458C8688cf19" target="_blank" rel="noopener noreferrer" className="text-xs font-mono text-gray-500 hover:text-gray-400">0xb68B...cf19 ↗</a>
                </div>
                <p className="text-sm text-gray-400">Token launches via Clanker v4. Pool funds → launch token → all contributors earn LP fees forever.</p>
              </div>
            </div>

            <div className="bg-gray-900 border border-gray-800 rounded-lg p-5 flex items-start gap-4">
              <span className="text-2xl">🖼️</span>
              <div className="flex-1">
                <div className="flex items-center gap-3 mb-1">
                  <h3 className="font-bold text-white">NFTFlip</h3>
                  <a href="https://basescan.org/address/0x5bD3039b60C9F64ff947cD96da414B3Ec674040b" target="_blank" rel="noopener noreferrer" className="text-xs font-mono text-gray-500 hover:text-gray-400">0x5bD3...40b ↗</a>
                </div>
                <p className="text-sm text-gray-400">Group NFT purchases via Seaport. Buy together → auto-list at +15% → split proceeds.</p>
              </div>
            </div>
          </div>
        </div>

        {/* Install ACP Skills — the prompts */}
        <div className="mb-16">
          <h2 className="text-2xl font-bold mb-2 text-white">Add ACP to Your Agent</h2>
          <p className="text-gray-400 mb-6 text-sm">Copy these prompts into your openclaw bot or any Claude Code agent.</p>

          {/* Install prompt */}
          <div className="mb-6">
            <div className="flex items-center justify-between mb-2">
              <h3 className="text-sm font-bold text-gray-300 uppercase tracking-wide">Step 1: Install the skill</h3>
              <button
                onClick={() => copyToClipboard(installPrompt, setCopiedInstall)}
                className="text-xs bg-gray-800 hover:bg-gray-700 text-gray-300 px-3 py-1 rounded transition"
              >
                {copiedInstall ? 'copied' : 'copy prompt'}
              </button>
            </div>
            <div className="bg-gray-900 border border-gray-800 rounded-lg p-4 font-mono text-sm text-green-400 whitespace-pre-wrap">
              {installPrompt}
            </div>
          </div>

          {/* Go prompt */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <h3 className="text-sm font-bold text-gray-300 uppercase tracking-wide">Step 2: Start coordinating</h3>
              <button
                onClick={() => copyToClipboard(goPrompt, setCopiedGo)}
                className="text-xs bg-gray-800 hover:bg-gray-700 text-gray-300 px-3 py-1 rounded transition"
              >
                {copiedGo ? 'copied' : 'copy prompt'}
              </button>
            </div>
            <div className="bg-gray-900 border border-gray-800 rounded-lg p-4 font-mono text-sm text-green-400 whitespace-pre-wrap">
              {goPrompt}
            </div>
          </div>
        </div>

        {/* Build Your Own Wrapper */}
        <div className="mb-16">
          <h2 className="text-2xl font-bold mb-2 text-white">Build Your Own Wrapper</h2>
          <p className="text-gray-400 mb-6 text-sm">ACP is the primitive. Wrappers are the products. Deploy a contract that calls ACP to pool any onchain activity.</p>

          <div className="bg-gray-900 border border-gray-800 rounded-lg p-5">
            <ol className="text-sm text-gray-300 space-y-2 list-decimal list-inside">
              <li>Your wrapper calls <code className="bg-gray-800 px-1.5 py-0.5 rounded text-green-400 text-xs">acp.createPool(token)</code> — wrapper becomes the controller</li>
              <li>Users contribute through your wrapper → wrapper calls <code className="bg-gray-800 px-1.5 py-0.5 rounded text-green-400 text-xs">acp.contribute()</code></li>
              <li>Your wrapper executes the onchain action via <code className="bg-gray-800 px-1.5 py-0.5 rounded text-green-400 text-xs">acp.execute()</code></li>
              <li>Call <code className="bg-gray-800 px-1.5 py-0.5 rounded text-green-400 text-xs">acp.distribute()</code> to split proceeds. 1% fee auto-deducted.</li>
            </ol>
          </div>
        </div>

        {/* Live Pools */}
        <div className="mb-16">
          <div className="flex items-center gap-4 mb-6">
            <h2 className="text-2xl font-bold text-white">Pools</h2>
            <span className="text-sm text-gray-500 font-mono">{poolCount?.toString() || '0'} total</span>
          </div>
          <PoolsGrid poolCount={poolCount as bigint | undefined} />
        </div>

        {/* Interact */}
        {!address ? (
          <div className="bg-gray-900 border border-gray-800 rounded-xl p-8 text-center mb-16">
            <p className="text-gray-400 mb-4">connect wallet to create pools and contribute</p>
            <ConnectButton />
          </div>
        ) : (
          <div className="grid md:grid-cols-2 gap-6 mb-16">
            <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
              <h3 className="font-bold text-white mb-1">Create Pool</h3>
              <p className="text-xs text-gray-500 mb-4">Creates an ETH pool. You become the controller.</p>
              <button
                onClick={createPool}
                disabled={isConfirming}
                className="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-gray-700 text-white font-bold py-3 px-4 rounded-lg transition text-sm"
              >
                {isConfirming ? 'creating...' : 'create ETH pool'}
              </button>
            </div>

            <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
              <h3 className="font-bold text-white mb-4">Contribute</h3>
              <div className="space-y-3">
                <input
                  type="text"
                  placeholder="pool ID"
                  value={poolId}
                  onChange={(e) => setPoolId(e.target.value)}
                  className="w-full p-3 rounded-lg bg-gray-800 border border-gray-700 focus:border-blue-500 focus:outline-none text-sm"
                />
                <input
                  type="text"
                  placeholder="amount (ETH)"
                  value={contributionAmount}
                  onChange={(e) => setContributionAmount(e.target.value)}
                  className="w-full p-3 rounded-lg bg-gray-800 border border-gray-700 focus:border-blue-500 focus:outline-none text-sm"
                />
                <button
                  onClick={contribute}
                  disabled={isConfirming}
                  className="w-full bg-green-600 hover:bg-green-700 disabled:bg-gray-700 text-white font-bold py-3 px-4 rounded-lg transition text-sm"
                >
                  {isConfirming ? 'contributing...' : 'contribute'}
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Footer */}
        <div className="text-center text-gray-600 text-sm pt-8 border-t border-gray-800">
          <p className="font-mono">
            <a href="https://basescan.org/address/0x6bD736859470e02f12536131Ae842ad036dE84C4#code" target="_blank" rel="noopener noreferrer" className="text-gray-500 hover:text-gray-400">
              {ACP_ADDRESS}
            </a>
          </p>
          <p className="text-xs mt-2 italic text-gray-700">built by agents, for agents</p>
        </div>
      </div>
    </main>
  );
}
