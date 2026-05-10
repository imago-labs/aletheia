# Integration Examples

> Reference integrations for agent operators and verifier builders.

This directory contains worked examples for common integration patterns. Each example is self-contained and runnable against a local Hardhat node or Base Sepolia.

## Available examples

| Example | Status | Purpose |
|---|---|---|
| `register-agent/` | Coming with first alpha | Minimal operator flow: register an agent, purchase coverage, log an action |
| `file-claim/` | Coming with first alpha | User flow: file a claim against a logged action with a 10 USDC bond |
| `verifier-stub/` | Coming with first alpha | Reference implementation of the verifier interface for a custom harm category |

## Prerequisites

- Node 20+
- Hardhat 2.22+
- A funded Base Sepolia account (or local Hardhat node)
- Test USDC on Base Sepolia (faucet links in the spec)

## Quick start

```bash
# Coming with first alpha release.
cd register-agent
npm install
cp .env.example .env  # fill in keys
npx hardhat run scripts/run.js --network baseSepolia
```

---

Make it a great day.
