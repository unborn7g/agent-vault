import { useState } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useSwitchChain, useReadContracts } from 'wagmi'
import { arcTestnet } from 'viem/chains'
import { isAddress } from 'viem'
import { toast } from 'sonner'
import { Loader2, Lock, Unlock, RefreshCw, ArrowUpRight, ChevronDown, ChevronUp } from 'lucide-react'
import { buildAddressExplorerUrl } from '@/onchain-facts'
import { parseAmount, Amount, usdcDecimalsFor } from '@/onchain-money'
import { AGENT_VAULT_ABI } from '@/agentVaultAbi'

const CHAIN_ID = arcTestnet.id

const ESCROW_META: Record<number, { label: string; bg: string; color: string }> = {
  0: { label: 'Active',   bg: 'var(--accent-dim)',   color: 'var(--accent)' },
  1: { label: 'Released', bg: 'var(--success-dim)',  color: 'var(--success)' },
  2: { label: 'Refunded', bg: 'var(--surface-muted)',color: 'var(--subtle)'  },
}

function fmt(raw: bigint) {
  return Amount.fromRaw(raw, usdcDecimalsFor(CHAIN_ID)).toFixed(2)
}

interface EscrowPanelProps {
  contractAddress: `0x${string}` | undefined
  isOwner: boolean
  canPropose: boolean
  escrowCount: number
}

interface EscrowItem {
  id: number
  proposer: `0x${string}`
  payee: `0x${string}`
  amount: bigint
  condition: string
  state: number
}

export function EscrowPanel({ contractAddress, isOwner, canPropose, escrowCount }: EscrowPanelProps) {
  const { chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const [payee, setPayee] = useState('')
  const [amount, setAmount] = useState('')
  const [condition, setCondition] = useState('')
  const [expanded, setExpanded] = useState<number | null>(null)
  const [actionHash, setActionHash] = useState<`0x${string}` | undefined>()

  const wrongChain = chainId !== CHAIN_ID
  const indices = Array.from({ length: escrowCount }, (_, i) => i)

  const { data: rawEscrows, refetch } = useReadContracts({
    contracts: indices.map(i => ({
      address: contractAddress!,
      abi: AGENT_VAULT_ABI,
      functionName: 'escrows' as const,
      args: [BigInt(i)] as const,
      chainId: CHAIN_ID,
    })),
    query: { enabled: !!contractAddress && escrowCount > 0, refetchInterval: 8000 },
  })

  const escrows: EscrowItem[] = (rawEscrows ?? []).map((r, i) => {
    if (!r.result) return null
    const [proposer, payee, amount, condition, state] = r.result as [`0x${string}`, `0x${string}`, bigint, string, number]
    return { id: i, proposer, payee, amount, condition, state }
  }).filter(Boolean) as EscrowItem[]

  const { writeContract, isPending } = useWriteContract()
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: actionHash })

  function act(fn: string, args: unknown[]) {
    if (!contractAddress) return
    if (wrongChain) { switchChain({ chainId: CHAIN_ID }); return }
    writeContract(
      { address: contractAddress, abi: AGENT_VAULT_ABI, functionName: fn as 'createEscrow', args: args as [`0x${string}`, bigint, string] },
      {
        onSuccess: (h) => { setActionHash(h); void refetch() },
        onError: (err) => toast.error(err.message.slice(0, 100)),
      },
    )
  }

  function handleCreate(e: React.FormEvent) {
    e.preventDefault()
    if (!isAddress(payee)) { toast.error('Invalid payee address'); return }
    let parsed: bigint
    try { parsed = parseAmount(CHAIN_ID, amount).raw } catch { toast.error('Invalid amount'); return }
    act('createEscrow', [payee, parsed, condition])
    setPayee(''); setAmount(''); setCondition('')
  }

  return (
    <div className="space-y-3">
      {canPropose && (
        <div className="card p-5">
          <p className="section-label mb-4">Create Escrow</p>
          <form onSubmit={handleCreate} className="space-y-3">
            <div>
              <label className="mb-1.5 block text-[11px] font-medium uppercase tracking-wide" style={{ color: 'var(--muted)' }}>Payee</label>
              <input value={payee} onChange={e => setPayee(e.target.value)} placeholder="0x…" className="field field-mono" />
            </div>
            <div>
              <label className="mb-1.5 block text-[11px] font-medium uppercase tracking-wide" style={{ color: 'var(--muted)' }}>Amount (USDC)</label>
              <input
                inputMode="decimal" value={amount}
                onChange={e => { const v = e.target.value.replace(/[^0-9.]/g, ''); if (v === '' || /^\d*\.?\d*$/.test(v)) setAmount(v) }}
                placeholder="0.00" className="field field-amount"
              />
            </div>
            <div>
              <label className="mb-1.5 block text-[11px] font-medium uppercase tracking-wide" style={{ color: 'var(--muted)' }}>Condition</label>
              <input value={condition} onChange={e => setCondition(e.target.value)} placeholder="e.g. Deliver report by Dec 1" className="field" />
            </div>
            <button type="submit" disabled={isPending || isConfirming || !payee || !amount} className="btn-primary">
              {isPending ? <><Loader2 className="size-4 animate-spin" /> Confirm…</> : <><Lock className="size-4" /> Lock in Escrow</>}
            </button>
          </form>
        </div>
      )}

      {escrowCount > 0 && (
        <div className="card-muted overflow-hidden">
          <div className="px-5 py-4">
            <p className="section-label">Escrows · {escrowCount}</p>
          </div>
          <div className="divide-card">
            {[...escrows].reverse().map(esc => {
              const meta = ESCROW_META[esc.state] ?? { label: 'Unknown', bg: 'var(--surface-muted)', color: 'var(--subtle)' }
              const isOpen = expanded === esc.id
              return (
                <div key={esc.id}>
                  <button
                    className="flex w-full items-start justify-between gap-4 px-5 py-4 text-left transition-colors"
                    style={{ background: 'transparent' }}
                    onMouseEnter={e => (e.currentTarget.style.background = 'var(--surface-muted)')}
                    onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
                    onClick={() => setExpanded(isOpen ? null : esc.id)}
                  >
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span className="display tabular-nums" style={{ fontSize: 20, fontWeight: 600, color: 'var(--ink)', letterSpacing: '-0.03em' }}>
                          {fmt(esc.amount)}
                        </span>
                        <span className="text-[13px]" style={{ color: 'var(--muted)' }}>USDC</span>
                      </div>
                      <p className="mt-0.5 truncate text-[12px]" style={{ color: 'var(--muted)' }}>
                        {esc.condition || '(no condition)'}
                      </p>
                    </div>
                    <div className="flex shrink-0 items-center gap-2">
                      <span className="rounded-full px-2.5 py-1 text-[11px] font-semibold" style={{ background: meta.bg, color: meta.color }}>
                        {meta.label}
                      </span>
                      <span className="mono text-[11px]" style={{ color: 'var(--subtle)' }}>#{esc.id}</span>
                      {isOpen ? <ChevronUp className="size-3.5 shrink-0" style={{ color: 'var(--subtle)' }} /> : <ChevronDown className="size-3.5 shrink-0" style={{ color: 'var(--subtle)' }} />}
                    </div>
                  </button>

                  {isOpen && (
                    <div className="px-5 pb-4 space-y-3">
                      <div className="rounded-2xl p-4 text-[12px]" style={{ background: 'var(--surface-muted)', border: '1px solid var(--border)' }}>
                        <div className="flex items-center justify-between gap-4">
                          <span style={{ color: 'var(--muted)' }}>Payee</span>
                          <a href={buildAddressExplorerUrl(CHAIN_ID, esc.payee)} target="_blank" rel="noreferrer"
                            className="mono flex items-center gap-1 transition-opacity hover:opacity-70"
                            style={{ color: 'var(--accent)' }}>
                            {esc.payee.slice(0, 12)}… <ArrowUpRight className="size-3" />
                          </a>
                        </div>
                      </div>
                      {isOwner && esc.state === 0 && (
                        <div className="flex gap-2">
                          <button onClick={() => act('releaseEscrow', [BigInt(esc.id)])} disabled={isPending || isConfirming}
                            className="btn-ghost" style={{ color: 'var(--success)', borderColor: 'rgba(52,211,153,0.25)' }}>
                            {isPending ? <Loader2 className="size-3 animate-spin" /> : <Unlock className="size-3" />} Release
                          </button>
                          <button onClick={() => act('refundEscrow', [BigInt(esc.id)])} disabled={isPending || isConfirming}
                            className="btn-ghost">
                            {isPending ? <Loader2 className="size-3 animate-spin" /> : <RefreshCw className="size-3" />} Refund
                          </button>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}
