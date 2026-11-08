from pathlib import Path
import re

p = Path("head_mult.hex")
values = p.read_text().split()

if len(values) != 1:
    raise SystemExit(
        f"STOP: expected 1 scalar multiplier, got {len(values)}"
    )

value = values[0].upper()

if not re.fullmatch(r"[0-9A-F]{8}", value):
    raise SystemExit(f"Invalid 32-bit HEX multiplier: {value}")

# Chỉ đúng khi mô hình dùng multiplier chung cho mọi output channel.
p.write_text((value + "\n") * 256)

result = p.read_text().split()
assert len(result) == 256
assert all(v == value for v in result)

print(f"PASS: wrote {len(result)} multipliers")
print(f"M[0] = {result[0]}")
print(f"M[1] = {result[1]}")
print(f"M[255] = {result[255]}")
