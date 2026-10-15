import { useEffect, useState } from 'react'
import { usePublicClient } from 'wagmi'
import { decodeEventLog } from 'viem'
import { arcTestnet } from 'viem/chains'
import { Activity, ArrowUpRight, Loader2 } from 'lucide-react'
import { buildTxExplorerUrl } from '@/onchain-facts'
import { Amount, usdcDecimalsFor } from '@/onchain-money'
import { AGENT_VAULT_ABI } from '@/agentVaultAbi'

const CHAIN_ID = arcTestnet.id

function fmt(raw: bigint) {
  return Amount.fromRaw(raw, usdcDecimalsFor(CHAIN_ID)).toFixed(2)
}

interface AuditLogProps {
  contractAddress: `0x${string}` | undefined
}

interface LogEntry {
  eventName: string
  summary: string
  txHash: `0x${string}` | undefined
  blockNumber: bigint
}

const EVENT_STYLE: Record<string, { bg: string; color: string }> = {
  VaultFunded:          { bg: 'var(--success-dim)',  color: 'var(--success)'  },
  CapsUpdated:          { bg: 'var(--surface-muted)', color: 'var(--muted)'   },
  AgentApproved:        { bg: 'var(--accent-dim)',   color: 'var(--accent)'   },
  AgentRevoked:         { bg: 'var(--danger-dim)',   color: 'var(--danger)'   },
  PaymentProposed:      { bg: 'var(--warning-dim)',  color: 'var(--warning)'  },
  ProposalApproved:     { bg: 'var(--violet-dim)',   color: 'var(--violet)'   },
  ProposalRejected:     { bg: 'var(--surface-muted)', color: 'var(--subtle)'  },
  ProposalExecuted:     { bg: 'var(--success-dim)',  color: 'var(--success)'  },
  ProposalFailed:       { bg: 'var(--danger-dim)',   color: 'var(--danger)'   },
  EscrowCreated:        { bg: 'var(--warning-dim)',  color: 'var(--warning)'  },
  EscrowReleased:       { bg: 'var(--success-dim)',  color: 'var(--success)'  },
  EscrowReleaseFailed:  { bg: 'var(--danger-dim)',   color: 'var(--danger)'   },
  EscrowRefunded:       { bg: 'var(--surface-muted)', color: 'var(--subtle)'  },
  SplitPaymentExecuted: { bg: 'var(--success-dim)',  color: 'var(--success)'  },
  SplitPaymentSkipped:  { bg: 'var(--danger-dim)',   color: 'var(--danger)'   },
}

function coerce(v: unknown): string {
  if (v === null || v === undefined) return '?'
  if (typeof v === 'bigint') return fmt(v)
  if (typeof v === 'string') return v
  if (typeof v === 'number' || typeof v === 'boolean') return String(v)
  return '?'
}

function addr(v: unknown): string {
  if (typeof v === 'string') return v.slice(0, 10) + '…'
  return '?'
}

function summarize(name: string, args: Record<string, unknown>): string {
  switch (name) {
    case 'VaultFunded': return `+${coerce(args['amount'])} USDC funded`
    case 'CapsUpdated': return `Caps updated — per-tx ${coerce(args['perTxCap'])}, daily ${coerce(args['dailyCap'])}`
    case 'AgentApproved': return `Agent approved: ${addr(args['agent'])}`
    case 'AgentRevoked': return `Agent revoked: ${addr(args['agent'])}`
    case 'PaymentProposed': return `#${coerce(args['proposalId'])} proposed ${coerce(args['amount'])} USDC to ${addr(args['recipient'])}`
    case 'ProposalApproved': return `#${coerce(args['proposalId'])} approved`
    case 'ProposalRejected': return `#${coerce(args['proposalId'])} rejected`
    case 'ProposalExecuted': return `#${coerce(args['proposalId'])} executed ${coerce(args['amount'])} USDC to ${addr(args['recipient'])}`
    case 'ProposalFailed': return `#${coerce(args['proposalId'])} blocked — transfer failed to ${addr(args['recipient'])}`
    case 'EscrowCreated': return `#${coerce(args['escrowId'])} locked ${coerce(args['amount'])} USDC`
    case 'EscrowReleased': return `#${coerce(args['escrowId'])} released ${coerce(args['amount'])} USDC`
    case 'EscrowReleaseFailed': return `#${coerce(args['escrowId'])} release failed for ${addr(args['payee'])}`
    case 'EscrowRefunded': return `#${coerce(args['escrowId'])} refunded ${coerce(args['amount'])} USDC`
    case 'SplitPaymentExecuted': {
      const skipped = typeof args['skippedCount'] === 'bigint' ? Number(args['skippedCount']) : 0
      return `Split ${coerce(args['totalAmount'])} USDC to ${coerce(args['recipientCount'])} recipients${skipped > 0 ? `, ${skipped} skipped` : ''}`
    }
    case 'SplitPaymentSkipped': return `Skipped ${coerce(args['amount'])} USDC to ${addr(args['recipient'])}`
    default: return name
  }
}

export function AuditLog({ contractAddress }: AuditLogProps) {
  const client = usePublicClient({ chainId: CHAIN_ID })
  const [entries, setEntries] = useState<LogEntry[]>([])
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    if (!contractAddress || !client) return
    let cancelled = false

    async function fetchLogs() {
      if (!contractAddress || !client) return
      setLoading(true)
      try {
        const rawLogs = await client.getLogs({ address: contractAddress, fromBlock: 'earliest', toBlock: 'latest' })
        if (cancelled) return
        const decoded: LogEntry[] = []
        for (const log of rawLogs) {
          for (const abiItem of AGENT_VAULT_ABI) {
            if (abiItem.type !== 'event') continue
            try {
              const result = decodeEventLog({ abi: [abiItem], data: log.data, topics: log.topics })
              decoded.push({
                eventName: result.eventName,
                summary: summarize(result.eventName, result.args),
                txHash: log.transactionHash ?? undefined,
                blockNumber: log.blockNumber ?? 0n,
              })
              break
            } catch { /* not this event */ }
          }
        }
        decoded.sort((a, b) => Number(b.blockNumber - a.blockNumber))
        setEntries(decoded)
      } catch { /* RPC error — silently ignore */ }
      finally { if (!cancelled) setLoading(false) }
    }

    void fetchLogs()
    const interval = setInterval(() => { void fetchLogs() }, 15000)
    return () => { cancelled = true; clearInterval(interval) }
  }, [contractAddress, client])

  if (!contractAddress) return null

  return (
    <div className="card-muted overflow-hidden">
      <div className="flex items-center gap-2.5 px-5 py-4">
        <Activity className="size-3.5" style={{ color: 'var(--muted)' }} />
        <p className="section-label">Audit Log</p>
        {loading && <Loader2 className="size-3 animate-spin ml-auto" style={{ color: 'var(--subtle)' }} />}
      </div>

      {entries.length === 0 && !loading ? (
        <p className="px-5 pb-5 text-[13px]" style={{ color: 'var(--subtle)' }}>
          No on-chain events yet. Interact with the vault to see activity.
        </p>
      ) : (
        <div className="divide-card">
          {entries.slice(0, 50).map((e, i) => {
            const style = EVENT_STYLE[e.eventName] ?? { bg: 'var(--surface-muted)', color: 'var(--subtle)' }
            return (
              <div key={i} className="flex items-center gap-3 px-5 py-3">
                <span
                  className="shrink-0 rounded-full px-2.5 py-0.5 text-[11px] font-semibold"
                  style={{ background: style.bg, color: style.color }}
                >
                  {e.eventName}
                </span>
                <span className="min-w-0 flex-1 truncate text-[12px]" style={{ color: 'var(--ink-2)' }}>
                  {e.summary}
                </span>
                {e.txHash && (
                  <a
                    href={buildTxExplorerUrl(CHAIN_ID, e.txHash)}
                    target="_blank" rel="noreferrer"
                    className="mono shrink-0 flex items-center gap-1 text-[11px] transition-opacity hover:opacity-70"
                    style={{ color: 'var(--accent)' }}
                  >
                    tx <ArrowUpRight className="size-3" />
                  </a>
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
