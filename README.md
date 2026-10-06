# fpga-itch-parser

A synthesizable Verilog parser for the **real NASDAQ TotalView-ITCH 5.0 message layout** — Stock Directory,
Add Order (with and without MPID), Order Executed (with and without price), Order Cancel, Order Delete and
Order Replace — verified in simulation against an **independent third-party ITCH implementation**, not
against code written from the same reading of the spec.

**In 30 seconds**
- **Real exchange data:** 200,000 messages sampled across a full NASDAQ main-venue day (January 30, 2020: 423 million messages), every field checked against a third-party ITCH parser, driven three ways. That is **600,006 checks, 0 failures**.
- **Spec-exact on generated edge cases too:** 1,214 random and boundary-value messages, 3,648 checks, 0 failures.
- **The tests can fail:** `scripts/mutate.sh` injects 8 realistic RTL bugs (wrong offsets, no field clearing, off-by-one lengths). Every one is caught, by 1 to 3,644 failing checks.
- **It synthesizes and meets a measured clock:** open-source place-and-route on a Lattice ECP5-25F gives 1,034 LUTs and 137–141 MHz. Critical-path analysis and two timing fixes took it from 107–118 MHz ([`synth/README.md`](synth/README.md)).
- **Honest about scope:** one byte per clock is ~1.1 Gbit/s, a verified decode core, not a 10GbE line-rate design. It has never run on a board.

## Read this first

**What this proves.** The RTL's decoded fields equal the third-party [`itchfeed`](https://pypi.org/project/itchfeed/)
parser's on 1,214 test vectors — every field of every supported message type, including all-zero and all-max
boundary values — each driven three ways (messages isolated by idle cycles, back-to-back with no gap, and
back-to-back with random bubbles in `byte_valid`): **3,648 checks, 0 failures**. Fields a message type doesn't
carry must read zero (no leakage from the previous message); truncated, overlong, one-byte and undecoded-type
messages are flagged (`len_ok`, `msg_known`) and the parser recovers on the next message. The suite is
mutation-tested by a script in the repo (`scripts/mutate.sh`): 8 deliberate RTL bugs (legacy offsets, no field
clearing, off-by-one length check, wrong Replace/Executed/timestamp offsets, one-byte and unknown-type
misreporting) each fail it, with 1 to 3,644 failures.

**What this does not prove.**
- **Synthesized with an open-source flow only.** Yosys + nextpnr-ecp5 place and route it on a Lattice ECP5-25F, for 1,034 LUT4 + 511 FF at 137–141 MHz post-route. That is an estimate from nextpnr's timing model: no vendor sign-off, no bitstream, no board. See [`synth/README.md`](synth/README.md) and [`LIMITATIONS.md`](LIMITATIONS.md).
- **Not line rate.** One byte per clock is ~1.1 Gbit/s at that clock. 10GbE needs an 8-byte datapath.
- **Two sets of vectors.** The 1,214 checked-in vectors are generated (random and boundary values). `scripts/real_to_oracle.py` samples a *real* NASDAQ file into the same format, and that run is recorded below: 200,000 real messages, 600,006 checks, 0 failures. The real-file vectors are not checked in, because NASDAQ's file is 5.6 GB and the vectors are its bytes.
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
scripts/mutate.sh     # 8 deliberate RTL bugs; each must make `make diff`'s test fail (~1 min)
synth/run_synth.sh    # Yosys + nextpnr-ecp5: LUT/FF counts and post-route Fmax (needs yosys, nextpnr-ecp5)
```

### Check the RTL on a real NASDAQ file

```bash
python3 -m venv ~/venv && ~/venv/bin/pip install -r scripts/requirements.txt     # itchfeed==1.6.4
~/venv/bin/python scripts/real_to_oracle.py ~/itch/01302020.NASDAQ_ITCH50.gz 2000 200000 > /tmp/real_oracle.txt
./build/rtl/test_itch50_rtl /tmp/real_oracle.txt
```

That takes every 100th supported message of the file (up to 200,000), with the hex bytes exactly as NASDAQ sent
them and every expected value read from `itchfeed`'s parser, and runs the same RTL checks on them.

The pipeline itself is checked without a real file: the 1,214 vectors framed as a NASDAQ-format file
(2-byte big-endian length prefix, gzipped, with interleaved System Event messages the RTL does not decode)
go through `real_to_oracle.py` and come back byte-identical to `tests/data/itch50_oracle.txt`, and then
pass all 3,648 checks.

**Recorded run on a real file** (WSL2 on an Intel Core Ultra 7 155H, Verilator 5.032):

```
file:   01302020.NASDAQ_ITCH50.gz   (NASDAQ main venue, 2020-01-30; 5,597,158,940 bytes,
                                     md5 baa0a7dfbf4384841a01594cd931e5c0; 423,285,709 messages)
sample: every 2,000th supported message, stopping at 200,000 -> covers the first 400,000,000
        supported messages, i.e. at least 94.5% of the file: essentially the whole trading day
        R=4  A=89,042  F=873  E=3,892  C=73  X=2,442  D=86,243  U=17,431
        0 supported-type messages with a length that is not the spec's
result: 200000 oracle messages x 3 drive modes + 6 framing cases: 600006 checks, 0 failures
```

An earlier sample from the same file (every 100th message, also 200,000 vectors) also passed with
600,006 checks and 0 failures. That sample only reached the first 20 million supported messages
(roughly the first 5% of the file), so the every-2,000th run above is the one that spans the day.

## What's in here

| Path | What it is |
|---|---|
| `rtl/itch50_parser.v` | The parser |
| `sim/smoke_tb.v` | One hand-encoded Add Order (Icarus Verilog) |
| `tests/test_itch50_rtl.cpp` | The differential test: RTL (Verilator) vs oracle vectors, three drive modes, framing errors, recovery |
| `tests/data/itch50_oracle.txt` | 1,214 vectors; **regenerate** with `scripts/gen_itch50_oracle.py <dir>` (CI checks it is byte-for-byte reproducible) |
| `scripts/real_to_oracle.py` | Samples a real NASDAQ file into the same vector format |
| `scripts/mutate.sh` | Mutation testing: 8 injected RTL bugs, all must be caught |
| `synth/` | Open-source synthesis + place-and-route (ECP5), results and timing history |

## Related

- [tick-to-trade](https://github.com/nisgemML/tick-to-trade) — a C++ pipeline whose ITCH 5.0 parser reads the same layout; its spec-accurate decoder replayed a real NASDAQ BX day (29.2M messages, zero anomalies)
