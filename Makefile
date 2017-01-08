# Constants

# Configurations
.SUFFIXES:
.DELETE_ON_ERROR:
.ONESHELL:
export SHELL := /bin/bash
export SHELLOPTS := pipefail:errexit:nounset:noclobber

JULIA := julia

# Tasks
.PHONY: all test
all: test
test:
	JULIA_LOAD_PATH="$(CURDIR)/src:$${JULIA_LOAD_PATH:-}" time -p $(JULIA) bin/juke -j8

# Files

# Rules
