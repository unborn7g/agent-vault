# AgentVault — A spending limit for AI agents, on Arc

You wouldn't give a new employee your company's unlimited credit card.
You wouldn't give a teenager your bank card with no limit.

**So why would you give an AI agent an unlimited wallet?**

That is the problem AgentVault solves — in one idea simple enough to say out loud:

## One sentence
_A human sets the limit once. The agent can spend inside it. It can never spend past it — and it can never raise its own limit._

Think of it like a prepaid card you top up for someone you trust-but-verify:
- You load the vault with USDC
- You sign the rules once: **“at most 250 USDC in one payment, at most 600 USDC in a day”**
- From then on, the agent can only *ask* (propose a payment). You approve. The money moves.
- The moment anything goes over the limit, the contract itself blocks it. Not a warning. Not a setting. **Blocked.**

No prompt, trick, or jailbreak can change that — the limit lives in the code, not in the chatbot.

## Why this matters right now
Agents are starting to pay for real things: API bills, cloud servers, data, other agents' work.
- A freelancer's agent paying a designer when the draft is delivered
- A small shop's agent restocking from a supplier under an agreed amount
- A dev team's agent settling metered API invoices every night

Every one of those needs the same thing a good manager has: **freedom to act, inside a budget a human approved.**

## What’s inside
- **Capped payments** — propose → approve → paid, with the limits enforced on *every* path out (no side doors)
- **Escrow** — “the money is locked; it releases when the work lands.” Perfect for gigs and deliverables
- **Splits** — pay three people their shares in one go (like splitting a bill, but for teams and creators)
- **A paper trail** — every top-up, approval, payment and block is recorded on-chain, visible to anyone

## See it (Arc Testnet)
- Contract: `0x6a214b64b9e6d66b09e708fe1f2a6cbba3374538`
- Explorer: https://explorer.testnet.arc.io/address/0x6a214b64b9e6d66b09e708fe1f2a6cbba3374538
- The vault’s owner is the human who signed the limit — set at deployment, verified on-chain
- Mainnet follows the same flow (build for **Arc Microgrants: Built with Arc Studio**, on DoraHacks)

## Built in Arc Studio
Contract + app generated and tested in **Arc Studio** — 130/130 tests, three audit rounds — then styled to a clean, Apple-grade dark UI where the hero moment is not a green chart. It’s the red **BLOCKED** banner when the ceiling holds.

## The 30-second demo
1. Agent asks for a normal payment → owner approves → USDC moves. ✅
2. Agent asks for more than the limit → **Blocked.** 🛑
Money moved. Money stopped. That’s the whole pitch.

## Run it
`bun install` (or `npm install`) → `bun run dev`. Connect a wallet on **Arc Testnet** (Chain ID 5042002). Free test USDC: https://faucet.circle.com
