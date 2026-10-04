# Bugs found while building this

Real mistakes caught while building, not a hypothetical list.

---

### 1. Testbench checked `msg_valid` one clock cycle too late

**Symptom:** The very first run of `sim/smoke_tb.v` failed immediately —
`msg_valid not asserted after 36 bytes` — despite the RTL appearing
correct on inspection.
**Root cause, found by adding cycle-by-cycle `$display` tracing rather
than guessing:** `msg_valid` is a one-cycle pulse, asserted only on the
clock edge immediately following the 36th byte, then deasserted again
the cycle after (by design — it's a pulse, not a level). The original
testbench drove all 36 bytes in a loop (one `@(posedge clk)` per byte,
36 edges total), then added one *more* `@(posedge clk)` before checking
`msg_valid` — sampling it exactly one cycle after it had already
deasserted. The RTL was correct the entire time; the testbench's own
timing was off by one edge.
**Fix:** removed the extra edge; check `msg_valid` immediately after the
byte-feeding loop's last iteration, which is the actual cycle the pulse
is valid on. Confirmed via the same cycle-by-cycle trace that
`msg_valid` and `byte_count` both behave exactly as the RTL's comments
describe once checked at the right time.
**Lesson:** a failing test and a broken design under test are not the
same claim, and conflating them wastes time fixing the wrong thing. The
fix here was never in `rtl/itch_add_order_parser.v` — it was entirely in
when the testbench looked.

### 2. Verilator's `-I` flag is a Verilog include path, not a C++ one

**Symptom:** `%Error: Cannot find file containing module:
third_party/udp-multicast-receiver/include` when trying to pass the C++
reference parser's include directory to Verilator.
**Fix:** Verilator's `-I<dir>` is specifically for locating Verilog
`` `include `` files; the actual knob for the C++ compiler's include path
during the `--exe --build` step is `-CFLAGS "-I<dir>"`, which passes the
flag through to the underlying `g++` invocation instead. One-line fix
once the actual flag's purpose (not just its name) was checked rather
than assumed from how `-I` works in every other C/C++ toolchain.

### 3. Verilator's generated `Makefile` needs an existing output directory

**Symptom:** `%Error: Cannot write build/diff/Vitch_add_order_parser__Syms.cpp`
on a clean checkout, despite the exact same command succeeding on a
second run.
**Root cause:** `--Mdir build/diff` tells Verilator where to generate
its intermediate build files, but it doesn't reliably create nested
parent directories that don't already exist — it worked the first time
only because an earlier, unrelated `build/` directory already existed
from prior experimentation in the same session.
**Fix:** `Makefile`'s `diff` target now explicitly runs `mkdir -p
build/diff` before invoking Verilator, rather than relying on it having
been created by something else earlier. Verified by removing `build/`
entirely and re-running `make all` from a genuinely clean checkout.

### 4. The RTL parsed the wrong layout — and its 20,006 passing comparisons were real, which is why nobody noticed
**Symptom:** none. The earlier modules (`itch_add_order_parser.v`, `itch_delete_order_parser.v`) matched the portfolio's C++ parser on 20,006 inputs with 0 mismatches. But that parser reads a *simplified* layout (timestamp at +1, order reference at +7, no stock-locate or tracking fields). The real NASDAQ ITCH 5.0 layout has `locate@1, tracking@3, timestamp@5, order_ref@11` — found while reading the official spec to replay a real NASDAQ file in tick-to-trade (its BUGS_FOUND.md #15). Fed a real message, both the C++ parser and this RTL would have read every field four bytes off.
**Why the tests couldn't see it:** they compared two implementations of the same wrong assumption. That is a self-consistency check, and it is exactly as strong as the independence between the thing under test and its reference — here, none.
**Fix:** replaced, not patched. `rtl/itch50_parser.v` decodes the real layout, and the reference is now a third-party implementation (`itchfeed`) whose own `struct` format strings reproduce the spec's message lengths — expected values come out of *its* parser, not out of anything in this repo. The legacy modules and the vendored legacy C++ parser were deleted. Mutation test: pointing Add Order's reference back at the legacy offset (+7) now fails 900 checks.
**Lesson:** a green differential test across a hardware/software boundary sounds impressive and says nothing about whether both sides were *right* — only that they agreed.

### 5. A test expectation that wasn't independent after all
**Symptom:** while reviewing the new suite, the expected attribution of the Add Order-with-MPID (`F`) message was a hardcoded constant ("NSDQ", the value the generator packs in), not a value read out of the oracle — the one field in the whole suite whose expectation came from the generator's intent instead of the third-party parser.
**Fix:** `scripts/gen_itch50_oracle.py` now records `attribution` from the oracle's parser like every other field, the vectors were regenerated, and the test reads it from the vector file. The refactor that let the real-file sampler share one function with the generator was checked to leave the generated data byte-identical.
**Lesson:** "independent oracle" is a property of every expectation individually, and a suite can be 99% independent and still have one convenient constant in it.

### 6. A green result on zero test vectors
**Symptom:** the first attempt to check the RTL on a real NASDAQ file. The sampler script crashed (its dependency, `itchfeed`, hadn't installed because the virtual environment couldn't be created), leaving its output file **empty** — and `test_itch50_rtl` was then run on that empty file anyway and printed `0 oracle messages ... 0 checks, 0 failures` followed by `PASS`. A harness that reports success when it was given nothing to check turns any upstream failure into a pass.
**Found by:** running the documented real-file procedure on a machine where a dependency step failed — not by any test.
**Fix:** the test now exits 2 with an explicit message when no vectors load. Verified both ways: an empty file is refused (exit 2, no PASS line); the real oracle file still passes with 3,648 checks. The same pattern was present in tick-to-trade's `test_itch50_oracle` and is fixed there too.
**Lesson:** "0 failures" and "everything passed" are different claims. A test is only evidence if it can fail for want of input as well as for wrong output.
