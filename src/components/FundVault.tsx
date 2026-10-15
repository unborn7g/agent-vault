import { useState } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useSwitchChain } from 'wagmi'
import { erc20Abi } from 'viem'
import { arcTestnet } from 'viem/chains'
import { toast } from 'sonner'
import { Loader2, ArrowUpRight, CheckCircle2 } from 'lucide-react'
import { getUsdc, buildTxExplorerUrl } from '@/onchain-facts'
import { parseAmount } from '@/onchain-money'
import { AGENT_VAULT_ABI } from '@/agentVaultAbi'

const CHAIN_ID = arcTestnet.id
const usdcFact = getUsdc(CHAIN_ID)!

interface FundVaultProps {
  contractAddress: `0x${string}` | undefined
}

export function FundVault({ contractAddress }: FundVaultProps) {
  const { chainId, isConnected } = useAccount()
  const { switchChain } = useSwitchChain()
  const [amount, setAmount] = useState('')
  const [step, setStep] = useState<'approve' | 'fund'>('approve')
  const [approveHash, setApproveHash] = useState<`0x${string}` | undefined>()
  const [fundHash, setFundHash] = useState<`0x${string}` | undefined>()

  const wrongChain = isConnected && chainId !== CHAIN_ID

  const { writeContract: writeApprove, isPending: approvePending } = useWriteContract()
  const { isLoading: approveConfirming, isSuccess: approveSuccess } = useWaitForTransactionReceipt({ hash: approveHash })
  const { writeContract: writeFund, isPending: fundPending } = useWriteContract()
  const { isLoading: fundConfirming, isSuccess: fundSuccess } = useWaitForTransactionReceipt({ hash: fundHash })

  function handleApprove(e: React.FormEvent) {
    e.preventDefault()
    if (!contractAddress) return
    if (wrongChain) { switchChain({ chainId: CHAIN_ID }); return }
    let parsed: bigint
    try { parsed = parseAmount(CHAIN_ID, amount).raw } catch { toast.error('Invalid amount'); return }
    writeApprove(
      { address: usdcFact.address as `0x${string}`, abi: erc20Abi, functionName: 'approve', args: [contractAddress, parsed] },
      {
        onSuccess: (h) => { setApproveHash(h); setStep('fund') },
        onError: (err) => toast.error(err.message.slice(0, 80)),
      },
    )
  }

  function handleFund() {
    if (!contractAddress) return
    if (wrongChain) { switchChain({ chainId: CHAIN_ID }); return }
    let parsed: bigint
    try { parsed = parseAmount(CHAIN_ID, amount).raw } catch { toast.error('Invalid amount'); return }
    writeFund(
      { address: contractAddress, abi: AGENT_VAULT_ABI, functionName: 'fund', args: [parsed] },
      {
        onSuccess: (h) => { setFundHash(h); setStep('approve'); setAmount('') },
        onError: (err) => toast.error(err.message.slice(0, 80)),
      },
    )
  }

  const busy = approvePending || approveConfirming || fundPending || fundConfirming

  return (
    <div className="card p-5">
      <p className="section-label mb-4">Fund Vault</p>

      {!isConnected ? (
        <p className="text-[13px]" style={{ color: 'var(--muted)' }}>Connect wallet to fund the vault.</p>
      ) : (
        <form
          onSubmit={step === 'approve' ? handleApprove : (e) => { e.preventDefault(); handleFund() }}
          className="space-y-4"
        >
          <div>
            <label className="mb-1.5 block text-[11px] font-medium uppercase tracking-wide" style={{ color: 'var(--muted)' }}>Amount (USDC)</label>
            <input
              inputMode="decimal"
              value={amount}
              onChange={e => { const v = e.target.value.replace(/[^0-9.]/g, ''); if (v === '' || /^\d*\.?\d*$/.test(v)) setAmount(v) }}
              placeholder="0.00"
              className="field field-amount"
              disabled={step === 'fund'}
            />
          </div>

          {/* Step indicators */}
          <div className="space-y-2">
            {[
              { n: 1, done: approveSuccess, active: step === 'approve', label: 'Allow USDC', sub: 'Permit the vault to pull from your wallet' },
              { n: 2, done: fundSuccess, active: step === 'fund', label: 'Transfer to Vault', sub: 'Moves USDC into the contract' },
            ].map(s => (
              <div key={s.n} className="flex items-start gap-3">
                <div
                  className="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full text-[11px] font-bold"
                  style={{
                    background: s.done ? 'var(--success-dim)' : s.active ? 'var(--accent)' : 'var(--surface-muted)',
                    color: s.done ? 'var(--success)' : s.active ? 'var(--accent-text)' : 'var(--subtle)',
                    border: s.active ? 'none' : '1px solid var(--border)',
                  }}
                >
                  {s.done ? <CheckCircle2 className="size-3.5" /> : s.n}
                </div>
                <div>
                  <p className="text-[13px] font-medium" style={{ color: s.active ? 'var(--ink)' : 'var(--muted)' }}>{s.label}</p>
                  <p className="text-[11px]" style={{ color: 'var(--subtle)' }}>{s.sub}</p>
                </div>
              </div>
            ))}
          </div>

          {fundSuccess && fundHash && (
            <a
              href={buildTxExplorerUrl(CHAIN_ID, fundHash)} target="_blank" rel="noreferrer"
              className="mono flex items-center gap-1.5 text-[12px] transition-opacity hover:opacity-80"
              style={{ color: 'var(--accent)' }}
            >
              Vault funded <ArrowUpRight className="size-3" />
            </a>
          )}

          <button
            type="submit"
            disabled={busy || !amount || !contractAddress}
            className="btn-primary"
          >
            {busy ? <><Loader2 className="size-4 animate-spin" /> Confirming…</>
              : wrongChain ? 'Switch to Arc Testnet'
              : step === 'approve' ? 'Allow USDC'
              : 'Transfer to Vault'}
          </button>
        </form>
      )}
    </div>
  )
}
