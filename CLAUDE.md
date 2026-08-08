# Sahih Contracts

Foundry repo for a Sharia-compliant fractional sukuk platform targeting Monad.

**Read `docs/sahih-repo-guide.md` before doing anything.** It carries the architecture, the
conventions to follow, the landmines, and the current list of open findings. The summary below is
only enough to orient you.

## The rule that explains the design

The contracts are a **dumb executor**. All business logic — revenue verification, profit-share
calculation, risk scoring — runs off-chain; a trusted Platform Operator writes results on-chain.
**Never add a calculation to a contract.** Numbers arrive as parameters.

## Commands

```bash
npm install                                    # REQUIRED first, or npx pulls the wrong solhint
forge build
forge test                                     # 104 tests, ~2s
forge fmt --check                              # CI gate
npx solhint 'src/**/*.sol' --max-warnings 0    # CI gate
forge coverage --no-match-coverage "^(test|script)/"   # anchor the regex, see guide §7
```

CI runs: `npm install` → `forge fmt --check` → `solhint` → `forge build --sizes` → `forge test`.
Verify all four before calling the suite green. `make` is NOT installed on this machine.

## Conventions

Custom errors not revert strings · full natspec on every function · new storage variables go at
the END and decrement the `__gap` · dependencies injected via `initialize()`, never hardcoded ·
`forge fmt` is authoritative.

## Landmines

- **Never add `setUp()` with `vm.createSelectFork` to a deploy script.** The network comes from
  `--rpc-url`. See guide §7 for the failure it causes.
- **`Upgrade.s.sol` cannot run** — three blockers, and the test suite does not catch it.
- **`purchaseTokens` mints without payment** (finding F1) — known, unfixed, Prod-critical.
- **`.env` holds real secrets** and is gitignored. Do not read or print it.
- Working tree is currently **uncommitted**; much of the current state exists only on disk.

## Docs

| File | For |
|---|---|
| `docs/sahih-repo-guide.md` | **Start here** — architecture, conventions, landmines, state |
| `docs/sahih-deployment-runbook.md` | Deployment order and commands |
| `docs/sahih-contract-review-checkpoint.md` | Audit findings (§5–§7 = current) |
| `docs/sahih-entity-contract-design.md` | API shape per function (Indonesian) |
| `docs/sahih-development-plan.md` | Lifecycle T0–T7, per-contract specs (Indonesian) |
