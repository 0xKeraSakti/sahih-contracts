.PHONY: install build fmt fmt-check lint lint-ci test test-unit test-integration test-invariant clean \
	deploy-demo-token deploy-attestation-stack register-schema deploy upgrade

# forge auto-loads .env, but make does not — without this, $(DEPLOYER_PRIVATE_KEY)
# below expands to nothing and every deploy target silently loses its signer.
-include .env
export

# Network alias from foundry.toml [rpc_endpoints]: base, base_sepolia, monad, monad_testnet
NETWORK ?= monad_testnet
FORGE_SCRIPT = forge script --rpc-url $(NETWORK) --broadcast --private-key $(DEPLOYER_PRIVATE_KEY)

install:
	forge install foundry-rs/forge-std
	forge install OpenZeppelin/openzeppelin-contracts@v5.0.2
	forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.0.2
	forge install OpenZeppelin/openzeppelin-foundry-upgrades
	npm install

build:
	forge build

fmt:
	forge fmt

fmt-check:
	forge fmt --check

lint:
	solhint 'src/**/*.sol'

lint-ci:
	solhint 'src/**/*.sol' --max-warnings 0

test:
	forge test -vv

test-unit:
	forge test --match-path 'test/unit/*' -vv

test-integration:
	forge test --match-path 'test/integration/*' -vv

test-invariant:
	forge test --match-path 'test/invariant/*' -vv

clean:
	forge clean

# Step 0 (testnet demo only): deploy the free-mint stand-in for an IDR stablecoin.
# Skip on any network with real money — use a real stablecoin address instead.
deploy-demo-token:
	$(FORGE_SCRIPT) script/DeployDemoPaymentToken.s.sol:DeployDemoPaymentToken

# Step 1 (chains without EAS, e.g. Monad): deploy our own schema + attestation
# registries and register all three schemas. Copy the logged values into .env.
# On chains running canonical EAS, skip this and use `register-schema` instead.
deploy-attestation-stack:
	$(FORGE_SCRIPT) script/DeployAttestationStack.s.sol:DeployAttestationStack

# Step 1 (chains with EAS): register the three schemas against the official registry.
register-schema:
	$(FORGE_SCRIPT) script/RegisterSchema.s.sol:RegisterSchema

# Step 2: deploy Factory, Distribution, and Attester. Requires EAS_ADDRESS and the
# three *_SCHEMA_UID values from step 1 to be set in .env.
deploy:
	$(FORGE_SCRIPT) script/Deploy.s.sol:Deploy

# Upgrade an existing proxy. Rebuilds from clean because the OZ validator reads
# out/build-info and rejects stale copies.
upgrade:
	forge clean
	forge build
	$(FORGE_SCRIPT) script/Upgrade.s.sol:Upgrade
