SHELL := /bin/bash
SCRIPTS := mkdistro $(wildcard scripts/*.sh) $(wildcard presets/*/preset.sh)

.PHONY: lint lint-shellcheck lint-bash

lint: lint-bash lint-shellcheck

lint-bash:
	bash -n $(SCRIPTS)

lint-shellcheck:
	shellcheck $(SCRIPTS)
