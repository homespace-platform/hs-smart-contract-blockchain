# HomeSpace Smart Contracts — Agent Instructions

## Engineering standards

- Preserve business invariants, public contracts and backward compatibility. Keep authentication, authorization, input validation and error handling intact.
- Protect secrets and sensitive data in code, commits, tests, logs and reports. Treat third-party hooks as untrusted until reviewed and explicitly authorized.
- Change production configuration, deploy or run destructive data operations only when explicitly authorized for the target environment.
- Keep review tasks read-only unless the developer requests fixes.

## Execution policy

- **FAST** is the default for a small fix, one API, a simple UI or configuration change, or a limited refactor. Start as soon as the scope is clear. Use the fewest useful calls, with a soft ceiling of roughly 8–12 in normal conditions.
- **STANDARD** fits multi-file features, API contract changes, broader refactors and hard-to-reproduce bugs. Make a short plan, inspect affected dependencies and verify in one focused round after editing.
- **DEEP** is required for significant security, authentication, authorization, payment, deposit, transaction, contract lifecycle, migration, architecture or incident risk. Identify the relevant invariants and verify the affected boundaries, including failure and denied cases where applicable. Escalate by risk even for small changes.

### Work and tools

- Identify the goal and smallest correct scope. Read the directly affected files, then check callers or dependencies when the change can affect them. Plan mentally or in a few lines for complex work, then execute.
- Give each tool call a purpose that advances the request or reduces a real risk. Batch independent reads and search exact paths or symbols. Reuse results when inputs are unchanged. Skip full repo scans, subagents and independent review passes for routine tasks.
- For a small review, stop at the requested diff when it establishes the findings. Inspect callers, test setup or runtime behavior only if a material finding depends on evidence missing from that diff.
- **No repeated verification without new evidence.** Repeat a read, search or check only when relevant inputs changed, an error or conflicting evidence appeared, or a required risk check remains. If two investigation attempts yield no useful evidence, change approach or stop that investigation.
- Make routine technical decisions independently. Ask when essential information is missing or the action requires authorization. Reuse existing code and patterns, protect user changes, and keep edits and dependencies within scope.

### Git and validation

- Run `git status --short` at most once at the start if needed to identify existing edits, and once at the end if needed to report files. Inspect the scoped diff once when useful. Use `git diff --stat` only to summarize scope and `git diff --check` at most once at the end when applicable. Reuse existing evidence for the same Git state. Recheck affected state for new errors, conflicts or concrete risk. Commit, reset, clean, checkout or discard only when requested.
- Normally validate once after editing with the smallest relevant test or compiler check. Skip full builds for small changes. Expand checks when evidence or risk warrants it. On failure, distinguish code from environment causes, diagnose and rerun only the affected check after a relevant change. Reuse test output already returned. If a check is blocked, use a permitted alternative only when the evidence is necessary, or report the blocker.

### Stop and report

Stop when the request and acceptance criteria are met, required checks are complete and concrete in-scope issues are resolved. Skip speculative optimization, unrelated refactors and automatic chains of review, audit or verification. Report **Completed**, **Validation** and **Notes** when needed. List only checks actually run and state material limits or remaining risks.

## Scope

Solidity 0.8.30 contracts built and tested with Foundry (`foundry.toml`, EVM `cancun`), using OpenZeppelin from `lib/` (a dependency; never edit it). Target network is Ethereum Sepolia.

- `src/ContractDocumentRegistry.sol`: owner-only registry of document proofs (`documentId` → SHA-256 `documentHash` + `registeredAt`) with case lineage (`caseId`, `documentKind`: 1 deposit, 2 lease, 3 annex). `Ownable2Step`.
- `src/EthPayment.sol`: ETH membership payment. Pays a backend-signed EIP-712 quote (`pay`), one-time `paymentId`, `quoteSigner` set by owner. `Ownable2Step`, `ReentrancyGuard`.

Read `README.md` for the registry data model. `CONTRACT_DOCUMENT_REGISTRY.md` and `ETH_PAYMENT.md` are deployment and manual-test guides; read them only for deployment or ABI questions. Backend consumers rely on these ABIs and configured addresses.

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
- Use DEEP for access control, payment logic, ABI, ownership and deployment scripts. Documentation and comments normally use FAST.

## Skills

- `solidity-safety-review`: explicit, review-only safety review of contract changes.

## Completion

Report changed contracts, ABI impact, verification that actually ran and deployment implications.
