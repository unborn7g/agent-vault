import { ConnectKitButton } from 'connectkit'
import { ShieldCheck, ArrowUpRight } from 'lucide-react'
import { buildAddressExplorerUrl } from '@/onchain-facts'
import { arcTestnet } from 'viem/chains'

interface VaultHeaderProps {
  contractAddress: string | undefined
}

export function VaultHeader({ contractAddress }: VaultHeaderProps) {
  const explorerUrl = contractAddress
    ? buildAddressExplorerUrl(arcTestnet.id, contractAddress)
    : undefined

  return (
    <header className="mx-auto flex max-w-[720px] items-center justify-between px-5 py-5">
      <div className="flex items-center gap-3">
        <div
          className="flex size-9 items-center justify-center rounded-2xl"
          style={{ background: 'var(--accent-dim)', border: '1px solid rgba(45,212,191,0.2)' }}
        >
          <ShieldCheck className="size-[18px]" style={{ color: 'var(--accent)' }} />
        </div>
        <div>
          <h1 className="display text-[17px] font-semibold leading-none tracking-tight" style={{ color: 'var(--ink)' }}>
            AgentVault
          </h1>
          {contractAddress && explorerUrl ? (
            <a
              href={explorerUrl}
              target="_blank"
              rel="noreferrer"
              className="mono mt-0.5 flex items-center gap-1 text-[11px] transition-colors"
              style={{ color: 'var(--muted)' }}
              onMouseEnter={e => (e.currentTarget.style.color = 'var(--accent)')}
              onMouseLeave={e => (e.currentTarget.style.color = 'var(--muted)')}
            >
              {contractAddress.slice(0, 8)}…{contractAddress.slice(-6)}
              <ArrowUpRight className="size-3" />
            </a>
          ) : (
            <span className="mt-0.5 block text-[11px]" style={{ color: 'var(--subtle)' }}>
              Not deployed
            </span>
          )}
        </div>
      </div>
      <ConnectKitButton />
    </header>
  )
}
