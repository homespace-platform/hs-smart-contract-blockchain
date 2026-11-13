---
name: solidity-safety-review
description: Review HomeSpace Solidity changes for ownership and access control, ETH payment integrity, replay and idempotency, external-call safety, document registry invariants, ABI compatibility and deployment risks. Use when an explicit smart contract safety review is requested.
---

# Solidity Safety Review

## Mode

Review-only by default. Do not edit files unless the user asks for fixes. Do not deploy, broadcast transactions, read `.env`, or call live networks.

## Procedure

Read the changed Solidity files in `src/`, the matching tests in `test/`, and `foundry.toml`. Read `README.md` for the registry data model when relevant.

1. **Ownership and access control.** Every state-changing function has the intended modifier or check. Ownership stays two-step (`Ownable2Step`). No reachable `renounceOwnership()` without explicit authorization. `quoteSigner` changes are owner-only and reject zero.
2. **Financial integrity.** `msg.value` equals the signed `amountWei`; funds go only to the signed `recipient`; no stuck ETH; no rounding or unit confusion between wei and other units; zero amount and zero address rejected.
3. **Replay and idempotency.** `paymentId` single use; quote expiry; payer bound to `msg.sender`; EIP-712 domain and typehash match the backend signer; signature malleability handled by the library; duplicate `documentId` rejected.
4. **External-call safety.** State is updated before external calls; `nonReentrant` kept; failed transfers revert; no unchecked low-level calls; no new callbacks to untrusted addresses.
5. **Document registry invariants.** Write-once proofs; non-zero IDs and hashes; lineage rules (one deposit and one lease per case, annex only after lease); hash semantics (SHA-256 of exact signed PDF bytes); no PII or private data on-chain; proofs are not described as legal verification.
6. **ABI compatibility.** Compare public functions, events, custom errors and getters with the previous version. Identify backend (`hs-core-api`) and guide documents that depend on them. A breaking change requires redeployment and backend address update; flag it. Storage layout only matters if upgradeability is introduced; do not assume it.
7. **Deployment risks.** Constructor arguments, owner and signer addresses, deploy script behavior, hard-coded addresses, and any command that would broadcast or spend ETH. Nothing is deployed automatically.
8. **Foundry tests.** List the existing tests covering each changed behavior and the missing ones (access denied, duplicate ID, replay, expired quote, wrong payer, wrong value, failed transfer, reentrancy attempt, lineage violations). Suggest `forge test --match-contract` or `--match-test` commands scoped to them.

## Output

Findings ordered by severity with file and line references and a concrete failure scenario for each. List missing tests. State what was reviewed and what was not run (for example: no `forge test`, no fork or live network). If no issue is found, say so.
