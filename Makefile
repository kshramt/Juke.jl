# Constants

# Configurations
.SUFFIXES:
.DELETE_ON_ERROR:
.ONESHELL:
export SHELL := /bin/bash
export SHELLOPTS := pipefail:errexit:nounset:noclobber

JULIA := julia

# Tasks
.PHONY: all check example
all:

check:
	JULIA_LOAD_PATH="$(CURDIR)/src:$${JULIA_LOAD_PATH:-}" time -p $(JULIA) bin/juke :test -j8 --keep-going

example:
	JULIA_LOAD_PATH="$(CURDIR)/src:$${JULIA_LOAD_PATH:-}" time -p $(JULIA) bin/juke :example -j8 --keep-going
