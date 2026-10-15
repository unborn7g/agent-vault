import { useAccount, useReadContracts } from 'wagmi'
import { arcTestnet } from 'viem/chains'
import { AlertTriangle } from 'lucide-react'
import { AGENT_VAULT_ABI } from '@/agentVaultAbi'
import { VaultHeader } from '@/components/VaultHeader'
import { VaultStats } from '@/components/VaultStats'
import { ProposeForm } from '@/components/ProposeForm'
import { ProposalsList } from '@/components/ProposalsList'
import { EscrowPanel } from '@/components/EscrowPanel'
import { SplitCalc } from '@/components/SplitCalc'
import { FundVault } from '@/components/FundVault'
import { AuditLog } from '@/components/AuditLog'

const CHAIN_ID = arcTestnet.id

const RAW_ADDR = import.meta.env.VITE_AGENT_VAULT_ADDRESS as string | undefined
const CONTRACT_ADDRESS: `0x${string}` | undefined =
  RAW_ADDR && RAW_ADDR.startsWith('0x') ? (RAW_ADDR as `0x${string}`) : undefined

export default function App() {
  const { address, isConnected } = useAccount()

  const { data: meta } = useReadContracts({
    contracts: [
      { address: CONTRACT_ADDRESS!, abi: AGENT_VAULT_ABI, functionName: 'owner', chainId: CHAIN_ID },
      { address: CONTRACT_ADDRESS!, abi: AGENT_VAULT_ABI, functionName: 'proposalsCount', chainId: CHAIN_ID },
      { address: CONTRACT_ADDRESS!, abi: AGENT_VAULT_ABI, functionName: 'escrowsCount', chainId: CHAIN_ID },
      {
        address: CONTRACT_ADDRESS!, abi: AGENT_VAULT_ABI, functionName: 'isAgent',
        args: address ? [address] : ['0x0000000000000000000000000000000000000000'],
        chainId: CHAIN_ID,
      },
    ],
    query: { enabled: !!CONTRACT_ADDRESS, refetchInterval: 8000 },
  })

  const owner = meta?.[0]?.result
  const proposalCount = Number(meta?.[1]?.result ?? 0n)
  const escrowCount = Number(meta?.[2]?.result ?? 0n)
  const isAgent = meta?.[3]?.result

  const isOwner = !!(address && owner && address.toLowerCase() === owner.toLowerCase())
  const canPropose = !!(isOwner || (isConnected && isAgent))

  return (
    <div className="min-h-dvh" style={{ background: 'var(--bg-gradient)', backgroundColor: 'var(--bg)' }}>
      <VaultHeader contractAddress={CONTRACT_ADDRESS} />

      <main className="mx-auto max-w-[720px] space-y-4 px-4 pb-32 pt-2">
        {!CONTRACT_ADDRESS && (
          <div
            className="flex items-start gap-3 rounded-2xl p-4"
            style={{ background: 'rgba(251,191,36,0.06)', border: '1px solid rgba(251,191,36,0.18)' }}
          >
            <AlertTriangle className="mt-0.5 size-4 shrink-0" style={{ color: 'var(--warning)' }} />
            <div>
              <p className="text-[13px] font-semibold" style={{ color: 'var(--warning)' }}>Contract not deployed</p>
              <p className="mt-0.5 text-[12px]" style={{ color: 'var(--muted)' }}>
                Deploy AgentVault.sol and set <span className="mono">VITE_AGENT_VAULT_ADDRESS</span> in <span className="mono">.env</span>, then restart the dev server.
              </p>
            </div>
          </div>
        )}

        {/* Hero: vault balance + caps */}
        <VaultStats contractAddress={CONTRACT_ADDRESS} />

        {/* Actions: propose + fund side by side on wide, stacked on mobile */}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <ProposeForm contractAddress={CONTRACT_ADDRESS} />
          <FundVault contractAddress={CONTRACT_ADDRESS} />
        </div>

        {/* Proposals list */}
        <ProposalsList
          contractAddress={CONTRACT_ADDRESS}
          isOwner={isOwner}
          proposalCount={proposalCount}
        />

        {/* Escrow */}
        <EscrowPanel
          contractAddress={CONTRACT_ADDRESS}
          isOwner={isOwner}
          canPropose={canPropose}
          escrowCount={escrowCount}
        />

        {/* Split payment */}
        <SplitCalc contractAddress={CONTRACT_ADDRESS} isOwner={isOwner} />

        {/* Audit log */}
        <AuditLog contractAddress={CONTRACT_ADDRESS} />
      </main>
    </div>
  )
}
