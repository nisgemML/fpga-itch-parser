# fpga-itch-parser

A real, synthesizable Verilog parser for ITCH 5.0 AddOrder messages,
verified two ways: simulated correctness (Verilator, Icarus Verilog) and
**differential testing against the actual C++ parser this portfolio uses
in production** — [udp-multicast-receiver](https://github.com/nisgemML/udp-multicast-receiver)'s
`ItchAddOrder::parse()`, vendored here unmodified, not reimplemented or
approximated.

## Read this before the rest of the README

**What this proves:** a correct, synthesizable RTL implementation of the
exact wire format this portfolio's real feed handler uses — same byte
offsets, same big-endian field encoding, same message layout, checked
field-for-field against 10,003 inputs (10,000 random + 3 explicit
boundary cases: all-zero fields, all-max-width fields, a representative
case) run through both the RTL (via Verilator) and the real C++ parser
in the same process. **0 mismatches.**

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
```

## Build & run

Needs `verilator` (5.x+) and `iverilog` (for the smoke test):

```bash
sudo apt-get install -y verilator iverilog
make lint    # verilator --lint-only, 0 warnings
make smoke   # single-message sanity check via Icarus Verilog
make diff    # the real differential test above
make all     # all three
```

## What's in here

| Path | What it is |
|---|---|
| `rtl/itch_add_order_parser.v` | The parser: one byte per clock, `msg_valid` pulses once all 36 bytes of a message are consumed |
| `sim/smoke_tb.v` | Single hand-encoded message, basic sanity check (Icarus Verilog) |
| `tests/test_differential.cpp` | The real test: RTL vs the actual C++ reference, 10,003 inputs |
| `third_party/udp-multicast-receiver/` | Vendored `wire_format.hpp`, unmodified |

## Related

- [udp-multicast-receiver](https://github.com/nisgemML/udp-multicast-receiver) — the real C++ parser this RTL is checked against
- [tick-to-trade](https://github.com/nisgemML/tick-to-trade) — where that C++ parser is actually used, in a running pipeline
