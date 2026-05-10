# Aletheia Protocol

> **Parametric on-chain protection for the agentic economy.**
> When an AI agent causes a verifiable financial loss, the pool pays out automatically.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Live on Base Sepolia](https://img.shields.io/badge/live-Base_Sepolia-00d4aa.svg)](https://www.aletheiaprotocol.io)
[![Built on Chrysalis](https://img.shields.io/badge/built_on-Chrysalis-7c5cff.svg)](https://github.com/imago-labs/chrysalis)

Aletheia is a discretionary mutual protection protocol for autonomous AI agents. Operators register their agents' financial boundaries on-chain. When a breach occurs, Claude on Bedrock arbitrates against on-chain evidence and the USDC pool pays out automatically. No human testimony, no subjective dispute resolution.

**Live demo:** [aletheiaprotocol.io](https://www.aletheiaprotocol.io)

---

## What's in this repo

This repository contains the public protocol layer (Apache 2.0):

| Path | Contents |
|---|---|
| `contracts/` | `AletheiaPool.sol`, the V2 mutual pool and agent registry contract |
| `abis/` | Compiled contract ABIs for integration |
| `scripts/` | Deployment scripts for Base Sepolia and Base mainnet |
| `spec/` | Protocol specification: pool economics, claim flow, verifier interface |
| `examples/` | Integration examples for agent operators |

The off-chain implementation (Bedrock arbitrator, x402 payments, frontend dashboard) is operated by Imago Labs and is not open-sourced.

---

## How it works

1. **Register an agent.** Operator submits agent profile, system prompt hash, tool manifest hash, and spend cap on-chain.
2. **Purchase coverage.** Operator pays USDC contribution into the pool. Policy is recorded on-chain.
3. **Agent acts.** Each consequential action is logged on-chain via `logAction`. Runtime prompt hash is compared to the registered hash, and deviations are flagged.
4. **Breach occurs.** Agent transaction exceeds registered spend cap.
5. **Claim filed.** User submits transaction hash and 10 USDC claim bond.
6. **Claude arbitrates.** Bedrock-hosted Claude evaluates `tx_amount > spend_cap` against the on-chain evidence. The verdict is mathematical, not interpretive.
7. **Payout.** If upheld, the USDC pool pays the claimant. If rejected, the bond is forfeited to the pool. State updates are atomic.

---

## Currently covered

- ✅ **Category 1: Spend Cap Breach.** Live on Base Sepolia.

## Roadmap

- 🟡 **Category 2: Slippage Breach.** Q3 2026.
- 🟡 **Category 3: Liquidation Breach.** Q3 2026.
- 🟡 **Pluggable arbitrator architecture.** Third-party harm-category verifiers can plug into the same pool, bond, and payout machinery.

---

## Built on Chrysalis

Aletheia is the first vertical product built on the [Chrysalis](https://github.com/imago-labs/chrysalis) accountability platform.

**Planned integration (Q3 2026, not yet live):**

- Chrysalis identity hashes register epistemic provenance alongside wallet
- Mirror's CPI feeds dynamic risk pricing
- Memoir's audit log supplements claim evidence
- Shield routes attestations across Solana and Base

Once integrated, agents governed by Chrysalis are expected to qualify for reduced monthly contributions, reflecting their lower measurable risk profile. Final pricing is subject to actuarial review.

---

## Smart contracts

`AletheiaPool.sol` is deployed on **Base Sepolia** for testnet validation. Mainnet deployment is gated on (a) full audit, (b) multisig oracle replacement of the current single-EOA oracle, and (c) integration with Chrysalis Shield for cross-chain attestation receipts.

See [`spec/`](./spec/) for the full protocol specification including pool economics, reserve ratios, claim flow, and the verifier interface.

---

## About

Aletheia is operated by [Imago Labs](https://github.com/imago-labs).

Originally built at the EasyA x CoinDesk Consensus Hackathon Miami 2026 by [Crystal Tubbs](https://github.com/Msmetamorphosis), with **Esteban Cerda Le-Bert** refining the initial financial model and pool economics (V1). Now operated as the flagship product of the Chrysalis platform.

---

## License and governance

Apache License 2.0. See [`LICENSE`](./LICENSE) for the full text.

- [`LICENSING.md`](./LICENSING.md): what is open, what is closed, and how the two relate.
- [`TRADEMARK.md`](./TRADEMARK.md): what you can and cannot do with the Aletheia name and marks, including on-chain naming.
- [`CONTRIBUTOR_LICENSE_AGREEMENT.md`](./CONTRIBUTOR_LICENSE_AGREEMENT.md): terms for code, spec, and audit contributions.
- [`SECURITY.md`](./SECURITY.md): how to report a vulnerability privately.

---

Make it a great day.
