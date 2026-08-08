# Sahih — Deployment Runbook

**Target:** Monad testnet (chain ID `10143`) / Monad mainnet (`143`)
**Last verified:** 2026-08-08, full flow executed end-to-end against a local anvil node
**Audience:** whoever runs the deploy. Read §1 before touching anything.

---

## 1. The one thing that makes Monad different

**EAS is not deployed on Monad.** Verified 2026-08-08 against three sources: the canonical
[`eas-contracts/deployments/`](https://github.com/ethereum-attestation-service/eas-contracts/tree/master/deployments)
directory (26 chains, no `monad`), the eas-contracts README (15 mainnets + 11 testnets, no
mention), and a search for community deployments. Monad mainnet launched 2025-11-24, recent
enough that EAS has not followed.

This costs almost nothing, because `Attester` depends on the `IEAS` **interface**, not on a
specific deployment, and takes the address through `initialize()`. So on Monad we deploy our
own registries and point at them.

| | Chain with canonical EAS (Base, OP, Arbitrum…) | Chain without EAS (Monad) |
|---|---|---|
| Registry | Official EAS + SchemaRegistry addresses | `SahihSchemaRegistry` + `SahihAttestationRegistry` |
| Schema registration | `RegisterSchema.s.sol` | `DeployAttestationStack.s.sol` (does both) |
| `src/` changes needed | none | none |

Switching later is `Attester.setEAS(<canonical EAS>)` plus re-registering schemas. No redeploy
of Factory, Distribution, or any issuer token.

### What our registries do and do not do

`SahihAttestationRegistry` implements the subset of `IEAS` the platform uses. It deliberately
omits revocation, delegated attestation, resolvers, and value-bearing attestations — every
attestation is permanent by construction, matching the design rule that history is only
appended to. It rejects `revocable: true` and any non-zero value outright rather than
half-supporting them.

`SahihSchemaRegistry` derives schema UIDs exactly as EAS does —
`keccak256(abi.encodePacked(schema, resolver, revocable))` — so a schema registered here carries
the same UID it would on a chain running real EAS. Confirmed empirically: two deploys on
different chains with different deployer addresses produced byte-identical UIDs.

**What this is not:** these are not canonical EAS. Do not tell judges or partners the project
"runs on EAS." The accurate statement is that it is built against the EAS interface and runs its
own registry because EAS has not shipped on Monad. `setEAS()` makes that a one-call migration.

---

## 2. Prerequisites

### Three distinct identities

Every `_grantRole` in the deploy path targets the `admin` / `operator` **parameters**, never
`msg.sender`. The deployer therefore ends up with **no role at all**.

| Identity | Where it lives | Powers |
|---|---|---|
| **Deployer** (`DEPLOYER_PRIVATE_KEY`) | Signs the deploy | None afterwards. Hot, disposable, needs gas only. |
| **Admin** (`ADMIN_ADDRESS`) | Parameter only — never signs during deploy | `_authorizeUpgrade` on all 3 UUPS contracts, role grant/revoke, transfer whitelist, payment token, schemas |
| **Operator** (`OPERATOR_ADDRESS`) | Backend secrets manager | `createIssuerToken`, `recordDistribution`, `attest*` |

**Do not reuse one address for admin and operator.** The operator key is hot by design — it
signs unattended every cycle. If it is also admin, a leak means the attacker can upgrade
`Distribution` to drain the pool, upgrade `IssuerToken` to mint freely, and revoke your admin
role so you cannot undo it. The rotation path exists precisely to survive that, and sharing the
address removes it.

Admin signs nothing during deployment, so a Safe multisig address works from day one at zero
friction.

### Payment token

`Distribution` assumes `safeTransfer` delivers exactly the recorded amount. A fee-on-transfer or
rebasing token would leave holders short of the `totalAmount` recorded on-chain and attested,
silently contradicting the audit trail. Use a plain, non-rebasing ERC-20.

For a testnet demo, `DeployDemoPaymentToken.s.sol` deploys `DemoPaymentToken`: **anyone can mint
any amount to any address**, and `decimals() == 0` so one unit is one Rupiah and backend figures
go on-chain verbatim. Testnet only — never point `PAYMENT_TOKEN_ADDRESS` at it on a network
carrying real money.

---

## 3. Deployment order

```
  STEP 0  DeployDemoPaymentToken.s.sol   ──▶  PAYMENT_TOKEN_ADDRESS
             (testnet only; skip on a chain with a real stablecoin)
                       │
  STEP 1  DeployAttestationStack.s.sol   ──▶  EAS_SCHEMA_REGISTRY_ADDRESS
             (Monad; skip on chains with EAS)   EAS_ADDRESS
                       │                        VERIFICATION/SCORE/DISTRIBUTION_SCHEMA_UID
                       │
  STEP 2  Deploy.s.sol                   ──▶  tokenImplementation, factory,
                       │                        distributionProxy, attesterProxy
                       │
  STEP 3  Fund Distribution (no script)
```

`RegisterSchema.s.sol` is **not** part of the Monad path. It is the alternative to Step 1 for
chains that already run canonical EAS. Running both would double-register.

Each script prints its outputs with the exact `.env` variable names. Paste them in before the
next step — Step 2 reverts immediately if Step 1's values are missing, which is the intended
behaviour.

### Commands

The scripts take the signer from `DEPLOYER_PRIVATE_KEY` (or `PRIVATE_KEY`) in `.env`, falling
back to `--private-key` / `--account` / `--ledger` on the command line. Either style works.

```bash
# Step 0 — testnet demo token
forge script script/DeployDemoPaymentToken.s.sol:DeployDemoPaymentToken \
  --rpc-url monad_testnet --broadcast

# Step 1 — attestation stack + all three schemas, one run
forge script script/DeployAttestationStack.s.sol:DeployAttestationStack \
  --rpc-url monad_testnet --broadcast

# Step 2 — Factory, Distribution, Attester
forge script script/Deploy.s.sol:Deploy \
  --rpc-url monad_testnet --broadcast

# Step 3 — fund Distribution (free mint, so mint straight to it)
cast send $PAYMENT_TOKEN_ADDRESS "mint(address,uint256)" $DISTRIBUTION_PROXY 1000000 \
  --rpc-url monad_testnet --private-key $DEPLOYER_PRIVATE_KEY
```

Skip Step 3 and `recordDistribution` reverts `InsufficientBalance`.

`make` targets exist for each step (`make deploy-demo-token`, `deploy-attestation-stack`,
`deploy`) but **`make` is not installed on the current dev machine** — use the raw commands
unless you install it.

### After deployment — runtime, not deployment

All operator-signed, no scripts: `createIssuerToken` per issuer → `purchaseTokens` →
`recordDistribution` → `attestVerification` / `attestScore` / `attestDistribution`.

---

## 4. Verified end-to-end

Executed against a local anvil node on 2026-08-08, all four steps plus the full lifecycle:

```
fund Distribution        Rp1,000,000
createIssuerToken        UMKM-001 → SHUMKM1
purchaseTokens           investorA 300 units, investorB 700 units
recordDistribution       Rp425,000 → 127,500 / 297,500
  investorA paid         Rp127,500
  investorB paid         Rp297,500
  Distribution left      Rp575,000    (1,000,000 − 425,000 ✓)
attestVerification       UMKM-001 / 2026-W31, read back decoded:
  ("UMKM-001", "2026-W31", 8500000, 12, 0x…abc, 1754179200)
  attester: the Attester proxy ✓
```

Schema self-description survives the round trip — `getSchema(uid)` returns the full definition
string, which a hardcoded UID would have lost.

---

## 5. Gotchas that will cost you an hour each

**`make` is not installed** on the current dev machine. All Makefile targets, including
pre-existing ones, will fail with `command not found`.

**`npx solhint` without `node_modules`** silently pulls solhint 6.x while `package.json` pins
`^5.0.3`. Under 6.x you get four phantom warnings, including one on untouched `IIssuerToken.sol`
code. Run `npm install` first. CI does this already and is unaffected.

**Windows + OZ upgrades plugin:** bare `bash` resolves to WSL 1 and the run dies with
`WSL 1 is not supported`. Set `OPENZEPPELIN_BASH_PATH="C:/Program Files/Git/bin/bash"`.

**`build_info = true` plus incremental builds** breaks the OZ validator with
`Found multiple contracts with name …`. Always `forge clean && forge build` before any upgrade
validation.

**Do not add `setUp()` with `vm.createSelectFork` to a deploy script.** The network comes from
`--rpc-url`. Forking inside a broadcasting script swaps out the EVM the script contract itself
lives in, and forge starts recording transactions against addresses holding no code — surfacing
as `Script contains a transaction to 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496 which does not
contain any code`. That address is Foundry's own ephemeral script-contract address, not anything
you deployed. Answer **no** to that prompt. `BaseScript` carries a warning comment about this.

**Coverage command:** `forge coverage --no-match-coverage "(test|script)"` silently drops
`src/Attester.sol`, because "At**test**er" contains "test". Anchor it:
`--no-match-coverage "^(test|script)/"`.

---

## 6. Current state

**Tests: 104 passing, 0 failing, 11 suites.** Unit (Attester, Distribution, Factory,
IssuerToken, SahihSchemaRegistry, SahihAttestationRegistry, DemoPaymentToken), integration
(FactoryToToken, FullIssuerLifecycle, UpgradeFlow), invariant (Distribution).

Coverage, excluding the invariant suite:

| File | Lines | Branches |
|---|---|---|
| `src/SahihAttestationRegistry.sol` | 100.00% | 100.00% |
| `src/SahihSchemaRegistry.sol` | 100.00% | 100.00% |
| `src/DemoPaymentToken.sol` | 92.86% | 100.00% |
| `src/Distribution.sol` | 93.24% | 75.00% |
| `src/Attester.sol` | 90.00% | 57.14% |
| `src/Factory.sol` | 90.54% | 46.15% |
| `src/IssuerToken.sol` | 86.21% | **33.33%** |
| `src/libraries/PeriodLib.sol` | 80.00% | 50.00% |
| **Total** | **90.78%** | **59.65%** |

All contracts are far inside the EIP-170 limit; largest is `Distribution` at 10,093 B (41%).
`SahihAttestationRegistry` is 3,223 B and `SahihSchemaRegistry` 1,972 B.

**`Upgrade.s.sol` cannot run.** It is not needed for initial deployment, but do not assume the
upgrade path works — see `sahih-contract-review-checkpoint.md` §6 for the three blockers.
