#!/usr/bin/env bash
set -e

# Usage: ./run_jg.sh [all|safety|liveness|misc]
MODE=${1:-all}
export JG_MODE="$MODE"

cd FPV
echo "Running JasperGold mode: $MODE"
jg -fpv FPV_axiapb.tcl