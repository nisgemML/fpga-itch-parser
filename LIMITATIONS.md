# Limitations

| Area | Current | Not claimed |
|------|---------|-------------|
| Verification | Simulation (Verilator, Icarus Verilog): RTL == third-party `itchfeed` parser on 1,214 vectors x 3 drive modes + framing-error cases (3,648 checks, 0 failures); 4/4 deliberate RTL bugs caught | Synthesis or any behaviour on real FPGA hardware — no Vivado/Quartus/board available |
| Real data | `scripts/real_to_oracle.py` turns a real NASDAQ file into oracle-checked vectors | **That it has been run.** Today's vectors are generated (random + boundary values), not captured from the exchange |
| Message coverage | 8 types: `R A F E C X D U` (the Stock Directory plus every book-affecting message) | The rest of the spec (`S H Y L V W K P Q B I N`): these are framed correctly and reported `msg_known=0`, but not decoded |
| Framing | Supplied by the transport (`byte_last`), as in real hardware (MoldUDP64, or the 2-byte length prefix in NASDAQ's sample files) | A block that finds message boundaries on its own from the byte stream |
| Timing | None — no synthesis means no place-and-route, no timing report, no clock frequency | Any achievable clock rate or latency in cycles beyond "one byte per clock, fields valid the cycle after `byte_last`" |
| Interface | Byte-wide valid/data/last streaming | A bus standard (AXI-Stream, Avalon-ST); this is a minimal interface sufficient for the tests |
| Book logic | None — this is the decode stage only | Order-book maintenance in hardware |

## What would close the synthesis gap

1. **Easiest, weakest:** run the RTL through an open-source flow (Yosys) for a resource/timing *estimate* — proves it synthesizes, not that it works on a board.
2. **Real:** a bitstream on an actual FPGA (Vivado or Quartus), e.g. a rented cloud FPGA instance, with the same oracle vectors replayed through it.
