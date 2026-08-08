# Sahih Contracts — Review Checkpoint

**Date:** 2026-08-07 · **updated 2026-08-08** (see §5–§7)
**Commit:** `09ea24b` (branch `master`, 3 commits total) — §1–§4 describe this commit; §5 onward
covers uncommitted follow-up work
**Companion doc:** `sahih-deployment-runbook.md` — deployment order and operational gotchas
**Scope:** Full read of `src/`, `script/`, `test/`, `docs/`, CI and tooling config. All metrics below were measured on this commit, not estimated.
**Context:** Findings are severity-rated on two axes — **Demo** (hackathon / testnet showcase) and **Prod** (real funds on Base mainnet) — because they diverge sharply for this codebase.

---

## 1. Project state

Sahih is a Base L2 platform for fractional Sharia profit-sharing (sukuk) investment in Indonesian UMKM, minimum Rp100k. The contracts are deliberately a **dumb executor**: all business logic (revenue verification, profit split, risk scoring) runs off-chain in the backend "Agent", and a single trusted **Platform Operator** address writes results on-chain. Tokens represent sukuk units and are non-transferable by default.

### Contracts

| Contract | Kind | Purpose |
|---|---|---|
| `src/Factory.sol` | Plain `AccessControl`, **not** upgradeable | Deploys + registers one `ERC1967Proxy` per issuer |
| `src/IssuerToken.sol` | UUPS impl behind proxy | ERC20 with transfer whitelist, minted on purchase |
| `src/Distribution.sol` | UUPS proxy | Records + pays a period's profit share to holders |
| `src/Attester.sol` | UUPS proxy | Writes verification / score / distribution records to EAS |
| `src/libraries/PeriodLib.sol` | Library | Lexicographic period-string comparison |

Every contract uses the same `ADMIN_ROLE` (self-administering, gates upgrades) / `OPERATOR_ROLE` (gates sensitive writes) pair, so operator key rotation works without redeploy — as required by `sahih-entity-contract-design.md`.

### Toolchain

- Solidity `0.8.26`, forge `1.7.1`, optimizer on (200 runs)
- OpenZeppelin contracts + contracts-upgradeable `v5.0.2`, openzeppelin-foundry-upgrades
- `ffi = true` (required by the OZ upgrades library — note that any test or script can therefore execute shell commands)
- CI gates on: `forge fmt --check`, `solhint --max-warnings 0`, `forge build --sizes`, `forge test`

### Verified metrics

**Tests: 71 passing, 0 failing, 8 suites.** Unit (Attester, Distribution, Factory, IssuerToken), integration (FactoryToToken, FullIssuerLifecycle, UpgradeFlow), invariant (Distribution, 4 invariants × 64 runs × 32 depth, 0 reverts).

**Coverage** (excluding invariant suite):

| File | Lines | Statements | Branches | Funcs |
|---|---|---|---|---|
| `src/Attester.sol` | 89.74% | 92.00% | **50.00%** | 86.67% |
| `src/Distribution.sol` | 93.24% | 94.74% | 75.00% | 91.67% |
| `src/Factory.sol` | 90.54% | 91.25% | **46.15%** | 100.00% |
| `src/IssuerToken.sol` | 86.21% | 87.50% | **33.33%** | 100.00% |
| `src/libraries/PeriodLib.sol` | 80.00% | 75.00% | **50.00%** | 75.00% |
| **Total** | **89.47%** | **90.09%** | **51.06%** | **92.00%** |

> **Gotcha when re-running coverage:** `forge coverage --no-match-coverage "(test|script)"` silently drops `src/Attester.sol`, because "At**test**er" contains the substring "test". Anchor the pattern: `--no-match-coverage "^(test|script)/"`.

**Contract sizes** — all comfortably within the EIP-170 24,576 B limit; largest is `Distribution` at 41%:

| Contract | Runtime (B) | % of limit |
|---|---|---|
| Distribution | 10,093 | 41% |
| IssuerToken | 8,715 | 35% |
| Attester | 8,488 | 35% |
| Factory | 7,036 | 29% |

**Working tree:** clean except a modified `foundry.lock` (left untouched).

---

## 2. What's solid

These are done well and need no action:

- **Access control and upgrade authority.** `_authorizeUpgrade` is `ADMIN_ROLE`-only on all three upgradeable contracts, `_disableInitializers()` in every implementation constructor, and re-initialization is explicitly tested — including *after* an upgrade (`UpgradeFlow.t.sol`).
- **`recordDistribution` safety.** Follows checks-effects-interactions (`_storeDistribution` before `_payoutHolders`) *and* carries `nonReentrant` *and* uses `SafeERC20`. Sum-vs-`totalAmount` check, duplicate-period guard, balance check, zero-address holder check, and holder-count cap are all present and tested.
- **Design discipline.** Custom errors throughout, storage gaps present, dependencies injected via `initialize()` rather than hardcoded, explicit interfaces for every contract. The plan's "Testability by Design" section was genuinely followed rather than retrofitted.
- **Lifecycle fidelity.** `FullIssuerLifecycle.t.sol` faithfully reproduces T2→T7 from the development plan.
- **Storage layout.** `IssuerTokenV2` correctly adds state in the derived contract, after the base `__gap` — layout-safe.

---

## 3. Findings

### F1 — `purchaseTokens` mints without taking payment

**Demo: Low (functional) / Medium (presentation) · Prod: Critical**

`src/IssuerToken.sol:102-125` takes no payment of any kind; `paymentSource` is an unvalidated string. The guard `msg.sender != investorAddress && !hasRole(OPERATOR_ROLE, ...)` permits *any* address to mint to itself. Verified with a throwaway test: an attacker with zero balance calls `purchaseTokens(attacker, MAX_SUPPLY, "i-paid-i-promise")` and receives 100% of the issue, leaving `remainingSupply() == 0`.

This is spec-faithful — the design doc marks the function `public — investor calls directly` — but the spec assumed a payment leg that does not exist on-chain.

*Demo note:* no one will attack a testnet demo. The risk is a judge skimming the contract and spotting a free mint in a Sharia-compliant-investment pitch. Fixing it costs **no demo functionality**, because the realistic demo flow mints via the operator anyway (payment is QRIS, off-chain).

**Fix cost (measured, not estimated):** gate on `OPERATOR_ROLE` only, then update **16 investor-direct call sites** to prank as `operator` — 8 in `test/unit/IssuerToken.t.sol`, 3 in `FullIssuerLifecycle.t.sol`, 3 in `UpgradeFlow.t.sol`, 2 in `FactoryToToken.t.sol`. Two tests need restructuring (`test_PurchaseTokensByInvestor`, `test_RevertWhen_PurchaseByUnauthorizedThirdParty`), and the `UnauthorizedPurchaser` custom error becomes dead code. Roughly 30 minutes to a green suite.

### F2 — 100-holder cap makes issuers with >100 holders unpayable

**Demo: None · Prod: High**

The development plan explicitly requires support for *"pemanggilan bertahap per periode yang sama"* (staged calls for the same period). But `MAX_HOLDERS_PER_DISTRIBUTION = 100` combined with the `PeriodAlreadyRecorded` guard means a period accepts exactly one call of at most 100 holders. Batching is impossible.

Given a Rp100k minimum ticket, exceeding 100 holders is the expected case, not an edge case. Needs a batch index in the record key, or a cumulative per-period accumulator.

### F3 — Distribution is one shared pool with no per-issuer accounting

**Demo: None · Prod: High**

`_validateDistribution` checks only the contract's *global* token balance, so issuer A's deposit can pay issuer B's holders. Consequently the plan's headline invariant — *total out for one issuer never exceeds total in × ratio* — is not checkable on-chain, and `DistributionInvariant.t.sol` substitutes a single global funding constant instead.

Related: there is no `fund()` entry point and no rescue path. Tokens sent in error, or the residual balance after `setPaymentToken` switches tokens, are stranded permanently.

### F4 — Period range queries break on unpadded week numbers

**Demo: Low–Medium · Prod: Medium**

`PeriodLib.compare` is byte-lexicographic. Verified: `compare("2026-W9", "2026-W10") > 0`, so `isWithin("2026-W9", "2026-W8", "2026-W10")` returns **false** — W9 silently vanishes from its own range. Zero-padded `"2026-W09"` behaves correctly.

Nothing enforces padding, and the invariant handler itself generates unpadded strings (`"2026-W1"`…`"2026-W10"`).

**Zero-code mitigation:** agree a zero-padded `YYYY-Www` convention with the backend. Existing tests use W31/W32, so the default demo path is already safe — just don't let the backend emit single-digit weeks.

### F5 — Indexed string event parameters are hashed, not readable

**Demo: Medium (integration time) · Prod: Medium (indexer design)**

`IssuerTokenCreated(string indexed issuerId, …)`, `Distributed(…, string indexed period, …)` and all three `*Attested` events index string parameters, so logs carry `keccak256(value)` rather than the value. The backend indexer can **filter** by `issuerId` but cannot **recover** it from the log.

Not a bug — a constraint. It needs to reach whoever builds the indexer *before* they hit it, or it costs hours of confused debugging.

### F6 — Upgrade-safety validation is not wired into the paths that matter

**Demo: None · Prod: Medium**

The plan requires the OZ validator as a CI / pre-deploy gate. In practice:

- `script/Deploy.s.sol` constructs `ERC1967Proxy` raw, bypassing `Upgrades.deployUUPSProxy`
- `script/Upgrade.s.sol:22` calls `validateUpgrade` **only** when the optional `UPGRADE_REFERENCE_CONTRACT` env var is set
- CI never runs it at all

`Factory._deployIssuerToken` also builds proxies raw — unavoidable inside a factory, but it means factory-deployed tokens carry no upgrade-safety metadata.

### F7 — Branch coverage is roughly half of line coverage

**Demo: None · Prod: Medium**

Line coverage (89%) reads reassuringly, but branch coverage is **51%**. The weakest contract is `IssuerToken` at **33%** — which is also the contract containing F1. Revert paths and guard conditions are substantially less exercised than the headline number suggests.

### Smaller items

| Item | Note |
|---|---|
| Natspec / code role mismatch | `Factory.sol:42` says `OPERATOR_ROLE` can update issuer status; `setIssuerStatus` at `:162` is `ADMIN_ROLE` |
| `volatilityIndex` scaling undocumented | Doc says `0.12`, tests use `12`. Consumers cannot distinguish 12% from 0.12 |
| No Factory ↔ Distribution link | `recordDistribution` never validates `issuerContract` against the Factory registry |
| Duplicate holders accepted | Same address twice in one array passes (sum still matches); creates duplicate `_investorDistributions` entries |
| Test gap | `Attester` and `Distribution` lack the direct-implementation-initialization test that `IssuerToken` has |
| `invariant.fail_on_revert = false` | Currently harmless (0 reverts observed), but would mask an always-reverting handler |
| No `README.md` | Judges read these; the two design docs are strong material currently buried in `docs/` |

---

## 4. Recommended sequencing

**Before the hackathon demo**

1. Fix **F1** (~30 min, no loss of demo functionality) — the only finding with real presentation downside.
2. Adopt zero-padded week strings in demo data (**F4**) — convention only, no code change.
3. Brief the backend/indexer owner on **F5** — five-minute conversation, saves hours.
4. Add a `README.md` — highest ratio of judging impact to effort in this list.

Everything else is safely deferrable: F2, F3, F6 and F7 have **no demo impact** at hackathon scale (one or two issuers, a handful of investors, worthless testnet tokens, no upgrades).

**Before any real funds**

F2 and F3 are architectural and should be designed together — per-issuer fund segregation and multi-batch periods touch the same storage. F6 and F7 are process work (wire the validator into CI, raise branch coverage on revert paths). Then the smaller items, then an external audit.

---

## 5. Status update — 2026-08-08

A follow-up session verified every finding above and then made changes. **All findings in §3 were
independently confirmed**; coverage figures and the 71-test count were reproduced exactly. F1 and
F4 were confirmed by execution, not just by reading. Two findings need correction, and the work
below changed the codebase materially.

### Corrections to §3

**F6 is materially worse than rated.** It was described as a process gap ("validation not wired
into the paths that matter", Prod: Medium). In fact `Upgrade.s.sol` **cannot execute at all** —
see §6 below. The upgrade path has never been run. Re-rate: **Prod: High.**

**F5 is milder than rated.** Only `string`/`bytes` indexed parameters are hashed; indexed value
types stay readable in topics. And every hashed value has a readable on-chain counterpart —
`issuerId` via `Factory.getIssuerContract`, `period` via `Distribution.getRecordedPeriods`, both
via `Attester.getVerificationAttestation`. The indexer can recover everything; it just needs a
view call per event rather than reading logs alone.

**F1 remains unfixed.** `purchaseTokens` still mints without payment.

### What changed

| Area | Change |
|---|---|
| Attestation layer | Added `SahihSchemaRegistry` + `SahihAttestationRegistry` (`IEAS`-compatible), because **EAS is not deployed on Monad** — verified against three sources |
| Schema definitions | Added `SahihSchemas` library; the three schema strings are now a single source of truth shared by scripts and tests |
| Security | **Fixed:** `Attester._requireSchema` now rejects attestations it did not write itself (see §7) |
| Payment token | Added `DemoPaymentToken` — free-mint, `decimals() == 0` so one unit is one Rupiah. Testnet only |
| Test hygiene | Deleted `MockEAS` and `MockToken`; tests now exercise the production contracts that actually get deployed |
| Scripts | Added `BaseScript` (env-or-CLI signer), `DeployAttestationStack.s.sol`, `DeployDemoPaymentToken.s.sol`; Monad chain config |
| Tests | **71 → 104 passing.** Branch coverage **51.06% → 59.65%**, lines 89.47% → 90.78% |

Deployment order, commands, and operational gotchas: **`sahih-deployment-runbook.md`**.

---

## 6. `Upgrade.s.sol` cannot run — three blockers

Each verified by execution, not inspection.

**6a. All three implementations fail the OZ validator.** Each has
`constructor() { _disableInitializers(); }` — correct OZ practice — but none carries the
`@custom:oz-upgrades-unsafe-allow constructor` annotation that marks it intentional:

```
✘ src/IssuerToken.sol:IssuerToken   :52: Contract has a constructor
✘ src/Distribution.sol:Distribution :46: Contract has a constructor
✘ src/Attester.sol:Attester         :35: Contract has a constructor
```

Verified: adding that one comment line to each flips all three to `✔ SUCCESS`. The change was
made temporarily to confirm the fix, then reverted — **it is not in the codebase.**

**6b. The reference-contract logic is inverted.** `Upgrade.s.sol` treats
`UPGRADE_REFERENCE_CONTRACT` as optional (`vm.envOr` behind a guarded `if`), but
`Upgrades.upgradeProxy` validates unconditionally and always requires a reference — it passes
`--requireReference` internally. With the variable unset (the default the code implies), the run
fails with *"does not specify what contract it upgrades from."* The script cannot run in the
configuration it presents as normal.

**6c. `@openzeppelin/upgrades-core` is an undeclared dependency.** `package.json` lists only
solhint. `npx` fetches it from the network at run time at a floating version; CI's `npm install`
would not install it.

**Why the test suite doesn't catch this:** `UpgradeFlow.t.sol` calls `upgradeToAndCall` directly
and never invokes the OZ validator. 104 tests pass green while the upgrade script is unrunnable.
Related: `IssuerTokenV2` additionally fails validation with `Missing initializer` — a real V2
would need a `reinitializer`.

**Fix (~15 min):** add the three annotations; make `UPGRADE_REFERENCE_CONTRACT` required and drop
the now-redundant separate `validateUpgrade` call; add `@openzeppelin/upgrades-core` to
`package.json`.

---

## 7. New findings

**N1 — Attestation spoofing via the read path. FIXED.**
`Attester._requireSchema` validated only the schema UID, never the attester. EAS is permissionless:
anyone can write against any schema UID, including the platform's own. A third party could craft
an attestation and have `getVerificationAttestation` return it as genuine platform data — the
`OPERATOR_ROLE` gate governs only what the contract *writes*, not what it will read back and
endorse. Fixed by rejecting `attestation.attester != address(this)`. `getAttestation` still
returns raw unvouched records. Verified live: a forged `avgRevenue: 999999999` record reverted
`UnauthorizedAttester(0x976EA7…0aa9)`.

**N2 — Admin lockout has no safety net. Prod: High.**
`_setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE)` on all four contracts means a single lost or wrongly
revoked admin key permanently bricks upgrades on all three UUPS contracts, the transfer whitelist,
the payment token, and the schemas. No timelock, no two-step transfer, no multisig assumed. Admin
signs nothing during deployment, so a Safe address costs nothing to adopt now.

**N3 — Payment token choice is load-bearing and undecided. Prod: High.**
`_payoutHolders` assumes `safeTransfer` delivers exactly `amount`. A fee-on-transfer or rebasing
token leaves holders short of the `totalAmount` recorded and attested, silently contradicting the
audit trail. Constrain `PAYMENT_TOKEN_ADDRESS` to a plain non-rebasing ERC-20.

**N4 — `IssuerToken.decimals()` returns 18 but whole units are minted. Demo: Medium.**
Investors hold raw balances like `300`, so any wallet or explorer renders `0.0000000000000003
SHUMKM1`. No contract logic is affected and all tests pass, but it looks wrong in any UI. Fix is a
`decimals()` override returning 0. **Not applied** — it touches a UUPS contract.

**N5 — Factory is not upgradeable but holds the canonical registry. Prod: Medium.**
Not a plan violation (only Token and Distribution were required upgradeable), but redeploying
Factory loses the `issuerId → address` mapping, which would have to be replayed.

**N6 — Basis-points convention undocumented.** Same class as the `volatilityIndex` item in §3:
tests use `3000` meaning 30%, the design doc says only "number". Consumers cannot tell.

**N7 — Deploy scripts must not fork.** Adding `setUp()` with `vm.createSelectFork` to a
broadcasting script swaps out the EVM the script contract lives in, and forge begins recording
transactions against addresses holding no code — surfacing as *"Script contains a transaction to
0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496 which does not contain any code."* That address is
Foundry's own ephemeral script-contract address. The network belongs in `--rpc-url`. See the
runbook §5.

**N8 — Toolchain traps.** `make` is not installed on the current dev machine, so every Makefile
target fails. `npx solhint` without `node_modules` pulls 6.x against a `^5.0.3` pin and reports
phantom warnings. On Windows the OZ upgrades plugin needs `OPENZEPPELIN_BASH_PATH` or it invokes
WSL bash and dies. `build_info = true` plus incremental builds breaks the OZ validator until
`forge clean`.

---

## 8. Open questions for the team

- Is the investor-direct `purchaseTokens` path actually wanted, or was operator-mediated minting always the intent? This decides whether F1 is a two-line gate or a design change.
- What is the real expected holder count per issuer at launch? If it can exceed 100, F2 is blocking rather than deferrable.
- Will one `Distribution` instance serve all issuers, or one per issuer? This determines whether F3 needs per-issuer accounting or instance isolation.
- What is the agreed period-string format, and where is it documented as a contract between backend and chain?
