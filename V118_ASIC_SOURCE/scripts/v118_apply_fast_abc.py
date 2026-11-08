#!/usr/bin/env python3
"""Apply V1.18 ABC-flow speed patch to V1.17 runner (no RTL changes).

Safe to run repeatedly. Existing sources and synthesis checkpoints are retained.
"""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parent.parent
cfg = root / 'config/config_v117_nearfull_compute.mk'
runner = root / 'scripts/run_v117_nearfull_gds.sh'
abc = root / 'config/v118_abc_quick.script'
assert abc.exists(), 'Missing v118 ABC script'
assert 'strash\nmap' in abc.read_text()
for p in (cfg, runner):
    assert p.is_file(), f'Missing {p}'
    backup = p.with_name(p.name + '.pre_v118')
    if not backup.exists():
        shutil.copy2(p, backup)

s = cfg.read_text()
if 'export ABC_SCRIPT :=' in s:
    import re
    s = re.sub(r'(?m)^export ABC_SCRIPT\s*:=.*$',
               'export ABC_SCRIPT := /workspace/config/v118_abc_quick.script', s)
else:
    s = s.rstrip() + '\nexport ABC_SCRIPT := /workspace/config/v118_abc_quick.script\n'
if 'export ADDER_MAP_FILE :=' not in s:
    s = s.rstrip() + '\nexport ADDER_MAP_FILE :=\n'
# The user has an experimental fast ABC script; never claim timing signoff.
cfg.write_text(s)

s = runner.read_text()
old = 'timeout -s TERM -k 30s 1200s docker run'
new = 'timeout -s TERM -k 90s "$limit_sec" docker run'
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit('Unexpected timeout command in V117 runner; refusing to patch')
old2 = ' local logfile="$out/$stage.log"\n echo "[V117] START $stage ; log=$logfile"'
new2 = (' local logfile="$out/$stage.log"\n'
        ' local limit_sec=2400\n'
        ' case "$stage" in floorplan) limit_sec=900;; finish) limit_sec=1800;; esac\n'
        ' echo "[V118] START $stage (limit=${limit_sec}s, quick ABC); log=$logfile"')
if old2 in s:
    s = s.replace(old2, new2, 1)
elif new2 not in s:
    raise SystemExit('Unexpected runner stage function; refusing to patch')
runner.write_text(s)

assert s.count(new) == 1
assert s.count('local limit_sec=2400') == 1
assert cfg.read_text().count('export ABC_SCRIPT :=') == 1
print('[OK] V118 ABC quick mapping enabled (strash; map)')
print('[OK] V117 runner timeout: synth 2400s, floorplan 900s, finish 1800s')
print('[OK] No RTL/memory/GDS files modified')
print('[NOTE] GDS remains NONFUNCTIONAL with absent memory; no DRC/LVS/STA')
