# Security Policy

Aletheia is an on-chain accountability protocol. Vulnerabilities can result in direct loss of user funds, so we take disclosure seriously.

## Reporting a vulnerability

**Do not open a public GitHub issue or post in any public channel.**

**Email:** hello@imagolabs.dev

Use the subject line `SECURITY: <short description>`. PGP key on request.

When reporting, please include:

- A clear description of the issue and its potential impact, including whether funds are at risk.
- Affected contract(s), version or commit hash, and target chain (e.g., Base Sepolia).
- Steps to reproduce, including any test transactions, scripts, or proof-of-concept code.
- Whether the vulnerability has been disclosed elsewhere or exploited in the wild.
- How you would like to be credited in the eventual advisory, or whether you prefer to remain anonymous.

## What to expect

- **Acknowledgement** within 24 hours of receipt.
- **Initial triage** within 72 hours, including a severity assessment and whether emergency action (pause, withdraw, redeploy) is warranted.
- **Status updates** at least every 7 days until the issue is resolved or formally closed.
- **Coordinated disclosure**: once a fix is deployed and any necessary user actions are complete, we will publish a public advisory and credit reporters who wish to be named. Disclosure timing is calibrated to user safety, not to a fixed clock.

## Scope

In scope:

- All Solidity sources under `contracts/`.
- Deployment scripts under `scripts/` to the extent they affect on-chain configuration.
- The protocol specification in `spec/PROTOCOL.md` where a spec ambiguity creates implementation risk.
- Any live deployment of these contracts on Base Sepolia or future production networks announced in this repository's releases.

Out of scope:

- Closed-source components in `aletheia-platform` (calculator, backend, frontend, demo). Report those privately to hello@imagolabs.dev with subject `SECURITY (PLATFORM): <description>`.
- Vulnerabilities in third-party dependencies (OpenZeppelin, Solidity compiler, etc.). Please report upstream and notify us so we can pin or patch.
- Generic blockchain risks not specific to Aletheia (chain reorgs, MEV against unrelated transactions, RPC provider outages).
- Phishing sites, social engineering, or scams that impersonate Aletheia. Report those at hello@imagolabs.dev so we can list them publicly.

## Severity guidance

We use the following rough rubric to triage severity:

- **Critical**: direct loss of funds or permanent freezing of pool assets.
- **High**: indirect loss of funds, unauthorized claim approval, breach of solvency invariants in the spec.
- **Medium**: griefing attacks, gas-exhaustion edge cases, DoS against legitimate claims.
- **Low**: spec ambiguities, missing access modifiers without exploit path, gas optimizations with safety implications.
- **Informational**: documentation issues, code style, missing events.

## Bug bounty

A formal bounty program is not yet active. We will retroactively recognize and compensate good-faith reports for any deployment that handles real user funds. The current Base Sepolia deployment is testnet-only and uses no real assets.

## Hardening guidance for integrators

If you are integrating against Aletheia contracts:

- Pin to a specific commit or release; do not assume `main` is stable.
- Validate the protocol spec version returned by the deployed contract matches what your integration expects.
- Treat the on-chain attestation hashes as informational, not as a guarantee of off-chain claim validity. The attester is one input to your decision, not the sole one.
- Monitor for upgrade or pause events on the pool contract.

## Past advisories

None as of the current release.

This policy may be updated. The current version always lives at the root of this repository.
