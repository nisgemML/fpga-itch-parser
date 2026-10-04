// tests/test_itch50_rtl.cpp
//
// Differential test of rtl/itch50_parser.v (simulated by Verilator) against an INDEPENDENT oracle:
// tests/data/itch50_oracle.txt, produced by scripts/gen_itch50_oracle.py with the third-party
// `itchfeed` package -- bytes packed with its own struct format strings, every expected field read
// back out of its own parser. Nothing here shares code, or one person's reading of the NASDAQ spec,
// with the RTL under test.
//
// Per message, BOTH directions are checked: every decoded field must equal the oracle's value, and
// every field the message type does not carry must read zero (no leakage from the previous message).
// Three drive modes exercise the framing logic differently: messages isolated by idle cycles,
// back-to-back with no gap at all, and back-to-back with random bubbles in byte_valid.
// Then framing errors: truncated, overlong, one-byte, and undecoded message types, followed by a
// normal message to prove the parser recovers.
//
// Usage: test_itch50_rtl tests/data/itch50_oracle.txt

#include "Vitch50_parser.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <fstream>
#include <map>
#include <memory>
#include <random>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct Obs {
    bool known{false}, len_ok{false};
    uint8_t type{0}, side{0}, printable{0};
    uint16_t locate{0}, tracking{0};
    uint32_t shares{0}, price{0}, attribution{0};
    uint64_t ts{0}, order_ref{0}, new_ref{0}, stock{0}, match{0};
    bool operator==(const Obs& o) const {
        return known == o.known && len_ok == o.len_ok && type == o.type && side == o.side && printable == o.printable &&
               locate == o.locate && tracking == o.tracking && shares == o.shares && price == o.price &&
               attribution == o.attribution && ts == o.ts && order_ref == o.order_ref && new_ref == o.new_ref &&
               stock == o.stock && match == o.match;
    }
};

std::string show(const Obs& o) {
    char b[400];
    std::snprintf(b, sizeof b, "{known=%d len_ok=%d type=%c loc=%u trk=%u ts=%llu ref=%llu new=%llu side=%02x sh=%u stock=%016llx px=%u match=%llu prt=%02x attr=%08x}",
        o.known, o.len_ok, o.type ? o.type : '?', o.locate, o.tracking, (unsigned long long)o.ts, (unsigned long long)o.order_ref,
        (unsigned long long)o.new_ref, o.side, o.shares, (unsigned long long)o.stock, o.price, (unsigned long long)o.match, o.printable, o.attribution);
    return b;
}

void tick(Vitch50_parser& d) { d.clk = 0; d.eval(); d.clk = 1; d.eval(); }

Obs snapshot(const Vitch50_parser& d) {
    Obs o;
    o.known = d.msg_known; o.len_ok = d.len_ok; o.type = d.msg_type; o.locate = d.locate; o.tracking = d.tracking;
    o.ts = d.timestamp_ns; o.order_ref = d.order_ref; o.new_ref = d.new_ref; o.side = d.side; o.shares = d.shares;
    o.stock = d.stock; o.price = d.price; o.match = d.match_number; o.printable = d.printable; o.attribution = d.attribution;
    return o;
}

// Drive one framed message; `idle_p` = probability of an idle (byte_valid=0) cycle before each byte.
// Returns the observation captured on the cycle msg_valid pulses (right after byte_last).
bool feed(Vitch50_parser& d, const std::vector<uint8_t>& m, double idle_p, std::mt19937_64& rng, Obs& out) {
    std::uniform_real_distribution<double> u(0.0, 1.0);
    bool got = false;
    for (std::size_t i = 0; i < m.size(); ++i) {
        while (idle_p > 0 && u(rng) < idle_p) { d.byte_valid = 0; d.byte_in = 0xAA; d.byte_last = 0; tick(d); }
        d.byte_valid = 1; d.byte_in = m[i]; d.byte_last = (i + 1 == m.size());
        tick(d);
        if (d.msg_valid) { out = snapshot(d); got = true; }
    }
    d.byte_valid = 0; d.byte_last = 0;
    return got;
}

std::vector<uint8_t> unhex(const std::string& s) {
    std::vector<uint8_t> v; for (std::size_t i = 0; i + 1 < s.size(); i += 2) v.push_back((uint8_t)std::stoul(s.substr(i, 2), nullptr, 16)); return v;
}
uint64_t hex64(const std::string& s) { return std::stoull(s, nullptr, 16); }

struct Case { std::vector<uint8_t> bytes; Obs expect; std::string line; };

Case parse_line(const std::string& line) {
    std::istringstream ss(line); std::string t, hex; ss >> t >> hex;
    std::map<std::string, std::string> kv; std::string tok;
    while (ss >> tok) { auto eq = tok.find('='); kv[tok.substr(0, eq)] = tok.substr(eq + 1); }
    auto n = [&](const char* k) { return std::stoull(kv.at(k)); };
    Case c; c.bytes = unhex(hex); c.line = line;
    Obs& e = c.expect; e.known = true; e.len_ok = true; e.type = (uint8_t)t[0];
    e.locate = (uint16_t)n("locate"); e.tracking = (uint16_t)n("tracking"); e.ts = n("timestamp");
    switch (t[0]) {
    case 'R': e.stock = hex64(kv.at("stock")); break;
    case 'A': case 'F': e.order_ref = n("order_ref"); e.side = (uint8_t)kv.at("side")[0]; e.shares = (uint32_t)n("shares"); e.stock = hex64(kv.at("stock")); e.price = (uint32_t)n("price");
        if (t[0] == 'F') e.attribution = (uint32_t)hex64(kv.at("attribution")); break;
    case 'E': e.order_ref = n("order_ref"); e.shares = (uint32_t)n("shares"); e.match = n("match"); break;
    case 'C': e.order_ref = n("order_ref"); e.shares = (uint32_t)n("shares"); e.match = n("match"); e.printable = (uint8_t)kv.at("printable")[0]; e.price = (uint32_t)n("price"); break;
    case 'X': e.order_ref = n("order_ref"); e.shares = (uint32_t)n("shares"); break;
    case 'D': e.order_ref = n("order_ref"); break;
    case 'U': e.order_ref = n("order_ref"); e.new_ref = n("new_ref"); e.shares = (uint32_t)n("shares"); e.price = (uint32_t)n("price"); break;
    }
    return c;
}

int g_fail = 0, g_checks = 0;
void expect(bool ok, const std::string& what) { ++g_checks; if (!ok) { ++g_fail; if (g_fail <= 12) std::fprintf(stderr, "FAIL: %s\n", what.c_str()); } }

void reset(Vitch50_parser& d) { d.rst_n = 0; d.byte_valid = 0; d.byte_last = 0; tick(d); tick(d); d.rst_n = 1; tick(d); }

} // namespace

int main(int argc, char** argv) {
    if (argc < 2) { std::fprintf(stderr, "usage: %s tests/data/itch50_oracle.txt\n", argv[0]); return 2; }
    std::ifstream in(argv[1]); if (!in) { std::fprintf(stderr, "cannot open %s\n", argv[1]); return 2; }
    std::vector<Case> cases; std::string line;
    while (std::getline(in, line)) if (!line.empty()) cases.push_back(parse_line(line));
    if (cases.empty()) { std::fprintf(stderr, "no test vectors in %s: refusing to report PASS on nothing\n", argv[1]); return 2; }
    std::map<char, int> per; for (auto& c : cases) ++per[(char)c.expect.type];

    auto dut = std::make_unique<Vitch50_parser>();
    std::mt19937_64 rng(2026);
    reset(*dut);

    // Mode 1: each message isolated by idle cycles.
    for (std::size_t i = 0; i < cases.size(); ++i) {
        Obs got; bool ok = feed(*dut, cases[i].bytes, 0.0, rng, got);
        for (int k = 0; k < 3; ++k) { dut->byte_valid = 0; tick(*dut); }
        expect(ok && got == cases[i].expect, "isolated #" + std::to_string(i) + "\n  line: " + cases[i].line.substr(0, 90) + "\n  got:  " + show(got) + "\n  want: " + show(cases[i].expect));
    }
    // Mode 2: all messages back to back, no idle cycle anywhere. Mode 3: same with random bubbles.
    for (int mode = 2; mode <= 3; ++mode) {
        const double idle_p = (mode == 3) ? 0.35 : 0.0;
        for (std::size_t i = 0; i < cases.size(); ++i) {
            Obs got; bool ok = feed(*dut, cases[i].bytes, idle_p, rng, got);
            expect(ok && got == cases[i].expect, std::string(mode == 2 ? "back-to-back" : "bubbles") + " #" + std::to_string(i) + "\n  got:  " + show(got) + "\n  want: " + show(cases[i].expect));
        }
    }

    // Framing errors and recovery. Use the first 'A' and 'D' vectors from the oracle.
    const Case* a = nullptr; const Case* dcase = nullptr;
    for (auto& c : cases) { if (!a && c.expect.type == 'A') a = &c; if (!dcase && c.expect.type == 'D') dcase = &c; }
    if (a && dcase) {
    {   // truncated: 35 of 36 bytes -> known type, wrong length
        std::vector<uint8_t> m(a->bytes.begin(), a->bytes.end() - 1); Obs g; bool ok = feed(*dut, m, 0, rng, g);
        expect(ok && g.known && !g.len_ok && g.type == 'A', "truncated Add Order must report len_ok=0, known=1: " + show(g));
    }
    {   // overlong: 37 bytes
        std::vector<uint8_t> m = a->bytes; m.push_back(0x00); Obs g; bool ok = feed(*dut, m, 0, rng, g);
        expect(ok && g.known && !g.len_ok, "overlong Add Order must report len_ok=0: " + show(g));
    }
    {   // one-byte message ('D' alone): last byte on index 0
        std::vector<uint8_t> m = {'D'}; Obs g; bool ok = feed(*dut, m, 0, rng, g);
        expect(ok && g.known && !g.len_ok && g.type == 'D', "1-byte 'D' must be known with len_ok=0: " + show(g));
    }
    {   // undecoded types: System Event 'S' (12 bytes) and Trade 'P' (44 bytes)
        std::vector<uint8_t> s(12, 0); s[0] = 'S'; Obs g; bool ok = feed(*dut, s, 0, rng, g);
        expect(ok && !g.known && g.type == 'S', "System Event must be msg_known=0: " + show(g));
        std::vector<uint8_t> p(44, 0); p[0] = 'P'; ok = feed(*dut, p, 0, rng, g);
        expect(ok && !g.known && g.type == 'P', "Trade must be msg_known=0: " + show(g));
    }
    {   // recovery: after all of the above, a normal message still decodes exactly
        Obs g; bool ok = feed(*dut, dcase->bytes, 0, rng, g);
        expect(ok && g == dcase->expect, "parser must recover after framing errors: " + show(g));
    }
    } else { std::fprintf(stderr, "note: sample has no 'A' and 'D' message; framing-error cases skipped\n"); }

    std::printf("%zu oracle messages (R=%d A=%d F=%d E=%d C=%d X=%d D=%d U=%d) x 3 drive modes, + 6 framing cases: %d checks, %d failures\n",
                cases.size(), per['R'], per['A'], per['F'], per['E'], per['C'], per['X'], per['D'], per['U'], g_checks, g_fail);
    if (g_fail == 0) { std::printf("PASS: RTL matches the independent third-party oracle on every field, including unused-field zeroing\n"); return 0; }
    return 1;
}
