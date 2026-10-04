#!/usr/bin/env python3
"""Sample a REAL NASDAQ TotalView-ITCH 5.0 file into oracle-format vectors for tests/test_itch50_rtl.

For every Kth supported message (R A F E C X D U) of the file -- framed [2-byte length][message], .gz ok --
this writes '<type> <hex bytes> k=v ...' where the hex is the message exactly as NASDAQ sent it and every
k=v is read out of the THIRD-PARTY `itchfeed` parser. Feed the result to the RTL test:

  python3 scripts/real_to_oracle.py ~/itch/20191230.BX_ITCH_50.gz 100 200000 > /tmp/real_oracle.txt
  ./build/rtl/test_itch50_rtl /tmp/real_oracle.txt

so the RTL is checked on real exchange bytes against an implementation that shares nothing with it.
usage: real_to_oracle.py FILE [EVERY_KTH=100] [MAX_LINES=200000]
"""
import gzip, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_itch50_oracle import oracle_line

SPEC_LEN = {b'R': 39, b'A': 36, b'F': 40, b'E': 31, b'C': 36, b'X': 23, b'D': 19, b'U': 35}

def main():
    path = sys.argv[1]; every = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else 200000
    opener = gzip.open if path.endswith('.gz') else open
    seen = out = bad = 0; per = {}
    with opener(path, 'rb') as f:
        while out < limit:
            lb = f.read(2)
            if len(lb) < 2: break
            n = struct.unpack('>H', lb)[0]; body = f.read(n)
            if len(body) < n: break
            t = body[:1]
            if t not in SPEC_LEN: continue
            if len(body) != SPEC_LEN[t]: bad += 1; continue      # reported, not silently skipped
            seen += 1
            if seen % every: continue
            print(oracle_line(t, body)); out += 1; per[t.decode()] = per.get(t.decode(), 0) + 1
    print(f"# sampled {out} of {seen} supported messages (every {every}th), by type {per}; "
          f"{bad} supported-type messages with a length that is not the spec's", file=sys.stderr)

if __name__ == "__main__":
    main()
