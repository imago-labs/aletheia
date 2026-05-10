# Licensing

Aletheia is split into open contracts and a closed application stack. This document explains what is in which repository and what license applies.

## Open contracts: this repository

Everything in this repository (`imago-labs/aletheia`) is licensed under the **Apache License, Version 2.0**.

The open repository includes:

- `contracts/`. `AletheiaPool.sol` and supporting Solidity sources.
- `spec/PROTOCOL.md`: the full protocol specification.
- `scripts/`. Hardhat deployment scripts.
- `abis/`, `examples/`, and surrounding documentation.

You can use, modify, fork, audit, and integrate these contracts under the terms of Apache 2.0. See [LICENSE](LICENSE) for the full text.

The Apache 2.0 license includes an explicit patent grant from contributors.

## Closed application stack: separate repository

The hosted application stack is maintained in a separate, private repository (`imago-labs/aletheia-platform`). It is **not** licensed under Apache 2.0.

The closed stack includes:

- The premium calculator and underwriting models.
- The application backend (claims service, indexer, attester wiring).
- The frontend, dashboard, and demo applications.

These components are All Rights Reserved, © 2026 Imago Labs / Metamorphic Curations LLC. The on-chain protocol is fully specified in this repository so anyone can integrate without depending on the closed stack.

For commercial licensing, integration partnerships, or hosted access, contact hello@imagolabs.dev.

## Audit and deployment status

The contracts in this repository have not been formally audited. Treat any deployment as experimental until an audit report is published in this repository.

Aletheia V1 currently covers Category 1 (Spend Cap Breach) on Base Sepolia. Categories 2 and 3 are scheduled for Q3 2026. Production mainnet deployment will be announced in this repository's releases.

## Contributing

By submitting a pull request to this repository, you agree to the terms in [CONTRIBUTOR_LICENSE_AGREEMENT.md](CONTRIBUTOR_LICENSE_AGREEMENT.md). The CLA confirms that you have the right to contribute and that you license your contribution under Apache 2.0.

## Trademarks

"Aletheia", "Imago Labs", and "Chrysalis" are trademarks of Metamorphic Curations LLC. The Apache 2.0 license does not grant trademark rights. See [TRADEMARK.md](TRADEMARK.md) for usage guidelines.

## Questions

For licensing, audit coordination, or commercial inquiries, contact hello@imagolabs.dev.
