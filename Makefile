.PHONY: lint smoke diff all clean

RTL    := rtl/itch50_parser.v
ORACLE := tests/data/itch50_oracle.txt

lint:
	verilator --lint-only -Wall $(RTL)

smoke:
	iverilog -g2012 -o /tmp/itch50_smoke_sim $(RTL) sim/smoke_tb.v
	vvp /tmp/itch50_smoke_sim

diff:
	mkdir -p build/rtl
	verilator --cc --exe --build -Wall --Mdir build/rtl $(CURDIR)/$(RTL) $(CURDIR)/tests/test_itch50_rtl.cpp -o test_itch50_rtl
	./build/rtl/test_itch50_rtl $(ORACLE)

all: lint smoke diff

clean:
	rm -rf build /tmp/itch50_smoke_sim
