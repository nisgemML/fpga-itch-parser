// tests/test_differential.cpp
//
// The actual point of this repo: does the RTL parser (rtl/itch_add_order_parser.v,
// simulated via Verilator -- real synthesizable Verilog, not a C++ model
// pretending to be hardware) extract the exact same fields as the real
// C++ parser this portfolio actually uses in production
// (third_party/udp-multicast-receiver's ItchAddOrder::parse(), vendored
// here unmodified)?
//
// Both are driven from the identical 36-byte wire buffer for each of
// many randomly generated AddOrder messages -- not hand-picked examples,
// and not "both implementations agree because they share a spec
// document" (they don't share any code; this is testing two independent
// implementations of the same wire format against each other, the
// textbook definition of differential testing, applied across a
// hardware/software boundary instead of the usual two-software-
// implementations case this portfolio has used elsewhere, e.g.
// tick-to-trade's own differential test against an independent
// reference order book).

#include "Vitch_add_order_parser.h"
#include "verilated.h"

#include "feed/wire_format.hpp"

#include <cstdio>
#include <cstring>
#include <random>
#include <vector>

namespace {

void clock_tick(Vitch_add_order_parser& dut) {
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
}

struct AddOrderFields {
    uint8_t  msg_type;
    uint64_t timestamp_ns;
    uint64_t order_ref;
    uint8_t  side;
    uint32_t shares;
    uint64_t stock_packed; // 8 bytes packed MSB-first, same convention as the RTL's `stock` output
    uint32_t price;
};

std::vector<uint8_t> encode_add_order(const AddOrderFields& f) {
    std::vector<uint8_t> b(36, 0);
    b[0] = f.msg_type;
    for (int i = 0; i < 6; ++i) b[1 + i] = static_cast<uint8_t>(f.timestamp_ns >> (8 * (5 - i)));
    for (int i = 0; i < 8; ++i) b[7 + i] = static_cast<uint8_t>(f.order_ref >> (8 * (7 - i)));
    b[15] = f.side;
    for (int i = 0; i < 4; ++i) b[16 + i] = static_cast<uint8_t>(f.shares >> (8 * (3 - i)));
    for (int i = 0; i < 8; ++i) b[20 + i] = static_cast<uint8_t>(f.stock_packed >> (8 * (7 - i)));
    for (int i = 0; i < 4; ++i) b[28 + i] = static_cast<uint8_t>(f.price >> (8 * (3 - i)));
    return b;
}

AddOrderFields run_rtl(Vitch_add_order_parser& dut, const std::vector<uint8_t>& bytes) {
    for (uint8_t b : bytes) {
        dut.byte_valid = 1;
        dut.byte_in = b;
        clock_tick(dut);
    }
    dut.byte_valid = 0;
    AddOrderFields out{};
    out.msg_type     = static_cast<uint8_t>(dut.msg_type);
    out.timestamp_ns = dut.timestamp_ns;
    out.order_ref    = dut.order_ref;
    out.side         = static_cast<uint8_t>(dut.side);
    out.shares       = dut.shares;
    out.stock_packed = dut.stock;
    out.price        = dut.price;
    return out;
}

AddOrderFields run_cpp_reference(const std::vector<uint8_t>& bytes) {
    feed::ItchAddOrder parsed{};
    const bool ok = feed::ItchAddOrder::parse(bytes.data(), bytes.size(), parsed);
    AddOrderFields out{};
    if (!ok) { out.msg_type = 0xFF; return out; } // sentinel for "parse failed" -- shouldn't happen with well-formed input
    out.msg_type     = static_cast<uint8_t>(bytes[0]);
    out.timestamp_ns = parsed.timestamp_ns;
    out.order_ref    = parsed.order_ref;
    out.side         = static_cast<uint8_t>(parsed.side);
    out.shares       = parsed.shares;
    out.price        = parsed.price;
    // Pack parsed.stock (char[9], null-terminated after 8 real chars)
    // into the same MSB-first 64-bit convention the RTL uses, for a
    // direct, single-comparison field check rather than a separate
    // string compare path.
    uint64_t packed = 0;
    for (int i = 0; i < 8; ++i) packed = (packed << 8) | static_cast<uint8_t>(parsed.stock[i]);
    out.stock_packed = packed;
    return out;
}

} // namespace

int main() {
    std::mt19937_64 rng(42);
    std::uniform_int_distribution<int> side_dist(0, 1);
    std::uniform_int_distribution<uint32_t> shares_dist(1, 1'000'000);
    std::uniform_int_distribution<uint32_t> price_dist(1, 100'000'000);
    std::uniform_int_distribution<int> letter_dist('A', 'Z');
    std::uniform_int_distribution<uint64_t> ref_dist(1, UINT64_C(0xFFFFFFFFFFFFFF));
    std::uniform_int_distribution<uint64_t> ts_dist(0, UINT64_C(0xFFFFFFFFFFFF)); // 48-bit range

    constexpr int kN = 10'000;
    int mismatches = 0;

    auto dut = std::make_unique<Vitch_add_order_parser>();
    dut->rst_n = 0;
    clock_tick(*dut);
    clock_tick(*dut);
    dut->rst_n = 1;
    clock_tick(*dut);

    // Explicit boundary cases, not left to chance even with 10,000 random
    // samples: all-zero fields, and all-max-value fields at each field's
    // actual bit width (48-bit timestamp, 64-bit order_ref, 32-bit shares
    // and price) -- the values most likely to expose an off-by-one in a
    // field's bit range if one existed.
    const std::vector<AddOrderFields> edge_cases = {
        {'A', 0, 0, 'B', 0, 0, 0},
        {'A', 0xFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 'S', 0xFFFFFFFFU,
         0x4141414141414141ULL /* "AAAAAAAA" */, 0xFFFFFFFFU},
        {'F', 12345, 42, 'B', 1, 0x5A5A5A5A5A5A5A5AULL, 1},
    };
    for (std::size_t i = 0; i < edge_cases.size(); ++i) {
        const auto bytes = encode_add_order(edge_cases[i]);
        const auto rtl_out = run_rtl(*dut, bytes);
        const auto cpp_out = run_cpp_reference(bytes);
        const bool match = (rtl_out.msg_type == cpp_out.msg_type) &&
                            (rtl_out.timestamp_ns == cpp_out.timestamp_ns) &&
                            (rtl_out.order_ref == cpp_out.order_ref) &&
                            (rtl_out.side == cpp_out.side) &&
                            (rtl_out.shares == cpp_out.shares) &&
                            (rtl_out.stock_packed == cpp_out.stock_packed) &&
                            (rtl_out.price == cpp_out.price);
        if (!match) {
            std::fprintf(stderr, "EDGE CASE %zu MISMATCH\n", i);
            ++mismatches;
        }
    }
    std::printf("%zu explicit edge cases checked\n", edge_cases.size());

    for (int iter = 0; iter < kN; ++iter) {
        AddOrderFields f{};
        f.msg_type = 'A';
        f.timestamp_ns = ts_dist(rng);
        f.order_ref = ref_dist(rng);
        f.side = side_dist(rng) ? 'B' : 'S';
        f.shares = shares_dist(rng);
        f.price = price_dist(rng);
        uint64_t stock = 0;
        for (int i = 0; i < 8; ++i) stock = (stock << 8) | static_cast<uint8_t>(letter_dist(rng));
        f.stock_packed = stock;

        const auto bytes = encode_add_order(f);
        const auto rtl_out = run_rtl(*dut, bytes);
        const auto cpp_out = run_cpp_reference(bytes);

        bool match = (rtl_out.msg_type == cpp_out.msg_type) &&
                     (rtl_out.timestamp_ns == cpp_out.timestamp_ns) &&
                     (rtl_out.order_ref == cpp_out.order_ref) &&
                     (rtl_out.side == cpp_out.side) &&
                     (rtl_out.shares == cpp_out.shares) &&
                     (rtl_out.stock_packed == cpp_out.stock_packed) &&
                     (rtl_out.price == cpp_out.price);

        if (!match) {
            ++mismatches;
            if (mismatches <= 5) {
                std::fprintf(stderr,
                    "MISMATCH iter=%d: RTL{type=%02x ts=%lu ref=%lu side=%02x shares=%u stock=%016lx price=%u} "
                    "CPP{type=%02x ts=%lu ref=%lu side=%02x shares=%u stock=%016lx price=%u}\n",
                    iter,
                    rtl_out.msg_type, rtl_out.timestamp_ns, rtl_out.order_ref, rtl_out.side, rtl_out.shares, rtl_out.stock_packed, rtl_out.price,
                    cpp_out.msg_type, cpp_out.timestamp_ns, cpp_out.order_ref, cpp_out.side, cpp_out.shares, cpp_out.stock_packed, cpp_out.price);
            }
        }
    }

    std::printf("%d messages compared, %d mismatches (RTL simulation vs real C++ parser)\n", kN, mismatches);
    return mismatches == 0 ? 0 : 1;
}
