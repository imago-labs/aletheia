# Aletheia Protocol Specification

> Discretionary mutual protection for autonomous AI agents.
> Version 2. Status: live on Base Sepolia.

This document specifies the on-chain protocol implemented by `AletheiaPool.sol`. It is the authoritative reference for integrators, auditors, and anyone implementing a compatible verifier.

---

## 1. Overview

Aletheia is a discretionary mutual. Agent operators contribute USDC to a shared pool, register their agents' financial boundaries on-chain, and can file claims when those boundaries are breached. Claims are arbitrated by a programmatic oracle (Claude on Bedrock for V2) and paid out from the pool.

The protocol separates four concerns:

| Concern | Where it lives | Why |
|---|---|---|
| Settlement | `AletheiaPool.sol` (this repo) | Reusable across harm categories |
| Verification | Off-chain arbitrator (private) | Specific to harm category |
| Risk pricing | Off-chain risk engine (private) | Operator-specific |
| Identity | Chrysalis platform (Q3 2026) | Cross-chain epistemic provenance |

This separation is what lets future verifiers plug into the same pool without rewriting settlement logic.

---

## 2. Roles

| Role | Capability | Today | Future |
|---|---|---|---|
| Operator | Registers agents, purchases coverage, files claims on behalf of users | EOA | Multisig, smart account |
| User | Files claims when harmed by an operator's agent | EOA | Smart account |
| Oracle | Submits arbitrator verdicts, triggers payouts | Single EOA (Imago Labs) | Multisig oracle, decentralized verifiers |
| Pool | Holds USDC reserves, enforces reserve ratio, processes payouts | Contract | Same |

---

## 3. State

`AletheiaPool.sol` maintains:

- **Agent registry.** `agentId -> AgentProfile { operator, systemPromptHash, toolManifestHash, spendCap, registeredAt, status }`
- **Coverage registry.** `policyId -> Policy { agentId, tier, contributionAmount, startTime, endTime }`
- **Action log.** `actionId -> Action { agentId, txHash, amount, timestamp, runtimePromptHash }`
- **Claim registry.** `claimId -> Claim { actionId, claimant, bondAmount, status, verdict, payoutAmount }`
- **Pool state.** `totalReserves`, `totalCoverage`, `reserveRatio`, `circuitBreakerActive`

---

## 4. Lifecycle

### 4.1 Agent registration

```
operator → registerAgent(systemPromptHash, toolManifestHash, spendCap)
          → emits AgentRegistered(agentId, operator, ...)
```

Hashes are keccak256 of canonical UTF-8 source. The registered prompt and tool manifest are the agent's declared identity. Runtime deviations are flagged at action time.

### 4.2 Coverage purchase

```
operator → purchaseCoverage(agentId, tier, durationDays)
          → transfers USDC contribution into pool
          → emits CoveragePurchased(policyId, agentId, ...)
```

Tiers are defined off-chain by the risk engine. The contract enforces the contribution amount and policy term but does not interpret the tier label.

### 4.3 Action logging

```
operator → logAction(agentId, txHash, amount, runtimePromptHash)
          → if runtimePromptHash != registeredPromptHash, sets driftFlag
          → emits ActionLogged(actionId, agentId, ...)
```

Operators are required to log consequential actions. The runtime prompt hash compared to the registered hash is the cheapest available drift signal.

### 4.4 Claim filing

```
user → fileClaim(actionId)
     → transfers 10 USDC bond into contract
     → emits ClaimFiled(claimId, actionId, claimant)
```

The claim references a specific logged action. Claims with no corresponding action are rejected at the contract level.

### 4.5 Arbitration

```
oracle → submitVerdict(claimId, verdict, payoutAmount)
       → if upheld: pool pays claimant payoutAmount, returns bond
       → if rejected: bond is forfeited to pool
       → emits ClaimResolved(claimId, verdict, payoutAmount)
```

The oracle's verdict is binary (UPHELD / REJECTED) with a payout amount denominated in USDC. State updates are atomic per claim.

---

## 5. Reserve management

The pool maintains a target reserve ratio (default 150 percent of total active coverage). When the ratio falls below threshold:

1. New coverage purchases are paused
2. The circuit breaker is triggered, blocking all payouts
3. The oracle pauses verdict submissions until reserves are restored

This prevents a cascade of breaches from emptying the pool.

---

## 6. Verifier interface

Future arbitrators (slippage, liquidation, custom) plug into the pool via the verifier interface defined in `spec/VERIFIER.md`. A verifier:

- Accepts a `Claim` and supporting on-chain evidence
- Returns `{ verdict: bool, payoutAmount: uint256, reasoning: bytes32 }`
- Is registered to a specific harm category by governance

The pool, bond, USDC payout, and registry are reusable across verifiers.

---

## 7. Currently covered

**Category 1: Spend Cap Breach.** A logged action has `amount > spendCap` for its agent.

Verdict logic is mathematical: `tx.amount > agent.spendCap`. The oracle validates the on-chain evidence and submits the verdict. The frontend exposes a one-click claim flow.

---

## 8. Roadmap

- **Category 2: Slippage Breach.** Q3 2026. Verifier compares on-chain swap output against operator-declared slippage tolerance using DEX price oracles at action timestamp.
- **Category 3: Liquidation Breach.** Q3 2026. Verifier inspects lending protocol state to confirm forced position closure exceeded operator-declared LTV bounds.
- **Multisig oracle.** Q3 2026. Replace single-EOA oracle with a multisig (initial signers: Imago Labs, two independent operators).
- **Chrysalis identity integration.** Q3 2026. `registerAgent` accepts `chrysalisIdentityHash` for cross-chain epistemic provenance.

---

## 9. Mainnet readiness

Mainnet deployment is gated on:

1. Full third-party audit (target: Q3 2026)
2. Multisig oracle live on Base Sepolia for at least 30 days
3. Reserve seed of at least 50,000 USDC committed
4. Chrysalis Shield integration for cross-chain attestation receipts

Until then, all deployments are testnet only.

---

## 10. References

- `contracts/AletheiaPool.sol` for the implementation
- `spec/VERIFIER.md` for the verifier interface (forthcoming)
- `spec/POOL_ECONOMICS.md` for reserve ratio and tier mechanics (forthcoming)
- [aletheiaprotocol.io](https://www.aletheiaprotocol.io) for the live operator dashboard
- [imago-labs/chrysalis](https://github.com/imago-labs/chrysalis) for the accountability platform Aletheia is built on

---

Make it a great day.
