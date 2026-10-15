import { useState } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useSwitchChain } from 'wagmi'
import { arcTestnet } from 'viem/chains'
import { isAddress } from 'viem'
import { toast } from 'sonner'
import { Loader2, Plus, Trash2, ArrowUpRight } from 'lucide-react'
import { buildTxExplorerUrl } from '@/onchain-facts'
import { parseAmount } from '@/onchain-money'
import { AGENT_VAULT_ABI } from '@/agentVaultAbi'

const CHAIN_ID = arcTestnet.id

interface SplitRow { address: string; bps: string }
interface SplitCalcProps {
  contractAddress: `0x${string}` | undefined
  isOwner: boolean
}

export function SplitCalc({ contractAddress, isOwner }: SplitCalcProps) {
  const { chainId } = useAccount()
  const { switchChain } = useSwitchChain()
  const [totalAmount, setTotalAmount] = useState('')
  const [rows, setRows] = useState<SplitRow[]>([{ address: '', bps: '5000' }, { address: '', bps: '5000' }])
  const [hash, setHash] = useState<`0x${string}` | undefined>()

  const { writeContract, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })
  const wrongChain = chainId !== CHAIN_ID

  const bpsSum = rows.reduce((s, r) => s + (parseInt(r.bps) || 0), 0)
  const bpsValid = bpsSum === 10000

  function preview() {
    const total = parseFloat(totalAmount)
    if (!total) return []
    return rows.map(r => (total * (parseInt(r.bps) || 0)) / 10000)
  }

  function handleExecute(e: React.FormEvent) {
    e.preventDefault()
    if (!contractAddress || !isOwner) return
    if (wrongChain) { switchChain({ chainId: CHAIN_ID }); return }
    let parsedTotal: bigint
    try { parsedTotal = parseAmount(CHAIN_ID, totalAmount).raw } catch { toast.error('Invalid total amount'); return }
    for (const r of rows) {
      if (!isAddress(r.address)) { toast.error(`Invalid address: ${r.address}`); return }
    }
    if (!bpsValid) { toast.error('BPS must sum to 10 000'); return }
    writeContract(
      {
        address: contractAddress,
        abi: AGENT_VAULT_ABI,
        functionName: 'splitPayment',
        args: [rows.map(r => r.address as `0x${string}`), rows.map(r => BigInt(parseInt(r.bps) || 0)), parsedTotal],
      },
      {
        onSuccess: (h) => setHash(h),
        onError: (err) => toast.error(err.message.slice(0, 100)),
      },
    )
  }

  const shares = preview()

  return (
    <div className="card p-5">
      <p className="section-label mb-4">Split Payment</p>

      <form onSubmit={handleExecute} className="space-y-4">
        <div>
          <label className="mb-1.5 block text-[11px] font-medium uppercase tracking-wide" style={{ color: 'var(--muted)' }}>Total Amount (USDC)</label>
          <input
            inputMode="decimal" value={totalAmount}
            onChange={e => { const v = e.target.value.replace(/[^0-9.]/g, ''); if (v === '' || /^\d*\.?\d*$/.test(v)) setTotalAmount(v) }}
            placeholder="0.00" className="field field-amount"
          />
        </div>

        <div className="space-y-2">
          {rows.map((row, i) => (
            <div key={i} className="flex items-center gap-2">
              <input
                value={row.address}
                onChange={e => setRows(r => r.map((x, j) => j === i ? { ...x, address: e.target.value } : x))}
                placeholder="0x recipient…"
                className="field field-mono min-w-0 flex-1"
                style={{ padding: '10px 12px', fontSize: 12 }}
              />
              <input
                type="number" min="0" max="10000" value={row.bps}
                onChange={e => setRows(r => r.map((x, j) => j === i ? { ...x, bps: e.target.value } : x))}
                className="field w-20 text-center"
                style={{ padding: '10px 8px', fontFamily: 'Space Grotesk, sans-serif', fontWeight: 700, fontSize: 14 }}
              />
              <span className="text-[11px] w-8 shrink-0" style={{ color: 'var(--subtle)' }}>bps</span>
              {shares[i] !== undefined && (
                <span className="mono w-20 shrink-0 text-right text-[12px] tabular-nums" style={{ color: 'var(--accent)' }}>
                  {shares[i].toFixed(2)}
                </span>
              )}
              {rows.length > 2 && (
                <button type="button" onClick={() => setRows(r => r.filter((_, j) => j !== i))}
                  className="shrink-0 rounded-lg p-2 transition-colors"
                  style={{ color: 'var(--danger)' }}
                  onMouseEnter={e => (e.currentTarget.style.background = 'var(--danger-dim)')}
                  onMouseLeave={e => (e.currentTarget.style.background = 'transparent')}
                >
                  <Trash2 className="size-3.5" />
                </button>
              )}
            </div>
          ))}
        </div>

        <div className="flex items-center justify-between">
          <button type="button" onClick={() => setRows(r => [...r, { address: '', bps: '0' }])}
            className="btn-ghost" style={{ padding: '6px 12px', fontSize: 12 }}>
            <Plus className="size-3" /> Add recipient
          </button>
          <span
            className="text-[12px] font-semibold tabular-nums"
            style={{ color: bpsValid ? 'var(--success)' : bpsSum > 0 ? 'var(--danger)' : 'var(--subtle)' }}
          >
            {bpsSum.toLocaleString()} / 10,000 bps
          </span>
        </div>

        {isSuccess && hash && (
          <a href={buildTxExplorerUrl(CHAIN_ID, hash)} target="_blank" rel="noreferrer"
            className="mono flex items-center gap-1.5 text-[12px] transition-opacity hover:opacity-80"
            style={{ color: 'var(--accent)' }}>
            Split executed <ArrowUpRight className="size-3" />
          </a>
        )}

        {isOwner ? (
          <button type="submit" disabled={isPending || isConfirming || !bpsValid || !totalAmount || !contractAddress} className="btn-primary">
            {isPending ? <><Loader2 className="size-4 animate-spin" /> Confirm…</>
              : isConfirming ? <><Loader2 className="size-4 animate-spin" /> Confirming…</>
              : wrongChain ? 'Switch to Arc Testnet'
              : 'Execute Split'}
          </button>
        ) : contractAddress ? (
          <p className="text-center text-[12px]" style={{ color: 'var(--subtle)' }}>Only the vault owner can execute split payments.</p>
        ) : null}
      </form>
    </div>
  )
}
