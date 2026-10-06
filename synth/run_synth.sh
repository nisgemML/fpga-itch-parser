#!/usr/bin/env bash
# synth/run_synth.sh — open-source synthesis + place-and-route for a resource
# and timing ESTIMATE on a Lattice ECP5 (LFE5U-25F, CABGA256).
#
#   1. yosys synth_ecp5 on itch50_parser alone      -> LUT/FF counts
#   2. yosys + nextpnr-ecp5 on synth/synth_top.v    -> post-route Fmax, 3 seeds
#      (synth_top registers every parser output and XOR-reduces them to one
#       pin, so nothing is optimized away and the 459 outputs fit a package)
#
# This shows the RTL synthesizes and what an open flow's timing model says.
# It does NOT show behaviour on a board. Needs: yosys, nextpnr-ecp5 (+ prjtrellis db).
set -euo pipefail
cd "$(dirname "$0")"
out=${1:-/tmp/itch50_synth}; mkdir -p "$out"

yosys -p "read_verilog ../rtl/itch50_parser.v; synth_ecp5 -top itch50_parser" > "$out/parser.log" 2>&1
echo "itch50_parser alone (yosys $(yosys -V | awk '{print $2}')):"
awk '/Printing statistics/,0' "$out/parser.log" | grep -E '^\s+(LUT4|TRELLIS_FF|CCU2C|PFUMX|L6MUX21)\s' | sed 's/^/  /'

yosys -p "read_verilog ../rtl/itch50_parser.v synth_top.v; synth_ecp5 -top synth_top -json $out/top.json" > "$out/top.log" 2>&1
echo "post-route Fmax, LFE5U-25F CABGA256 (nextpnr-ecp5 $(nextpnr-ecp5 --version 2>&1 | head -1 | awk '{print $NF}')):"
for seed in 1 2 3; do
  nextpnr-ecp5 --25k --package CABGA256 --json "$out/top.json" --lpf-allow-unconstrained \
               --freq 250 --seed "$seed" --timing-allow-fail > "$out/pnr_$seed.log" 2>&1
  f=$(grep -E 'Max frequency for clock' "$out/pnr_$seed.log" | tail -1 | grep -oE '[0-9.]+ MHz' | head -1)
  echo "  seed $seed: $f"
done
echo "critical path (seed 1):"
awk '/Critical path report for clock/,/ns logic/' "$out/pnr_1.log" | grep -E 'Source|Sink' | sed -n '1p;$p' \
  | sed -E 's/^Info: +([0-9.]+ +[0-9.]+ +)?//; s/(Source|Sink) ([^ ]{0,48}).*/  \1 \2/'
