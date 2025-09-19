#!/usr/bin/env bash
set -euo pipefail
# always start at repo root
cd "$(git rev-parse --show-toplevel)"

# add your code and tests to the MATLAB path, then run all tests under tests/
matlab -batch "addpath('src'); addpath('tests'); results = runtests('tests', IncludeSubfolders=true); disp(results);"