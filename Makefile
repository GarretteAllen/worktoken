-include .env
export

.PHONY: build test test-gas deploy-amoy deploy-polygon clean

build:
	forge build

test:
	forge test

test-gas:
	forge test --gas-report

deploy-amoy:
	forge script script/DeployVaultX.s.sol --rpc-url amoy --private-key $(PRIVATE_KEY) --broadcast --verify

deploy-polygon:
	forge script script/DeployVaultX.s.sol --rpc-url polygon --private-key $(PRIVATE_KEY) --broadcast --verify

clean:
	forge clean
