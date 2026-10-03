# fpga-itch-parser

A real, synthesizable Verilog parser for ITCH 5.0 AddOrder messages,
verified two ways: simulated correctness (Verilator, Icarus Verilog) and
**differential testing against the actual C++ parser this portfolio uses
in production** — [udp-multicast-receiver](https://github.com/nisgemML/udp-multicast-receiver)'s
`ItchAddOrder::parse()`, vendored here unmodified, not reimplemented or
approximated.

## Read this before the rest of the README

**What this proves:** correct, synthesizable RTL for **two** real, 
structurally different ITCH message layouts this portfolio's real feed
handler uses — AddOrder (36 bytes) and OrderDelete (19 bytes, with two
genuinely unextracted skip-byte fields, matched to the real parser's
exact behavior, not "improved" on it) — each checked field-for-field
against 10,003 inputs (10,000 random + 3 explicit boundary cases) run
through both the RTL (via Verilator) and the real C++ parser in the same
process. **20,006 total comparisons, 0 mismatches.** Two differently-shaped
message types means this demonstrates a methodology that generalizes,
not a single lucky case.

**What this does NOT prove, stated plainly:** this was never synthesized
onto physical FPGA hardware. No Vivado, no Quartus, no vendor toolchain,
no FPGA board — none of those are available in the environment this was
built in. "Verified via simulation" and "deployed on real silicon" are
different claims; only the first one is made here. See
[`LIMITATIONS.md`](LIMITATIONS.md) for exactly what closing that gap
would require.

## Why this exists

FPGA/HDL experience was an identified gap against top-tier HFT firm
requirements for the most latency-sensitive roles (Optiver, Jump
Trading, Citadel Securities all call this out specifically for their
hottest paths). This repo closes the "have I ever actually written and
verified real RTL" question honestly — a working parser for a real,
already-used-elsewhere protocol, checked against the real software
reference — rather than leaving it as an unverified line on a resume.

## The differential test, precisely

`tests/test_differential.cpp` generates random `AddOrder` messages,
encodes each into the exact 36-byte wire format
(`third_party/udp-multicast-receiver/include/feed/wire_format.hpp`'s own
documented byte layout), and feeds the identical bytes to:

1. The RTL (`rtl/itch_add_order_parser.v`), simulated via Verilator —
   real synthesizable Verilog, clocked one byte per cycle, not a
   behavioral C++ model pretending to be hardware.
2. The real C++ reference, `feed::ItchAddOrder::parse()` — vendored
   unmodified from the actual repo this portfolio uses in production.

Every field is compared: `timestamp_ns`, `order_ref`, `side`, `shares`,
`stock`, `price`. This is differential testing applied across a
hardware/software boundary, the same discipline
[tick-to-trade](https://github.com/nisgemML/tick-to-trade) uses between
two independent software implementations of an order book — extended
here to two independent implementations (one in Verilog, one in C++) of
the same wire protocol.

```
$ make diff
3 explicit edge cases checked
10000 messages compared, 0 mismatches (RTL simulation vs real C++ parser)

$ make diff-delete
3 explicit edge cases checked
10000 messages compared, 0 mismatches (RTL simulation vs real C++ parser)
```

The second message type's RTL and test built and passed clean on the
first real run — worth noting plainly rather than silently: the three
real bugs in `BUGS_FOUND.md` (a testbench timing bug, Verilator's `-I`
vs `-CFLAGS`, a missing build directory) were all general lessons from
building the *first* parser, and applying them correctly the second time
is a legitimate, honest reason this went smoothly, not evidence nothing
could have gone wrong.

## Build & run

Needs `verilator` (5.x+) and `iverilog` (for the smoke test):

```bash
sudo apt-get install -y verilator iverilog
make lint         # verilator --lint-only, both modules, 0 warnings
make smoke        # single-message sanity check via Icarus Verilog
make diff         # AddOrder differential test
make diff-delete  # OrderDelete differential test
make all          # all of the above
```

## What's in here

| Path | What it is |
|---|---|
| `rtl/itch_add_order_parser.v` | AddOrder parser: one byte per clock, `msg_valid` pulses once all 36 bytes are consumed |
| `rtl/itch_delete_order_parser.v` | OrderDelete parser: same interface convention, 19 bytes, matches the real parser's skip-byte behavior exactly |
| `sim/smoke_tb.v` | Single hand-encoded AddOrder message, basic sanity check (Icarus Verilog) |
| `tests/test_differential.cpp` | AddOrder: RTL vs the actual C++ reference, 10,003 inputs |
| `tests/test_differential_delete.cpp` | OrderDelete: same methodology, 10,003 more inputs |
| `third_party/udp-multicast-receiver/` | Vendored `wire_format.hpp`, unmodified |

## Related

- [udp-multicast-receiver](https://github.com/nisgemML/udp-multicast-receiver) — the real C++ parser this RTL is checked against
- [tick-to-trade](https://github.com/nisgemML/tick-to-trade) — where that C++ parser is actually used, in a running pipeline
