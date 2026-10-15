import { useState } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useSwitchChain, useReadContract } from 'wagmi'
import { isAddress } from 'viem'
import { arcTestnet } from 'viem/chains'
import { toast } from 'sonner'
import { Loader2, ArrowUpRight } from 'lucide-react'
import { buildTxExplorerUrl } from '@/onchain-facts'
import { parseAmount } from '@/onchain-money'
import { AGENT_VAULT_ABI } from '@/agentVaultAbi'

const CHAIN_ID = arcTestnet.id

interface ProposeFormProps {
  contractAddress: `0x${string}` | undefined
}

export function ProposeForm({ contractAddress }: ProposeFormProps) {
  const { address, chainId, isConnected } = useAccount()
  const { switchChain } = useSwitchChain()
  const [recipient, setRecipient] = useState('')
  const [amount, setAmount] = useState('')
  const [reason, setReason] = useState('')

  const { data: isAgent } = useReadContract({
    address: contractAddress!,
    abi: AGENT_VAULT_ABI,
    functionName: 'isAgent',
    args: address ? [address] : ['0x0000000000000000000000000000000000000000'],
    chainId: CHAIN_ID,
    query: { enabled: !!contractAddress && !!address },
  })

  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const wrongChain = isConnected && chainId !== CHAIN_ID
  const canPropose = !!contractAddress && !!isAgent

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!contractAddress) return
    if (wrongChain) { switchChain({ chainId: CHAIN_ID }); return }
    let parsed: bigint
    try { parsed = parseAmount(CHAIN_ID, amount).raw } catch { toast.error('Invalid amount'); return }
    if (!isAddress(recipient)) { toast.error('Invalid recipient address'); return }
    writeContract(
      { address: contractAddress, abi: AGENT_VAULT_ABI, functionName: 'proposePayment', args: [recipient, parsed, reason] },
      {
        onSuccess: () => { setRecipient(''); setAmount(''); setReason('') },
        onError: (err) => toast.error(err.message.slice(0, 80)),
      },
    )
  }

  return (
    <div className="card p-5">
      <p className="section-label mb-4">Propose Payment</p>

      {!isConnected && (
        <p className="text-[13px]" style={{ color: 'var(--muted)' }}>Connect your wallet to propose a payment.</p>
      )}

      {isConnected && !canPropose && contractAddress && (
        <div
          className="rounded-xl px-4 py-3 text-[13px]"
          style={{ background: 'var(--danger-dim)', border: '1px solid rgba(248,113,113,0.2)', color: 'var(--danger)' }}
        >
          Your wallet is not an approved agent on this vault.
        </div>
      )}

      {isConnected && (
        <form onSubmit={handleSubmit} className="space-y-3">
          <div>
            <label className="mb-1.5 block text-[11px] font-medium uppercase tracking-wide" style={{ color: 'var(--muted)' }}>Recipient</label>
            <input
              value={recipient}
              onChange={e => setRecipient(e.target.value)}
              placeholder="0x…"
              className="field field-mono"
            />
          </div>
          <div>
            <label className="mb-1.5 block text-[11px] font-medium uppercase tracking-wide" style={{ color: 'var(--muted)' }}>Amount (USDC)</label>
            <input
              inputMode="decimal"
              value={amount}
              onChange={e => { const v = e.target.value.replace(/[^0-9.]/g, ''); if (v === '' || /^\d*\.?\d*$/.test(v)) setAmount(v) }}
              placeholder="0.00"
              className="field field-amount"
            />
          </div>
          <div>
            <label className="mb-1.5 block text-[11px] font-medium uppercase tracking-wide" style={{ color: 'var(--muted)' }}>Reason</label>
            <input
              value={reason}
              onChange={e => setReason(e.target.value)}
              placeholder="e.g. API usage invoice #42"
              className="field"
            />
          </div>

          {isSuccess && hash && (
            <a
              href={buildTxExplorerUrl(CHAIN_ID, hash)}
              target="_blank" rel="noreferrer"
              className="mono flex items-center gap-1.5 text-[12px] transition-opacity hover:opacity-80"
              style={{ color: 'var(--accent)' }}
            >
              Proposal submitted <ArrowUpRight className="size-3" />
            </a>
          )}

          <button
            type="submit"
            disabled={!canPropose || isPending || isConfirming || !recipient || !amount}
            className="btn-primary"
          >
            {isPending ? <><Loader2 className="size-4 animate-spin" /> Confirm in wallet…</>
              : isConfirming ? <><Loader2 className="size-4 animate-spin" /> Confirming…</>
              : wrongChain ? 'Switch to Arc Testnet'
              : 'Propose Payment'}
          </button>
        </form>
      )}
    </div>
  )
}
