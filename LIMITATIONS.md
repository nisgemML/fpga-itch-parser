# Limitations

| Area | Current | Not claimed |
|------|---------|-------------|
| Verification | Simulated correctness via Verilator and Icarus Verilog; differential-tested against the real C++ production parser across 10,003 inputs, 0 mismatches | Synthesis on real FPGA hardware — no Vivado, Quartus, or physical FPGA board available in this environment |
| Message coverage | AddOrder (`'A'`/`'F'`) and OrderDelete (`'D'`) — two real, differently-shaped layouts (36 bytes vs 19, with/without skip-bytes), same differential-testing methodology for both | OrderExecuted, OrderCancel, and other ITCH message types the real C++ parser handles (see `wire_format.hpp`) — the RTL does not cover these yet |
| Timing closure | None performed — no synthesis means no place-and-route, no timing report, no clock-frequency claim | Any specific achievable clock frequency on real hardware |
| Interface | Simple byte-valid/byte-in streaming interface, one byte per clock | Any specific bus standard (AXI-Stream, Avalon-ST, etc.) — this is a minimal interface sufficient to prove correctness, not a drop-in IP core |

## What would need to change to close the synthesis gap

In order of how much it would actually prove, not how easy each is:

1. **Weakest but easiest:** run the RTL through an open-source synthesis
   flow (e.g., Yosys) targeting a specific FPGA family, to get a real
   resource-utilization and timing estimate. Proves the RTL is
   synthesizable at all and gives a rough area/timing picture; does not
   prove it works on a real board (bitstream generation and actual
   hardware testing are separate, further steps even after this).
2. **Real, but needs hardware access:** generate a bitstream (Vivado for
   Xilinx, Quartus for Intel/Altera) and test on an actual FPGA
   development board. This is what the job postings that motivated this
   repo actually mean by FPGA experience, and needs physical access to
   that hardware and those toolchains, neither of which this environment
   has.

## Extending message coverage further

OrderDelete (`rtl/itch_delete_order_parser.v`) already proves the
methodology generalizes, not just works once: a second, differently-shaped
real message (19 bytes vs 36, with two genuinely unextracted skip-byte
fields matching the real parser's own behavior exactly) checked the same
way, 10,003 more differential comparisons, 0 mismatches. Remaining ITCH
types (OrderExecuted, OrderCancel, etc.) are the same mechanical
repetition of this now-twice-proven methodology, not a new technique —
not done here because two real, structurally different message types is
sufficient to demonstrate the approach generalizes.
