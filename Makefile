.PHONY: install build fmt fmt-check lint lint-ci test test-unit test-integration test-invariant clean

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
