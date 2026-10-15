# AgentVault

> Built with Arc Studio — money-powered apps in minutes

A USDC payments vault on Arc for AI agents and small teams.

---

## What This App Does

AgentVault lets an owner (typically a team or automation operator) manage USDC outflows through a governed proposal lifecycle: agents propose payments, the owner approves/rejects/executes them. Supports escrow (lock funds for a payee pending a condition), split payments (batch pay in basis points), and a full on-chain audit log via events.

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS
- Web3: wagmi v2, viem v2, ConnectKit
- Contracts: Solidity ^0.8.20 + Foundry. Sources in `contracts/`, unit tests in `contracts/test/*.t.sol`. Build with `forge build`, test with `forge test`.
- Wallet: injected (MetaMask, etc.)
- Chain: Arc Testnet (Chain ID: 5042002, `arcTestnet` from `viem/chains`)
- Token: USDC (6 decimals, address 0x3600000000000000000000000000000000000000 on Arc Testnet)
- Toasts: Sonner

## Contract: AgentVault

**Source:** `contracts/AgentVault.sol`
**Deployed address (v4 — ACTIVE):** `0x6a214b64b9e6d66b09e708fe1f2a6cbba3374538` on Arc Testnet
**Deploy tx:** `0x8d4e8f5fef7e52109624de2fa5bb70513506b27c01fdcc07b371bf53c6111214`
**Explorer:** https://explorer.testnet.arc.io/address/0x6a214b64b9e6d66b09e708fe1f2a6cbba3374538
**Caps:** perTxCap = 250 USDC, dailyCap = 600 USDC
**Owner (verified on-chain):** `0x51039aF25D8AD8B04B86ed89AacBCb9cDd526c9c` (user wallet — hardcoded in constructor)

**Constructor args:**
- `usdcToken`: USDC address on Arc Testnet = `0x3600000000000000000000000000000000000000`
- `_perTxCap`: per-transaction cap in USDC 6-decimal units (e.g. `100000000` = 100 USDC)
- `_dailyCap`: daily cap in USDC 6-decimal units (e.g. `1000000000` = 1000 USDC)

**Key features:**
- `proposePayment(recipient, amount, reason)` — onlyProposer (owner or approved agent)
- `approveProposal/rejectProposal/executeProposal` — onlyOwner
- `retryProposal(id, newRecipient)` — retry a Failed proposal with a new recipient
- `createEscrow/releaseEscrow/refundEscrow` — lock/release/refund USDC
- `splitPayment(recipients[], bps[], totalAmount)` — owner splits total by basis points
- `fund(amount)` — anyone funds the vault (requires prior ERC-20 approve)
- `setCaps/approveAgent/revokeAgent` — onlyOwner admin

**Security:** All outbound paths (proposals, escrow releases, split payments) enforce daily + per-tx caps. All transfers use try/catch to isolate blocklisted recipients without reverting the whole transaction.

**Tests:** 130+ Foundry unit tests in `contracts/test/AgentVault.t.sol` + `AgentVaultNew.t.sol`. 3 invariants fuzz-tested.

## Key Files

- `src/App.tsx` — Main page composition
- `src/components/VaultHeader.tsx` — Header + wallet connect + contract address link
- `src/components/VaultStats.tsx` — Live vault balance, daily spend bar, per-tx cap
- `src/components/ProposeForm.tsx` — Propose a payment (agents + owner)
- `src/components/ProposalsList.tsx` — All proposals with Approve/Reject/Execute/Retry
- `src/components/EscrowPanel.tsx` — Create, release, refund escrows
- `src/components/SplitCalc.tsx` — Split payment builder + executor
- `src/components/FundVault.tsx` — 2-step approve + fund flow
- `src/components/AuditLog.tsx` — On-chain event log (polls getLogs every 15s)
- `src/agentVaultAbi.ts` — Full ABI for AgentVault
- `src/config.ts` — wagmi config
- `.env` — VITE_AGENT_VAULT_ADDRESS (set after deploy)

## To Deploy

1. `forge build` (in `/home/user/app`)
2. Use the deploy flow with constructor args:
   - `usdcToken`: `0x3600000000000000000000000000000000000000`
   - `_perTxCap`: e.g. `100000000` (100 USDC)
   - `_dailyCap`: e.g. `1000000000` (1000 USDC)
3. Set `VITE_AGENT_VAULT_ADDRESS=<deployed address>` in `.env`
4. Restart dev server so Vite picks up the new env var

## To Run

```bash
bun install
bun run dev
```
