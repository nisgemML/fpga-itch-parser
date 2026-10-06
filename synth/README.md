# Synthesis and timing (open-source flow, estimate only)

```bash
synth/run_synth.sh     # yosys + nextpnr-ecp5; ~1 min
```

Target: Lattice ECP5 **LFE5U-25F, CABGA256**, chosen because its full
open-source flow exists (Yosys 0.33, nextpnr-ecp5 0.6, Project Trellis). This
proves the RTL **synthesizes and places and routes**, and gives the
timing that nextpnr's model reports. It is **not** a board result: no
bitstream was loaded, no hardware was clocked, and no vendor sign-off timing
(Vivado/Quartus) was run.

`synth_top.v` wraps the parser for place-and-route only. The parser has 459
output bits, more than the package has pins, so the wrapper registers them all
and XOR-reduces them (pipelined) to a single pin. Every output bit reaches that
pin, so synthesis cannot delete any parser logic, and the reduction has its own
register stages, so it is not on the parser's paths. The critical path reported
below is inside `dut` in every run.

## Results: three versions of the same RTL

All three pass the same 3,648 differential checks against the third-party
oracle. Fmax is post-route, for placement seeds 1/2/3.

| Version | LUT4 | FF | CCU2C | Fmax (MHz) | Critical path |
|---|---|---|---|---|---|
| Original | 985 | 466 | 49 | 117.6 / 106.8 / 111.1 | `idx` → type mux → 8-way spec-length case → compare → `len_ok` |
| + spec length registered at the type byte | 1019 | 471 | 49 | 117.3 / 116.4 / 109.6 | `idx` → range compares (carry chains) → clock enables of 64-bit field registers |
| + one-hot byte position (current) | 1034 | 511 | 8 | **137.2 / 136.6 / 141.3** | `msg_type` decode → field clock enables |

**What changed and why.** On the last byte of each message, the original
looked up the type's spec length and compared it with `idx + 1`, all in one
cycle. That is the first critical path. Registering the spec length when the
type byte arrives removes it, but **on its own it did not raise Fmax**: the
next path, from `idx` through 7-bit magnitude comparisons (`idx >= 20 && idx
<= 23`, built from carry chains) to the field-register enables, was nearly as
long. Replacing those comparisons with a one-hot byte-position register (`pos[k]
== (idx == k)`) turns each range into a small OR. That raised Fmax about 20%,
for 45 more flip-flops. The remaining critical path is the `msg_type` case
selecting which enables fire. The next step would be registering one-hot type
flags at byte 0.

## What the clock rate means for line rate

One byte per clock at ~137 MHz is **~1.1 Gbit/s**. 10GbE delivers 1.25 GB/s,
which would need a 1.25 GHz clock at one byte per cycle, far beyond FPGA
fabric. Production feed handlers use 8-byte (64-bit) or wider datapaths at
roughly 156–322 MHz and handle several messages starting inside one bus word.
This parser is a verified decode core, not a line-rate design. See
`../LIMITATIONS.md`.
