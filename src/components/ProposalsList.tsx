import { useState } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useSwitchChain, useReadContracts } from 'wagmi'
import { arcTestnet } from 'viem/chains'
import { isAddress } from 'viem'
import { toast } from 'sonner'
import { Loader2, Check, X, PlayCircle, RotateCcw, ArrowUpRight, ChevronDown, ChevronUp, AlertCircle } from 'lucide-react'
import { buildAddressExplorerUrl } from '@/onchain-facts'
import { Amount, usdcDecimalsFor } from '@/onchain-money'
import { AGENT_VAULT_ABI } from '@/agentVaultAbi'

const CHAIN_ID = arcTestnet.id

// State styles: amber Pending, violet Approved, muted Rejected, teal Executed, red Failed
const STATE_META: Record<number, { label: string; bg: string; color: string }> = {
  0: { label: 'Pending',  bg: 'var(--warning-dim)',  color: 'var(--warning)' },
  1: { label: 'Approved', bg: 'var(--violet-dim)',   color: 'var(--violet)'  },
  2: { label: 'Rejected', bg: 'var(--surface-muted)',color: 'var(--subtle)'  },
  3: { label: 'Executed', bg: 'var(--success-dim)',  color: 'var(--success)' },
  4: { label: 'Failed',   bg: 'var(--danger-dim)',   color: 'var(--danger)'  },
}

function fmt(raw: bigint) {
  return Amount.fromRaw(raw, usdcDecimalsFor(CHAIN_ID)).toFixed(2)
}

interface ProposalsListProps {
  contractAddress: `0x${string}` | undefined
  isOwner: boolean
  proposalCount: number
}

interface Proposal {
  id: number
  proposer: `0x${string}`
  recipient: `0x${string}`
  amount: bigint
  reason: string
  state: number
}

export function ProposalsList({ contractAddress, isOwner, proposalCount }: ProposalsListProps) {
  const { chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const [expanded, setExpanded] = useState<number | null>(null)
  const [retryRecipient, setRetryRecipient] = useState('')
  const [actionHash, setActionHash] = useState<`0x${string}` | undefined>()

  const wrongChain = chainId !== CHAIN_ID
  const indices = Array.from({ length: proposalCount }, (_, i) => i)

  const { data: rawProposals, refetch } = useReadContracts({
    contracts: indices.map(i => ({
      address: contractAddress!,
      abi: AGENT_VAULT_ABI,
      functionName: 'proposals' as const,
      args: [BigInt(i)] as const,
      chainId: CHAIN_ID,
    })),
    query: { enabled: !!contractAddress && proposalCount > 0, refetchInterval: 8000 },
  })

  const proposals: Proposal[] = (rawProposals ?? []).map((r, i) => {
    if (!r.result) return null
    const [proposer, recipient, amount, reason, state] = r.result as [`0x${string}`, `0x${string}`, bigint, string, number]
    return { id: i, proposer, recipient, amount, reason, state }
  }).filter(Boolean) as Proposal[]

  const { writeContract, isPending } = useWriteContract()
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: actionHash })

  function act(fn: string, args: unknown[]) {
    if (!contractAddress) return
    if (wrongChain) { switchChain({ chainId: CHAIN_ID }); return }
    writeContract(
      { address: contractAddress, abi: AGENT_VAULT_ABI, functionName: fn as 'approveProposal', args: args as [bigint] },
      {
        onSuccess: (h) => { setActionHash(h); void refetch() },
        onError: (err) => toast.error(err.message.slice(0, 100)),
      },
    )
  }

  if (!contractAddress) return null

  return (
    <div className="card-muted overflow-hidden">
      <div className="flex items-center justify-between px-5 py-4">
        <p className="section-label">Proposals{proposalCount > 0 ? ` · ${proposalCount}` : ''}</p>
      </div>

      {proposalCount === 0 ? (
        <p className="px-5 pb-5 text-[13px]" style={{ color: 'var(--subtle)' }}>
          No proposals yet.
        </p>
      ) : (
        <div className="divide-card">
          {[...proposals].reverse().map(p => {
            const meta = STATE_META[p.state] ?? { label: 'Unknown', bg: 'var(--surface-muted)', color: 'var(--subtle)' }
            const isOpen = expanded === p.id
            const isFailed = p.state === 4

            return (
              <div key={p.id}>
                {/* Failed banner — always visible for failed proposals */}
                {isFailed && (
                  <div
                    className="mx-4 mt-4 flex items-start gap-3 rounded-2xl px-4 py-3"
                    style={{ background: 'rgba(248,113,113,0.08)', border: '1px solid rgba(248,113,113,0.25)' }}
                  >
                    <AlertCircle className="mt-0.5 size-4 shrink-0" style={{ color: 'var(--danger)' }} />
                    <div>
                      <p className="text-[13px] font-semibold" style={{ color: 'var(--danger)' }}>
                        Blocked — transfer failed
                      </p>
                      <p className="mt-0.5 text-[12px]" style={{ color: 'var(--muted)' }}>
                        The USDC transfer to the recipient was rejected. Use Retry to redirect to a new address.
                      </p>
                    </div>
                  </div>
                )}

                {/* Proposal row — Apple Wallet pass style */}
                <button
                  className="flex w-full items-start justify-between gap-4 px-5 py-4 text-left transition-colors"
                  style={{ background: 'transparent' }}
                  onMouseEnter={e => (e.currentTarget.style.background = 'var(--surface-muted)')}
                  onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
                  onClick={() => setExpanded(isOpen ? null : p.id)}
                >
                  {/* Left: amount large */}
                  <div className="flex min-w-0 flex-1 items-start gap-3">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span
                          className="display tabular-nums"
                          style={{ fontSize: 20, fontWeight: 600, color: 'var(--ink)', letterSpacing: '-0.03em' }}
                        >
                          {fmt(p.amount)}
                        </span>
                        <span className="text-[13px]" style={{ color: 'var(--muted)' }}>USDC</span>
                      </div>
                      <p className="mt-0.5 truncate text-[12px]" style={{ color: 'var(--muted)' }}>
                        {p.reason || '(no reason)'} · {p.recipient.slice(0, 8)}…
                      </p>
                    </div>
                  </div>

                  {/* Right: status pill + chevron */}
                  <div className="flex shrink-0 items-center gap-2">
                    <span
                      className="rounded-full px-2.5 py-1 text-[11px] font-semibold"
                      style={{ background: meta.bg, color: meta.color }}
                    >
                      {meta.label}
                    </span>
                    <span className="mono text-[11px]" style={{ color: 'var(--subtle)' }}>#{p.id}</span>
                    {isOpen
                      ? <ChevronUp className="size-3.5 shrink-0" style={{ color: 'var(--subtle)' }} />
                      : <ChevronDown className="size-3.5 shrink-0" style={{ color: 'var(--subtle)' }} />
                    }
                  </div>
                </button>

                {/* Expanded detail */}
                {isOpen && (
                  <div className="px-5 pb-4 space-y-3">
                    {/* Detail rows */}
                    <div
                      className="rounded-2xl p-4 text-[12px] space-y-2"
                      style={{ background: 'var(--surface-muted)', border: '1px solid var(--border)' }}
                    >
                      {[
                        { label: 'Proposer', val: p.proposer },
                        { label: 'Recipient', val: p.recipient },
                      ].map(row => (
                        <div key={row.label} className="flex items-center justify-between gap-4">
                          <span style={{ color: 'var(--muted)' }}>{row.label}</span>
                          <a
                            href={buildAddressExplorerUrl(CHAIN_ID, row.val)}
                            target="_blank" rel="noreferrer"
                            className="mono flex items-center gap-1 transition-opacity hover:opacity-70"
                            style={{ color: 'var(--accent)' }}
                          >
                            {row.val.slice(0, 12)}… <ArrowUpRight className="size-3" />
                          </a>
                        </div>
                      ))}
                    </div>

                    {/* Owner actions */}
                    {isOwner && (
                      <div className="flex flex-wrap gap-2">
                        {p.state === 0 && (
                          <>
                            <button
                              onClick={() => act('approveProposal', [BigInt(p.id)])}
                              disabled={isPending || isConfirming}
                              className="btn-ghost"
                              style={{ color: 'var(--success)', borderColor: 'rgba(52,211,153,0.25)' }}
                            >
                              {isPending ? <Loader2 className="size-3 animate-spin" /> : <Check className="size-3" />} Approve
                            </button>
                            <button
                              onClick={() => act('rejectProposal', [BigInt(p.id)])}
                              disabled={isPending || isConfirming}
                              className="btn-ghost"
                              style={{ color: 'var(--danger)', borderColor: 'rgba(248,113,113,0.25)' }}
                            >
                              {isPending ? <Loader2 className="size-3 animate-spin" /> : <X className="size-3" />} Reject
                            </button>
                          </>
                        )}
                        {p.state === 1 && (
                          <button
                            onClick={() => act('executeProposal', [BigInt(p.id)])}
                            disabled={isPending || isConfirming}
                            className="btn-ghost"
                            style={{ color: 'var(--accent)', borderColor: 'rgba(45,212,191,0.25)' }}
                          >
                            {isPending ? <Loader2 className="size-3 animate-spin" /> : <PlayCircle className="size-3" />} Execute
                          </button>
                        )}
                        {p.state === 4 && (
                          <div className="w-full space-y-2">
                            <p className="text-[12px]" style={{ color: 'var(--muted)' }}>
                              Redirect payment to a different address:
                            </p>
                            <div className="flex gap-2">
                              <input
                                value={retryRecipient}
                                onChange={e => setRetryRecipient(e.target.value)}
                                placeholder="0x new recipient…"
                                className="field field-mono min-w-0 flex-1"
                                style={{ padding: '8px 12px', fontSize: 12 }}
                              />
                              <button
                                onClick={() => {
                                  if (!isAddress(retryRecipient)) { toast.error('Invalid address'); return }
                                  act('retryProposal', [BigInt(p.id), retryRecipient])
                                }}
                                disabled={isPending || isConfirming || !retryRecipient}
                                className="btn-ghost"
                                style={{ color: 'var(--accent)', borderColor: 'rgba(45,212,191,0.3)', padding: '8px 14px' }}
                              >
                                {isPending ? <Loader2 className="size-3 animate-spin" /> : <RotateCcw className="size-3" />} Retry
                              </button>
                            </div>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
