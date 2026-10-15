import { useReadContracts } from 'wagmi'
import { erc20Abi } from 'viem'
import { arcTestnet } from 'viem/chains'
import { getUsdc } from '@/onchain-facts'
import { Amount, usdcDecimalsFor } from '@/onchain-money'
import { AGENT_VAULT_ABI } from '@/agentVaultAbi'
import { Lock } from 'lucide-react'

const CHAIN_ID = arcTestnet.id
const usdcFact = getUsdc(CHAIN_ID)!

interface VaultStatsProps {
  contractAddress: `0x${string}` | undefined
}

function fmt(raw: bigint | undefined): string {
  if (raw === undefined) return '—'
  return Amount.fromRaw(raw, usdcDecimalsFor(CHAIN_ID)).toFixed(2)
}

export function VaultStats({ contractAddress }: VaultStatsProps) {
  const enabled = !!contractAddress

  const { data } = useReadContracts({
    contracts: [
      { address: usdcFact.address as `0x${string}`, abi: erc20Abi, functionName: 'balanceOf', args: contractAddress ? [contractAddress] : ['0x0000000000000000000000000000000000000000'], chainId: CHAIN_ID },
      { address: contractAddress!, abi: AGENT_VAULT_ABI, functionName: 'spentToday', chainId: CHAIN_ID },
      { address: contractAddress!, abi: AGENT_VAULT_ABI, functionName: 'dailyCap', chainId: CHAIN_ID },
      { address: contractAddress!, abi: AGENT_VAULT_ABI, functionName: 'perTxCap', chainId: CHAIN_ID },
      { address: contractAddress!, abi: AGENT_VAULT_ABI, functionName: 'escrowedBalance', chainId: CHAIN_ID },
    ],
    query: { enabled, refetchInterval: 8000 },
  })

  const vaultBalance = data?.[0]?.result
  const spentToday = data?.[1]?.result
  const dailyCap = data?.[2]?.result
  const perTxCap = data?.[3]?.result
  const escrowedBalance = data?.[4]?.result

  const dailyPct = (spentToday !== undefined && dailyCap !== undefined && dailyCap > 0n)
    ? Number((spentToday * 10000n) / dailyCap) / 100
    : 0

  const freeBalance = (vaultBalance !== undefined && escrowedBalance !== undefined)
    ? (vaultBalance > escrowedBalance ? vaultBalance - escrowedBalance : 0n)
    : undefined

  const barColor = dailyPct >= 90 ? 'var(--danger)' : dailyPct >= 70 ? 'var(--warning)' : 'var(--accent)'

  return (
    <div className="card p-6">
      {/* Hero balance */}
      <div className="mb-6">
        <p className="section-label mb-3">Vault Balance</p>
        <div className="flex items-baseline gap-2">
          <span
            className="display tabular-nums"
            style={{ fontSize: 52, fontWeight: 300, lineHeight: 1, color: 'var(--ink)', letterSpacing: '-0.04em' }}
          >
            {enabled ? fmt(freeBalance) : '—'}
          </span>
          <span
            className="display"
            style={{ fontSize: 22, fontWeight: 400, color: 'var(--muted)', letterSpacing: '-0.02em' }}
          >
            USDC
          </span>
        </div>
        {escrowedBalance !== undefined && escrowedBalance > 0n && (
          <p className="mt-2 flex items-center gap-1.5 text-[13px] tabular-nums" style={{ color: 'var(--muted)' }}>
            <Lock className="size-3" style={{ color: 'var(--warning)' }} />
            {fmt(escrowedBalance)} USDC escrowed
          </p>
        )}
      </div>

      {/* Divider */}
      <div style={{ height: 1, background: 'var(--border)', marginBottom: 20 }} />

      {/* Daily spend + per-tx cap row */}
      <div className="grid grid-cols-2 gap-6">
        {/* Daily spend */}
        <div>
          <p className="section-label mb-2">Spent Today</p>
          <div className="mb-3 flex items-baseline gap-1.5">
            <span className="display text-2xl font-semibold tabular-nums" style={{ color: 'var(--ink)', letterSpacing: '-0.03em' }}>
              {enabled ? fmt(spentToday) : '—'}
            </span>
            <span className="text-[13px]" style={{ color: 'var(--muted)' }}>
              / {fmt(dailyCap)}
            </span>
          </div>
          {/* Progress bar */}
          <div
            className="relative h-1.5 overflow-hidden rounded-full"
            style={{ background: 'var(--surface-muted)', border: '1px solid var(--border)' }}
          >
            <div
              className="absolute left-0 top-0 h-full rounded-full"
              style={{
                width: `${Math.min(dailyPct, 100)}%`,
                background: barColor,
                transition: 'width 700ms cubic-bezier(0.4,0,0.2,1), background 400ms ease',
              }}
            />
          </div>
          <p
            className="mt-1.5 text-[11px] tabular-nums"
            style={{ color: dailyPct >= 90 ? 'var(--danger)' : dailyPct >= 70 ? 'var(--warning)' : 'var(--muted)' }}
          >
            {dailyPct.toFixed(1)}% of daily limit
          </p>
        </div>

        {/* Per-tx cap */}
        <div>
          <p className="section-label mb-2">Per-Transaction Cap</p>
          <div className="flex items-baseline gap-1.5">
            <span className="display text-2xl font-semibold tabular-nums" style={{ color: 'var(--ink)', letterSpacing: '-0.03em' }}>
              {enabled ? fmt(perTxCap) : '—'}
            </span>
            <span className="text-[13px]" style={{ color: 'var(--muted)' }}>USDC max</span>
          </div>
          <p className="mt-3 text-[11px]" style={{ color: 'var(--subtle)' }}>
            Single payment ceiling
          </p>
        </div>
      </div>
    </div>
  )
}
