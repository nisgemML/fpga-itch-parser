#!/usr/bin/env bash
# scripts/mutate.sh — does the differential test actually catch RTL bugs?
#
# Applies one deliberate bug at a time to a copy of rtl/itch50_parser.v,
# rebuilds the Verilator test against it, and requires the oracle test to
# FAIL. A mutant that passes means the suite has a blind spot. Exit 1 if any
# mutant survives.
#
# Usage: scripts/mutate.sh            (from the repo root; needs verilator)
set -uo pipefail
cd "$(dirname "$0")/.."
RTL=rtl/itch50_parser.v
ORACLE=tests/data/itch50_oracle.txt
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# name | sed expression (applied to a copy of the RTL)
mutants=(
  "add-order ref at old simplified offset (bytes 7..14)|s/if ((|pos\[18:11\])) order_ref <= {order_ref\[55:0\], byte_in};/if ((|pos[14:7])) order_ref <= {order_ref[55:0], byte_in};/"
  "fields not cleared at message start|/exp_len  <= spec_len(byte_in);/,/attribution <= 32'd0;/{s/order_ref <= 64'd0;/order_ref <= order_ref;/;s/shares <= 32'd0;/shares <= shares;/;s/price <= 32'd0;/price <= price;/}"
  "len_ok off by one|s/(exp_len == total_len)/(exp_len == total_len + 8'd1)/"
  "replace price at offset 32 instead of 31|s/if ((|pos\[34:31\])) price/if ((|pos[35:32])) price/"
  "timestamp starts at byte 4|s/if ((|pos\[10:5\])) timestamp_ns/if ((|pos[9:4])) timestamp_ns/"
  "execution shares read from byte 20|s/if ((|pos\[22:19\])) shares       <=/if ((|pos[23:20])) shares       <=/"
  "one-byte message reported len_ok|s/len_ok    <= (idx == 7'd0) ? 1'b0 /len_ok    <= (idx == 7'd0) ? 1'b1 /"
  "unknown type reported known|s/default: spec_len = 8'd0;/default: spec_len = 8'd36;/"
)

survivors=0
for m in "${mutants[@]}"; do
  name=${m%%|*}; expr=${m#*|}
  mkdir -p "$work/m"; cp "$RTL" "$work/m/itch50_parser.v"
  sed -i "$expr" "$work/m/itch50_parser.v"
  if cmp -s "$RTL" "$work/m/itch50_parser.v"; then
    echo "ERROR  mutant did not apply: $name"; survivors=$((survivors+1)); continue
  fi
  rm -rf "$work/build"
  if ! verilator --cc --exe --build -Wno-fatal --Mdir "$work/build" "$work/m/itch50_parser.v" \
         "$PWD/tests/test_itch50_rtl.cpp" -o t >/dev/null 2>&1; then
    echo "ERROR  mutant did not build: $name"; survivors=$((survivors+1)); continue
  fi
  out=$("$work/build/t" "$ORACLE" 2>&1); rc=$?
  fails=$(grep -oE '[0-9]+ failures' <<<"$out" | tail -1)
  if [ $rc -ne 0 ]; then echo "killed   $name  ($fails)"
  else echo "SURVIVED $name"; survivors=$((survivors+1)); fi
done
echo "${#mutants[@]} mutants, $survivors survived"
[ $survivors -eq 0 ]
