# Constants

# Configurations
.SUFFIXES:
.DELETE_ON_ERROR:
.ONESHELL:
export SHELL := /bin/bash
export SHELLOPTS := pipefail:errexit:nounset:noclobber

# Tasks
.PHONY: all test
all: test
test:
	cd test
	julia run.jl

# Files

# Rules
