# Sahih Contracts — Repository Guide

**Purpose:** everything an engineer or coding agent needs to work in this repo without
re-deriving context. Written 2026-08-08 against the current working tree (uncommitted).

Read this first, then the doc you need from §2.

---

## 1. What this project is

**Sahih** is a Base-originated, now Monad-targeted platform for Sharia-compliant fractional
sukuk investment in Indonesian UMKM (small businesses), minimum ticket Rp100,000. Investors buy
non-transferable tokens representing a profit-sharing claim on an issuer's revenue; profit is
distributed periodically in an ERC-20 stablecoin.

### The one architectural rule that explains everything

**The contracts are a dumb executor.** All business logic — revenue verification, profit-share
calculation, risk scoring, per-holder breakdown — runs off-chain in a backend "Agent". A single
trusted **Platform Operator** address writes the results on-chain. Solidity performs no business
arithmetic.

Consequences you must respect:

- Never add a calculation to a contract. If a number needs computing, it arrives as a parameter.
- `recordDistribution` receives a pre-computed `HolderAmount[]`; the contract only checks the sum
  matches `totalAmount` and pays it out.
- Holder enumeration is never on-chain. The backend indexes `Purchase` events.
- Attestations are append-only. Each period is a new record; nothing is ever mutated.

### Trust model

Everything bottoms out at two keys, not at any cryptographic property:

- `OPERATOR_ROLE` — hot, backend-held, signs unattended. Creates issuers, records distributions,
  writes attestations.
- `ADMIN_ROLE` — cold. Upgrade authority on all three UUPS contracts, plus role rotation,
  transfer whitelist, payment token, and schemas.

`ADMIN_ROLE` is self-administering on every contract (`_setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE)`),
which is what makes operator key rotation possible without redeploy — and also what makes admin
key loss unrecoverable. These must be **different addresses**.

---

## 2. Document map

| Doc | Read it for |
|---|---|
| **this file** | Orientation, conventions, landmines, current state |
| `sahih-entity-contract-design.md` | Entities and the payload/response shape of every public function. **Source of truth for API shape.** |
| `sahih-development-plan.md` | When each function is called in the T0–T7 lifecycle, per-contract specs, security checklist, testing priorities |
| `sahih-deployment-runbook.md` | Deployment order, commands, env vars, operational gotchas |
| `sahih-contract-review-checkpoint.md` | Audit findings. §1–§4 = commit `09ea24b`; §5–§7 = current status, corrections, and new findings |
| `sahih-foundry-linter-formatter.md` | Formatter/linter setup rationale |

The two original design docs are in **Indonesian**. They are authoritative on intent — when code
and doc disagree, raise it rather than silently picking one.

---

## 3. Contracts

| Contract | Kind | Responsibility |
|---|---|---|
| `src/Factory.sol` | Plain `AccessControl`, **not upgradeable** | Deploys one `ERC1967Proxy` per issuer; holds the `issuerId → address` registry |
| `src/IssuerToken.sol` | UUPS impl behind proxy | ERC-20 sukuk units, minted on purchase, recipient-whitelisted transfers |
| `src/Distribution.sol` | UUPS proxy | Records a period's profit share and pays holders in ERC-20 |
| `src/Attester.sol` | UUPS proxy | Writes/reads verification, score, and distribution records via the `IEAS` interface |
| `src/SahihSchemaRegistry.sol` | Plain | EAS-compatible schema registry, for chains without EAS |
| `src/SahihAttestationRegistry.sol` | Plain | EAS-compatible attestation registry, for chains without EAS |
| `src/DemoPaymentToken.sol` | Plain ERC-20 | **Testnet only.** Free-mint IDR stand-in, `decimals() == 0` |
| `src/libraries/PeriodLib.sol` | Library | Lexicographic period-string comparison |
| `src/libraries/SahihSchemas.sol` | Library | The three schema definition strings — single source of truth |

Every contract has an explicit interface in `src/interfaces/`. Tests and other contracts talk to
interfaces, not implementations — this is deliberate and lets mocks substitute cleanly.

### Why the two Sahih* registries exist

**EAS is not deployed on Monad** (verified 2026-08-08 against the canonical `eas-contracts`
deployments directory, its README, and a community search). `Attester` depends on the `IEAS`
*interface* and receives the address via `initialize()`, so we deploy our own registries and point
at them. `SahihSchemaRegistry` derives UIDs exactly as EAS does, so schema UIDs are identical to
what canonical EAS would produce. Migration to real EAS is `Attester.setEAS(...)` — no redeploy.

**Do not describe this as "running on EAS."** It is built against the EAS interface with a
self-hosted registry.

---

## 4. Layout

```
src/                      production contracts (solhint lints ONLY this tree)
  interfaces/             one interface per contract + IEAS/ISchemaRegistry
  libraries/              PeriodLib, SahihSchemas
script/
  BaseScript.sol          shared broadcast helper — all scripts inherit this
  DeployDemoPaymentToken.s.sol   step 0 (testnet)
  DeployAttestationStack.s.sol   step 1 (chains without EAS)
  RegisterSchema.s.sol           step 1 alternative (chains WITH EAS)
  Deploy.s.sol                   step 2
  Upgrade.s.sol                  ⚠ currently unrunnable, see §7
test/
  unit/                   one contract in isolation
  integration/            multiple contracts through a real flow
  invariant/              Distribution accounting under randomized calls
  helpers/                DeployHelpers (fixtures), TestConstants
  mocks/                  IssuerTokenV2 only — used to exercise the upgrade path
docs/
```

---

## 5. Conventions — follow these

- **Custom errors, never revert strings.** `error TransferRestricted(); revert TransferRestricted();`
  Enforced by solhint `gas-custom-errors`. Tests assert with `vm.expectRevert(X.selector)`.
- **Full natspec on everything public and private** — `@notice`, `@param`, `@return`. The existing
  code is uniformly documented; match it.
- **Storage layout rules for upgradeable contracts.** New variables go at the END, never inserted.
  Never change a type or delete a variable. Every upgradeable base carries `uint256[50] __gap` —
  if you add a variable to a base contract, decrement the gap.
- **`initialize()` replaces the constructor**, with the `initializer` modifier. Implementation
  constructors call `_disableInitializers()`.
- **Dependencies are injected via `initialize()`**, never hardcoded. This is what makes the EAS
  swap a config change.
- **Events for every meaningful state change.**
- **`forge fmt` is authoritative** — 120 cols, 4-space, double quotes, `params_first` multiline
  headers. CI gates on `forge fmt --check`.
- **Indexed string event params are hashed.** Filterable, not recoverable. Every such value has a
  readable on-chain counterpart via a view call — see checkpoint §5.

---

## 6. Commands

```bash
npm install                                    # REQUIRED first — see §7
forge build                                    # compile
forge test                                     # 104 tests, ~2s
forge test --match-path 'test/unit/*'          # unit only
forge fmt                                      # format
forge fmt --check                              # CI gate
npx solhint 'src/**/*.sol' --max-warnings 0    # CI gate
forge coverage --no-match-coverage "^(test|script)/"
```

CI (`.github/workflows/ci.yml`) runs, in order: `npm install`, `forge fmt --check`,
`solhint --max-warnings 0`, `forge build --sizes`, `forge test`.

`make` targets exist but **`make` is not installed on the current dev machine** — use raw commands.

---

## 7. Landmines — read before debugging

**Run `npm install` first.** Without `node_modules`, `npx solhint` pulls 6.x against a `^5.0.3`
pin and reports four phantom warnings, one on untouched code. CI installs first and is unaffected.

**Coverage regex must be anchored.** `--no-match-coverage "(test|script)"` silently drops
`src/Attester.sol` — "At**test**er" contains "test". Use `"^(test|script)/"`.

**Never add `setUp()` with `vm.createSelectFork` to a deploy script.** The network comes from
`--rpc-url`. Forking inside a broadcasting script swaps out the EVM the script contract lives in,
and forge records transactions against addresses holding no code, surfacing as *"Script contains a
transaction to `0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496` which does not contain any code"* —
that address is Foundry's own ephemeral script-contract address. `BaseScript` carries a warning.

**`Upgrade.s.sol` cannot run.** Three blockers, each verified by execution — missing
`@custom:oz-upgrades-unsafe-allow constructor` on all three implementations, inverted
reference-contract logic, and `@openzeppelin/upgrades-core` undeclared in `package.json`. Full
detail in checkpoint §6. **The test suite does not catch this** because `UpgradeFlow.t.sol` calls
`upgradeToAndCall` directly and never invokes the OZ validator.

**Windows + OZ upgrades plugin** needs `OPENZEPPELIN_BASH_PATH="C:/Program Files/Git/bin/bash"`,
otherwise bare `bash` resolves to WSL 1 and dies. And `build_info = true` plus incremental builds
breaks the validator with `Found multiple contracts` until `forge clean`.

**`ffi = true`** is on globally (required by the OZ upgrades library) — any test or script can
execute shell commands.

---

## 8. Current state

**104 tests passing, 0 failing, 11 suites.**

| Suite | Tests | | Suite | Tests |
|---|---|---|---|---|
| `unit/IssuerToken` | 16 | | `unit/SahihAttestationRegistry` | 11 |
| `unit/Distribution` | 15 | | `unit/SahihSchemaRegistry` | 9 |
| `unit/Factory` | 14 | | `integration/UpgradeFlow` | 6 |
| `unit/Attester` | 12 | | `integration/FactoryToToken` | 4 |
| `unit/DemoPaymentToken` | 11 | | `invariant/Distribution` | 4 |
| | | | `integration/FullIssuerLifecycle` | 2 |

Coverage: **90.78% lines / 59.65% branches**. Both Sahih* registries are at 100% on all metrics.
`IssuerToken` is weakest at **33% branches** — and is also the contract holding the largest open
finding.

### Open findings, by priority

| | Finding | Severity |
|---|---|---|
| **F1** | `purchaseTokens` mints without taking payment — anyone can mint the entire supply free | Demo: Low · **Prod: Critical** |
| **F2** | 100-holder cap plus duplicate-period guard makes >100-holder issuers unpayable | Prod: High |
| **F3** | Distribution is one shared pool, no per-issuer accounting, no rescue path | Prod: High |
| **N2** | Admin lockout — self-administering role, no timelock or multisig | Prod: High |
| **N3** | Fee-on-transfer/rebasing payment token would break attested totals | Prod: High |
| **F6** | `Upgrade.s.sol` unrunnable | Prod: High |
| **F4** | Unpadded week strings break range queries (`"2026-W9"` sorts after `"2026-W10"`) | Prod: Medium |
| **N4** | `IssuerToken.decimals()` is 18 but whole units are minted — UIs show `3e-16` | Demo: Medium |
| **F7** | Branch coverage well below line coverage | Prod: Medium |

Fixed this session: **N1**, attestation spoofing via the read path — `Attester._requireSchema` now
rejects attestations it did not write itself.

Full detail and the remaining smaller items: `sahih-contract-review-checkpoint.md` §3, §6, §7.

---

## 9. If you are an agent picking this up

- The design docs are authoritative on **intent**; the code is authoritative on **behaviour**.
  Where they disagree, say so rather than choosing silently.
- Verify before asserting. Several findings here were confirmed by executing throwaway tests
  against a local anvil node, not by reading. Claims about coverage, test counts, or on-chain
  behaviour should be measured.
- `.env` is gitignored and holds real secrets. Do not read or print it. Check variable *names*
  with `grep -c '^NAME=' .env` if you need to confirm one is set.
- The working tree is currently **uncommitted** — a substantial amount of work described in §8
  exists only on disk.
- Before claiming the suite is green, run all four CI steps, not just `forge test`.
