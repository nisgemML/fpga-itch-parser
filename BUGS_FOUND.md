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
