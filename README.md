# fpga-itch-parser

A synthesizable Verilog parser for the **real NASDAQ TotalView-ITCH 5.0 message layout** — Stock Directory,
Add Order (with and without MPID), Order Executed (with and without price), Order Cancel, Order Delete and
Order Replace — verified in simulation against an **independent third-party ITCH implementation**, not
against code written from the same reading of the spec.

## Read this first

**What this proves.** The RTL's decoded fields equal the third-party [`itchfeed`](https://pypi.org/project/itchfeed/)
parser's on 1,214 test vectors — every field of every supported message type, including all-zero and all-max
boundary values — each driven three ways (messages isolated by idle cycles, back-to-back with no gap, and
back-to-back with random bubbles in `byte_valid`): **3,648 checks, 0 failures**. Fields a message type doesn't
carry must read zero (no leakage from the previous message); truncated, overlong, one-byte and undecoded-type
messages are flagged (`len_ok`, `msg_known`) and the parser recovers on the next message. The suite is
mutation-tested: four deliberate RTL bugs (legacy offsets, no field clearing, off-by-one length check, wrong
Replace offset) fail it with 450–3,644 failures each.

**What this does not prove.**
- **Never synthesized.** No Vivado/Quartus, no board: this is simulation (Verilator, Icarus Verilog), nothing more. See [`LIMITATIONS.md`](LIMITATIONS.md).
- **The 1,214 vectors are generated** (random and boundary values), not captured from the exchange. `scripts/real_to_oracle.py` samples a *real* NASDAQ file into the same format so the RTL can be checked on actual exchange bytes against the same third-party oracle (below) — **that run has not been done yet.**
- **8 of NASDAQ's ~20 message types** are decoded; framing (message boundaries) comes from the transport via `byte_last`, as it does in real hardware.

**History worth knowing.** An earlier version of this repo parsed the portfolio's *simplified* layout (no stock-locate/tracking fields), and its "20,006 differential comparisons, 0 mismatches" were real — but between two implementations of the same wrong layout. That's [`BUGS_FOUND.md`](BUGS_FOUND.md) #4; those modules are gone.

## The layout (from the NASDAQ spec, v5.0 03/06/2015, section 4)

Every message starts `type@0, stock locate@1 (2), tracking number@3 (2), timestamp@5 (6)`; all multi-byte fields are big-endian.

| Type | Message | Bytes | Fields after the header |
|---|---|---|---|
| `R` | Stock Directory | 39 | stock@11 |
| `A` / `F` | Add Order / with MPID | 36 / 40 | ref@11 side@19 shares@20 stock@24 price@32 (`F`: attribution@36) |
| `E` / `C` | Order Executed / with price | 31 / 36 | ref@11 shares@19 match@23 (`C`: printable@31 price@32) |
| `X` | Order Cancel (partial) | 23 | ref@11 canceled shares@19 |
| `D` | Order Delete | 19 | ref@11 |
| `U` | Order Replace | 35 | orig ref@11 new ref@19 shares@27 price@31 |

## Interface

One byte per clock (`byte_valid`/`byte_in`), with `byte_last` on each message's final byte. After `byte_last`,
`msg_valid` pulses for one cycle and the outputs hold that message's fields — read them only then.
`msg_known`: a type this block decodes. `len_ok`: received length equals the spec's length for that type.

## Run it

Needs `verilator` (5.x) and `iverilog`:

```bash
sudo apt-get install -y verilator iverilog g++
make lint    # verilator --lint-only -Wall, 0 warnings
make smoke   # one hand-encoded Add Order (Icarus Verilog)
make diff    # the real test: RTL vs the third-party oracle vectors, 3 drive modes + framing errors
make all
```

### Check the RTL on a real NASDAQ file

```bash
python3 -m venv ~/venv && ~/venv/bin/pip install -r scripts/requirements.txt     # itchfeed==1.6.4
~/venv/bin/python scripts/real_to_oracle.py ~/itch/20191230.BX_ITCH_50.gz 100 200000 > /tmp/real_oracle.txt
./build/rtl/test_itch50_rtl /tmp/real_oracle.txt
```

That takes every 100th supported message of the file (up to 200,000), with the hex bytes exactly as NASDAQ sent
them and every expected value read from `itchfeed`'s parser, and runs the same RTL checks on them.

## What's in here

| Path | What it is |
|---|---|
| `rtl/itch50_parser.v` | The parser |
| `sim/smoke_tb.v` | One hand-encoded Add Order (Icarus Verilog) |
| `tests/test_itch50_rtl.cpp` | The differential test: RTL (Verilator) vs oracle vectors, three drive modes, framing errors, recovery |
| `tests/data/itch50_oracle.txt` | 1,214 vectors; **regenerate** with `scripts/gen_itch50_oracle.py <dir>` (CI checks it is byte-for-byte reproducible) |
| `scripts/real_to_oracle.py` | Samples a real NASDAQ file into the same vector format |

## Related

- [tick-to-trade](https://github.com/nisgemML/tick-to-trade) — a C++ pipeline whose ITCH 5.0 parser reads the same layout; its spec-accurate decoder replayed a real NASDAQ BX day (29.2M messages, zero anomalies)
