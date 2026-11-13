---
name: solidity-safety-review
description: Review HomeSpace Solidity changes for ownership and access control, ETH payment integrity, replay and idempotency, external-call safety, document registry invariants, ABI compatibility and deployment risks. Use when an explicit smart contract safety review is requested.
---

# solidity-safety-review (Claude Code adapter for hs-smart-contract-blockchain)

This is an adapter. It does not contain the workflow itself. The source workflow is the Codex skill at:

```text
../../../.agents/skills/solidity-safety-review/SKILL.md
```

(relative to this directory; it resolves to `.agents/skills/solidity-safety-review/SKILL.md` in the `hs-smart-contract-blockchain` repository root).

Claude Code does not import that file automatically. When this skill is triggered:

1. Read the source file above with the Read tool.
2. Follow its workflow exactly, together with the `AGENTS.md` rules of this repository. It is review-only unless the user asks for fixes.
3. The source skill has no `references/` or `scripts/` directories. If they are added later, read them from the source skill directory when the workflow requires them.
