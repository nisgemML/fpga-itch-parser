.PHONY: lint smoke diff all clean

RTL := rtl/itch_add_order_parser.v
CPP_INC := $(CURDIR)/third_party/udp-multicast-receiver/include

lint:
	verilator --lint-only -Wall $(RTL)

smoke:
	iverilog -g2012 -o /tmp/itch_smoke_sim $(RTL) sim/smoke_tb.v
	vvp /tmp/itch_smoke_sim

diff:
	mkdir -p build/diff
	verilator --cc --exe --build -Wall --Mdir build/diff \
		-CFLAGS "-I$(CPP_INC)" \
		$(CURDIR)/$(RTL) $(CURDIR)/tests/test_differential.cpp \
		-o test_differential
	./build/diff/test_differential

all: lint smoke diff

clean:
	rm -rf build /tmp/itch_smoke_sim
