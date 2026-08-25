.DEFAULT_GOAL := help

.PHONY: help lint test verify

help:
	@echo "AWG OpenWrt3 developer targets:"
	@echo "  make lint    Run repository static checks"
	@echo "  make test    Run fixture-based tests"
	@echo "  make verify  Run lint and tests"

lint:
	@./scripts/lint.sh

test:
	@./tests/run.sh

verify: lint test
