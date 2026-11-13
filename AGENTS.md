# HomeSpace Smart Contracts — Agent Instructions

## Scope

Solidity 0.8.30 contracts built and tested with Foundry (`foundry.toml`, EVM `cancun`), using OpenZeppelin from `lib/` (a dependency; never edit it). Target network is Ethereum Sepolia.

- `src/ContractDocumentRegistry.sol`: owner-only registry of document proofs (`documentId` → SHA-256 `documentHash` + `registeredAt`) with case lineage (`caseId`, `documentKind`: 1 deposit, 2 lease, 3 annex). `Ownable2Step`.
- `src/EthPayment.sol`: ETH membership payment. Pays a backend-signed EIP-712 quote (`pay`), one-time `paymentId`, `quoteSigner` set by owner. `Ownable2Step`, `ReentrancyGuard`.

Read `README.md` for the registry data model. `CONTRACT_DOCUMENT_REGISTRY.md` and `ETH_PAYMENT.md` are deployment and manual-test guides; read them only for deployment or ABI questions. The backend (`hs-core-api`) consumes these ABIs and configured addresses.

## Smart Contract Safety

- Preserve access control (`onlyOwner`, quote signer checks). Do not widen who can write proofs or set the quote signer.
- Preserve safe ownership transfer (two-step `Ownable2Step`). Never call or add a path to `renounceOwnership()` without explicit, reviewed authorization: it permanently stops proof writing.
- Preserve invariants: a `documentId` is written once and never updated or deleted; zero IDs and zero hashes are rejected; lineage rules (one deposit and one lease per `caseId`, annex only after lease) hold; a `paymentId` can be paid only once.
- Review ABI compatibility before any change to a public function, event, error or storage getter. The backend, indexers and manual guides depend on them. An ABI change needs a new deployment and a backend address update; state that in the report.
- The contracts are not upgradeable. Do not assume proxies. If upgradeability is introduced, review storage-layout compatibility first.

## Document Integrity

- `documentHash` semantics: SHA-256 of the exact signed PDF bytes, computed off-chain. `documentId` is an opaque `bytes32` for one PDF. Preserve these semantics.
- Never publish PII, private document contents or private URLs on-chain.
- Preserve the document lineage constraints.
- A blockchain proof is not legal verification of contract content, identity or signatures. Do not word code, docs or comments to imply otherwise.
- Retry behavior: `DocumentAlreadyRegistered` means read the existing proof and compare the hash. Do not change the ID to bypass it.

## Payment Security

- Check ETH accounting: `msg.value` equals the quoted `amountWei`, funds go only to the quoted `recipient`, and the contract does not retain unexpected ETH.
- Review duplicate transactions and replay: `paymentId` single use, quote expiry, payer equals `msg.sender`, signer equals `quoteSigner`, EIP-712 domain separation.
- Review state transitions: state (`paidPayments`) is updated before the external call.
- Review reentrancy and external-call risk for any change involving `call`, `transfer` or callbacks. Keep `nonReentrant`.

## Execution Safety

- Never deploy and never broadcast transactions automatically (`forge create`, `forge script --broadcast`, `cast send`).
- Never expose or print private keys, keystore passwords or RPC keys. Never use real credentials in tests. Do not read or print `.env`.
- Never change deployed contract addresses in backend or docs automatically.
- No live on-chain operations without explicit authorization. Read-only `cast call` / `cast code` still needs a concrete reason and an authorized RPC.
- Do not commit `out/`, `cache/` or `lib/` content or proof files containing live data.

## Verification

- Prefer Foundry unit tests: `forge test --match-contract <ContractTest>` or `--match-test <name>`. Tests live in `test/`. Use `forge build` for compilation only when `forge` is installed.
- Use static checks and local tests first. Use fuzz or invariant tests for payment and registry rules when the change affects them.
- Do not use live Sepolia transactions for ordinary verification.
- Risk: access control, payment logic, ABI, ownership and deployment scripts are L3. Documentation and comments are L1.
- Never claim tests passed unless `forge test` actually ran.

## Skills

- `solidity-safety-review`: explicit, review-only safety review of contract changes.

## Completion

Report changed contracts, ABI impact, verification that actually ran and deployment implications.
