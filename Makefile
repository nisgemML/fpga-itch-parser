.PHONY: lint smoke diff diff-delete all clean

RTL := rtl/itch_add_order_parser.v
RTL_DELETE := rtl/itch_delete_order_parser.v
CPP_INC := $(CURDIR)/third_party/udp-multicast-receiver/include

lint:
	verilator --lint-only -Wall $(RTL)
	verilator --lint-only -Wall $(RTL_DELETE)

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

diff-delete:
	mkdir -p build/diff_delete
	verilator --cc --exe --build -Wall --Mdir build/diff_delete \
		-CFLAGS "-I$(CPP_INC)" \
		$(CURDIR)/$(RTL_DELETE) $(CURDIR)/tests/test_differential_delete.cpp \
		-o test_differential_delete
	./build/diff_delete/test_differential_delete

all: lint smoke diff diff-delete

clean:
	rm -rf build /tmp/itch_smoke_sim
