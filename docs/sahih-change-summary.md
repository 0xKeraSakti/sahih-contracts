# Sahih Contracts — Change Summary

**Baseline:** `09ea24b` — *fix(ci): update branch name from main to master in workflow configuration*
**As of:** 2026-08-08
**Status:** all changes below are **uncommitted** — they exist only in the working tree.

Measured with `git diff --numstat` and `git status`, not estimated. Line counts are actual file
lengths.

---

## 1. New files (14)

### Production contracts — `src/`

| File | Lines | What it is |
|---|---|---|
| `SahihSchemaRegistry.sol` | 74 | EAS-compatible schema registry. UID derivation matches EAS exactly: `keccak256(abi.encodePacked(schema, resolver, revocable))` |
| `SahihAttestationRegistry.sol` | 129 | EAS-compatible attestation registry. Deliberately omits revocation, delegated attestation, resolvers, and value-bearing attestations |
| `DemoPaymentToken.sol` | 81 | Free-mint IDR stand-in, `decimals() == 0` so one unit is one Rupiah. **Testnet only** |
| `libraries/SahihSchemas.sol` | 20 | The three schema definition strings — single source of truth for scripts and tests |

Why the registries exist: **EAS is not deployed on Monad** (verified 2026-08-08 against the
canonical `eas-contracts` deployments directory, its README, and a community search). `Attester`
depends on the `IEAS` interface and takes the address via `initialize()`, so we deploy our own and
point at them. Migration to canonical EAS later is `Attester.setEAS(...)` — no redeploy.

### Scripts — `script/`

| File | Lines | What it is |
|---|---|---|
| `BaseScript.sol` | 45 | Shared broadcast helper. Prefers `DEPLOYER_PRIVATE_KEY`, then `PRIVATE_KEY`, then the CLI signer |
| `DeployAttestationStack.s.sol` | 58 | Step 1: both registries plus all three schemas in one run |
| `DeployDemoPaymentToken.s.sol` | 45 | Step 0: demo token plus initial mint to the deployer |

### Tests — `test/unit/`

| File | Lines | Tests |
|---|---|---|
| `SahihAttestationRegistry.t.sol` | 167 | 11 |
| `DemoPaymentToken.t.sol` | 115 | 11 |
| `SahihSchemaRegistry.t.sol` | 108 | 9 |

### Documentation

| File | Lines | What it is |
|---|---|---|
| `docs/sahih-contract-review-checkpoint.md` | 304 | Audit findings. §1–§4 = commit `09ea24b`; §5–§7 = status update, corrections, new findings |
| `docs/sahih-repo-guide.md` | 236 | Repo orientation: architecture, conventions, landmines, current state |
| `docs/sahih-deployment-runbook.md` | 218 | Deployment order, commands, operational gotchas |
| `CLAUDE.md` (repo root) | 52 | Short router for coding agents; points at the guide |

---

## 2. Deleted (2)

| File | Lines | Why |
|---|---|---|
| `test/mocks/MockEAS.sol` | −48 | Replaced by `SahihAttestationRegistry`. Tests now exercise the contract that actually gets deployed |
| `test/mocks/MockToken.sol` | −37 | Replaced by `DemoPaymentToken`, same reasoning |

---

## 3. Modified — real content changes (16)

### Source

| File | +/− | Change |
|---|---|---|
| `src/Attester.sol` | +10 −1 | **Security fix.** `_requireSchema` now rejects attestations this contract did not write. Adds `UnauthorizedAttester(address)` |
| `src/interfaces/ISchemaRegistry.sol` | +24 −1 | Adds the `SchemaRecord` struct, `getSchema`, and the `Registered` event |

### Scripts

| File | +/− | Change |
|---|---|---|
| `script/Deploy.s.sol` | +10 −3 | Inherits `BaseScript`; broadcasts via `_startBroadcast()` |
| `script/RegisterSchema.s.sol` | +13 −13 | Uses `SahihSchemas` instead of duplicating the schema strings; inherits `BaseScript` |
| `script/Upgrade.s.sol` | +3 −3 | Inherits `BaseScript` |

### Config

| File | +/− | Change |
|---|---|---|
| `.env.example` | +76 −3 | Restructured: three-identity separation, Monad variables, attestation-layer guidance, upgrade prerequisites |
| `Makefile` | +38 −1 | `-include .env` + `export` so targets see the signer; four deploy targets added |
| `foundry.toml` | +2 −0 | `monad` and `monad_testnet` RPC endpoints |

### Tests

| File | +/− | Change |
|---|---|---|
| `test/unit/Attester.t.sol` | +52 −3 | Two new tests: third-party attestation rejected by the typed getter; raw getter still returns it unfiltered |
| `test/helpers/DeployHelpers.sol` | +36 −14 | Adds `deployAttestationStack()`; wires fixtures to the real registries instead of mocks |
| `test/integration/FullIssuerLifecycle.t.sol` | +5 −5 | Type swap; `eas.nonce()` → `eas.attestationCount()` |
| `test/invariant/DistributionInvariant.t.sol` | +4 −4 | `MockToken` → `DemoPaymentToken` |
| `test/unit/Distribution.t.sol` | +3 −3 | `MockToken` → `DemoPaymentToken` |
| `test/integration/UpgradeFlow.t.sol` | +2 −2 | `MockToken` → `DemoPaymentToken` |

---

## 4. Modified with zero content change (14)

These show `M` in `git status` but have **0 diff lines**. `forge fmt` rewrote them with LF where
the repo stores CRLF, so they contribute nothing to a commit:

`foundry.lock` · `src/Distribution.sol` · `src/Factory.sol` · `src/IssuerToken.sol` ·
`src/interfaces/IAttester.sol` · `src/interfaces/IDistribution.sol` · `src/interfaces/IEAS.sol` ·
`src/interfaces/IIssuerToken.sol` · `src/libraries/PeriodLib.sol` · `test/helpers/TestConstants.sol` ·
`test/integration/FactoryToToken.t.sol` · `test/mocks/IssuerTokenV2.sol` · `test/unit/Factory.t.sol` ·
`test/unit/IssuerToken.t.sol`

---

## 5. Net effect

| Metric | Before (`09ea24b`) | Now |
|---|---|---|
| Tests passing | 71 | **104** |
| Test suites | 8 | **11** |
| `src/` contracts | 5 | **9** |
| Deploy scripts | 3 | **6** |
| Line coverage | 89.47% | **90.78%** |
| Branch coverage | 51.06% | **59.65%** |
| Docs | 3 | **6** + `CLAUDE.md` |

**Exactly one behavioural change to a pre-existing contract:** the `Attester` attester guard.
Everything else is additive, test-side, configuration, or documentation. `Factory.sol`,
`Distribution.sol`, `IssuerToken.sol`, and `PeriodLib.sol` are byte-for-byte unchanged.

New contract sizes, all far inside the EIP-170 limit: `SahihAttestationRegistry` 3,223 B,
`SahihSchemaRegistry` 1,972 B, `DemoPaymentToken` unchanged in profile from a standard ERC-20.

---

## 6. What was verified, and how

Not read — executed.

- **Full CI pipeline from clean:** `forge fmt --check`, `solhint --max-warnings 0`,
  `forge build --sizes`, `forge test`. All pass.
- **Four-step deployment end-to-end against a local anvil node**, including a real payout:
  funded Rp1,000,000 → `recordDistribution` Rp425,000 → investorA Rp127,500, investorB Rp297,500,
  Rp575,000 remaining. Exact Rupiah arithmetic, no scaling.
- **Attestation round trip:** written by the operator through `Attester`, read back decoded with
  the correct payload and attester.
- **The security fix, live:** an outsider wrote a forged `avgRevenue: 999999999` record against
  the platform's own schema UID; the typed getter reverted `UnauthorizedAttester(0x976EA7…0aa9)`
  while the raw getter still returned it.
- **Schema UID stability:** two deploys on different chains with different deployer addresses
  produced byte-identical schema UIDs.

---

## 7. Deliberately not fixed

| | Finding | Severity |
|---|---|---|
| **F1** | `purchaseTokens` mints without taking payment | Demo: Low · **Prod: Critical** |
| **F2** | 100-holder cap plus duplicate-period guard makes >100-holder issuers unpayable | Prod: High |
| **F3** | Distribution is one shared pool, no per-issuer accounting, no rescue path | Prod: High |
| **F4** | Unpadded week strings break range queries | Prod: Medium |
| **F6** | `Upgrade.s.sol` unrunnable — three blockers | Prod: High |
| **N4** | `IssuerToken.decimals()` is 18 but whole units are minted | Demo: Medium |

The `@custom:oz-upgrades-unsafe-allow constructor` annotations were added temporarily to prove
the F6 fix works, then reverted. **They are not in the tree.**

Full detail in `sahih-contract-review-checkpoint.md` §3, §6, §7.

---

## 8. Known state of the working tree

`DeployAttestationStack.s.sol` and `DeployDemoPaymentToken.s.sol` currently carry `setUp()` with
`vm.createSelectFork`, which is documented as a landmine in `sahih-repo-guide.md` §7 — the network
belongs in `--rpc-url`, and forking inside a broadcasting script makes forge record transactions
against addresses holding no code.

`node_modules/` now exists from `npm install`. It is gitignored and will not appear in a commit,
but it matters: without it, `npx solhint` pulls 6.x against a `^5.0.3` pin and reports phantom
warnings.
