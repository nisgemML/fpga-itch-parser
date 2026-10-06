# Limitations

| Area | Current | Not claimed |
|------|---------|-------------|
| Verification | Simulation (Verilator, Icarus Verilog): RTL == third-party `itchfeed` parser on 1,214 vectors x 3 drive modes + framing-error cases (3,648 checks, 0 failures); `scripts/mutate.sh`: 8/8 deliberate RTL bugs caught (1 to 3,644 failing checks each) | Any behaviour on real FPGA hardware — no bitstream loaded, no board |
| Real data | `scripts/real_to_oracle.py` turns a real NASDAQ file into oracle-checked vectors | **That it has been run.** Today's vectors are generated (random + boundary values), not captured from the exchange |
| Message coverage | 8 types: `R A F E C X D U` (the Stock Directory plus every book-affecting message) | The rest of the spec (`S H Y L V W K P Q B I N`): these are framed correctly and reported `msg_known=0`, but not decoded |
| Framing | Supplied by the transport (`byte_last`), as in real hardware (MoldUDP64, or the 2-byte length prefix in NASDAQ's sample files) | A block that finds message boundaries on its own from the byte stream |
| Synthesis / timing | Open-source flow (`synth/run_synth.sh`): Yosys + nextpnr-ecp5 on a Lattice ECP5-25F, 1,034 LUT4 + 511 FF, post-route Fmax 137-141 MHz over 3 seeds (`synth/README.md`, including the before/after of two timing fixes) | Vendor sign-off timing (Vivado/Quartus), or any other device family; nextpnr's timing model is an estimate |
| Throughput | One byte per clock: ~1.1 Gbit/s at ~137 MHz | Line rate. 10GbE needs an 8-byte-wide datapath (several messages may start in one bus word); this is a decode core, not a line-rate design |
| Interface | Byte-wide valid/data/last streaming | A bus standard (AXI-Stream, Avalon-ST); this is a minimal interface sufficient for the tests |
| Book logic | None — this is the decode stage only | Order-book maintenance in hardware |

## What would close the synthesis gap

1. ~~Open-source synthesis for a resource/timing estimate~~ — **done** (`synth/`): it synthesizes, places and routes.
2. **Real:** a bitstream on an actual FPGA (Vivado or Quartus), e.g. a rented cloud FPGA instance, with the same oracle vectors replayed through it.
3. **Line rate:** an 8-byte datapath, which is a redesign, not a tweak.
