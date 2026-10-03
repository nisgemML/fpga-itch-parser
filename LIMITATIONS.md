# Limitations

| Area | Current | Not claimed |
|------|---------|-------------|
| Verification | Simulated correctness via Verilator and Icarus Verilog; differential-tested against the real C++ production parser across 10,003 inputs, 0 mismatches | Synthesis on real FPGA hardware — no Vivado, Quartus, or physical FPGA board available in this environment |
| Message coverage | AddOrder (`'A'`/`'F'`) only | Any other ITCH message type (OrderExecuted, OrderCancel, OrderDelete, etc.) — the real C++ parser handles these (see `wire_format.hpp`), the RTL does not yet |
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

## Extending message coverage

The RTL's byte-counter/case-statement structure generalizes directly to
other fixed-layout ITCH messages (OrderCancel, OrderDelete are both
simpler than AddOrder — fewer fields, shorter total length) by adding a
`msg_type`-dispatched parallel field map. Not done here because AddOrder
alone is sufficient to prove the differential-testing methodology works;
extending coverage is mechanical repetition of that same methodology, not
a new technique.
