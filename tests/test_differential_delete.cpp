// tests/test_differential_delete.cpp
//
// Same methodology as test_differential.cpp, applied to the second real
// message type: ITCH OrderDelete ('D'), 19 bytes, RTL simulated via
// Verilator vs feed::ItchDeleteOrder::parse(), the actual C++ reference.
// Deliberately includes the locate/tracking skip-bytes behavior matching
// the real parser exactly -- see rtl/itch_delete_order_parser.v's own
// comments for why that's a correctness requirement here, not an
// oversight to "fix."

#include "Vitch_delete_order_parser.h"
#include "verilated.h"

#include "feed/wire_format.hpp"

#include <cstdio>
#include <cstring>
#include <random>
#include <vector>

namespace {

void clock_tick(Vitch_delete_order_parser& dut) {
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
}

struct DeleteFields {
    uint8_t  msg_type;
    uint64_t timestamp_ns;
    uint16_t locate;   // on the wire, not extracted by either implementation
    uint16_t tracking; // same
    uint64_t order_ref;
};

std::vector<uint8_t> encode_delete_order(const DeleteFields& f) {
    std::vector<uint8_t> b(19, 0);
    b[0] = f.msg_type;
    for (int i = 0; i < 6; ++i) b[1 + i] = static_cast<uint8_t>(f.timestamp_ns >> (8 * (5 - i)));
    b[7] = static_cast<uint8_t>(f.locate >> 8);
    b[8] = static_cast<uint8_t>(f.locate);
    b[9] = static_cast<uint8_t>(f.tracking >> 8);
    b[10] = static_cast<uint8_t>(f.tracking);
    for (int i = 0; i < 8; ++i) b[11 + i] = static_cast<uint8_t>(f.order_ref >> (8 * (7 - i)));
    return b;
}

struct ExtractedFields {
    uint8_t  msg_type;
    uint64_t timestamp_ns;
    uint64_t order_ref;
};

ExtractedFields run_rtl(Vitch_delete_order_parser& dut, const std::vector<uint8_t>& bytes) {
    for (uint8_t b : bytes) {
        dut.byte_valid = 1;
        dut.byte_in = b;
        clock_tick(dut);
    }
    dut.byte_valid = 0;
    ExtractedFields out{};
    out.msg_type     = static_cast<uint8_t>(dut.msg_type);
    out.timestamp_ns = dut.timestamp_ns;
    out.order_ref    = dut.order_ref;
    return out;
}

ExtractedFields run_cpp_reference(const std::vector<uint8_t>& bytes) {
    feed::ItchDeleteOrder parsed{};
    const bool ok = feed::ItchDeleteOrder::parse(bytes.data(), bytes.size(), parsed);
    ExtractedFields out{};
    if (!ok) { out.msg_type = 0xFF; return out; }
    out.msg_type     = bytes[0];
    out.timestamp_ns = parsed.timestamp_ns;
    out.order_ref    = parsed.order_ref;
    return out;
}

} // namespace

int main() {
    std::mt19937_64 rng(1234);
    std::uniform_int_distribution<uint64_t> ref_dist(1, UINT64_C(0xFFFFFFFFFFFFFF));
    std::uniform_int_distribution<uint64_t> ts_dist(0, UINT64_C(0xFFFFFFFFFFFF));
    std::uniform_int_distribution<uint16_t> field_dist(0, 0xFFFF);

    constexpr int kN = 10'000;
    int mismatches = 0;

    auto dut = std::make_unique<Vitch_delete_order_parser>();
    dut->rst_n = 0;
    clock_tick(*dut);
    clock_tick(*dut);
    dut->rst_n = 1;
    clock_tick(*dut);

    // Explicit boundary cases, same discipline as the AddOrder test.
    const std::vector<DeleteFields> edge_cases = {
        {'D', 0, 0, 0, 0},
        {'D', 0xFFFFFFFFFFFFULL, 0xFFFF, 0xFFFF, 0xFFFFFFFFFFFFFFFFULL},
        {'D', 999999, 0x1234, 0x5678, 42},
    };
    for (std::size_t i = 0; i < edge_cases.size(); ++i) {
        const auto bytes = encode_delete_order(edge_cases[i]);
        const auto rtl_out = run_rtl(*dut, bytes);
        const auto cpp_out = run_cpp_reference(bytes);
        const bool match = (rtl_out.msg_type == cpp_out.msg_type) &&
                            (rtl_out.timestamp_ns == cpp_out.timestamp_ns) &&
                            (rtl_out.order_ref == cpp_out.order_ref);
        if (!match) { std::fprintf(stderr, "EDGE CASE %zu MISMATCH\n", i); ++mismatches; }
    }
    std::printf("%zu explicit edge cases checked\n", edge_cases.size());

    for (int iter = 0; iter < kN; ++iter) {
        DeleteFields f{};
        f.msg_type = 'D';
        f.timestamp_ns = ts_dist(rng);
        f.locate = field_dist(rng);
        f.tracking = field_dist(rng);
        f.order_ref = ref_dist(rng);

        const auto bytes = encode_delete_order(f);
        const auto rtl_out = run_rtl(*dut, bytes);
        const auto cpp_out = run_cpp_reference(bytes);

        const bool match = (rtl_out.msg_type == cpp_out.msg_type) &&
                            (rtl_out.timestamp_ns == cpp_out.timestamp_ns) &&
                            (rtl_out.order_ref == cpp_out.order_ref);
        if (!match) {
            ++mismatches;
            if (mismatches <= 5) {
                std::fprintf(stderr, "MISMATCH iter=%d: RTL{ts=%lu ref=%lu} CPP{ts=%lu ref=%lu}\n",
                              iter, rtl_out.timestamp_ns, rtl_out.order_ref, cpp_out.timestamp_ns, cpp_out.order_ref);
            }
        }
    }

    std::printf("%d messages compared, %d mismatches (RTL simulation vs real C++ parser)\n", kN, mismatches);
    return mismatches == 0 ? 0 : 1;
}
