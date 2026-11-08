#!/usr/bin/env python3
"""Compare observed residual-engine transactions from two real memory backends."""
import pathlib
import re
import sys


def parse(path: str):
    lines = pathlib.Path(path).read_text().splitlines()
    out = []
    for line in lines:
        m = re.fullmatch(r"TRACE word=(\d+) data=([0-9a-fA-F]{16})", line)
        if m is None:
            raise SystemExit(f"[FAIL] Unrecognized trace record: {line}")
        out.append((int(m.group(1)), int(m.group(2), 16)))
    return out


def oracle(idx: int):
    result = 0
    for lane in range(8):
        a = (idx + lane * 13 + 1) % 256
        b = (idx * 3 + lane * 7 + 2) % 256
        result |= min(a + b, 255) << (8 * lane)
    return result


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: v112_compare_residual.py gold.trace hard.trace WORDS")
    gold, hard = parse(sys.argv[1]), parse(sys.argv[2])
    n = int(sys.argv[3])
    if len(gold) != n or len(hard) != n:
        raise SystemExit(f"[FAIL] trace length gold={len(gold)} hard={len(hard)} expected={n}")
    for j in range(n):
        expected = (j, oracle(j))
        if gold[j] != expected:
            raise SystemExit(f"[FAIL] V106 reference engine output word={j}: {gold[j]} != {expected}")
        if hard[j] != expected:
            raise SystemExit(f"[FAIL] V109 physical SRAM engine output word={j}: {hard[j]} != {expected}")
    if gold != hard:
        raise SystemExit("[FAIL] V106/V109 trace mismatch")
    print(f"[PASS] V112 residual engine integrated with V109 hard-SRAM and V106 reference: {n} writes + independent saturation oracle + readback")
    print("[LIMIT] Residual engine only; reduced 1024-word x 8-bank test; NOT full-frame HandSeg/CNN equivalence, PnR or signoff")


if __name__ == '__main__':
    main()
