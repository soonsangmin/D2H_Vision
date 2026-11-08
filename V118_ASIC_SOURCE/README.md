# AI ASIC V1.04 — SKY130 SRAM Banking (Engineering Work-in-Progress)

Builds on actual V1.03 full detector+classifier RTL. Adds a selectable physical-macro adapter for the **six CNN completed-row FIFOs** using **52 x 1 KiB** 32x256 OpenRAM-style SRAM instances. Preserves the full-depth RTL fallback. No AI arithmetic was changed.

**NOT GDS-READY**: physical macro LEF/Liberty/GDS are NOT included; other RAM/ROMs are unresolved; external memory pins are transaction-level, not a JEDEC PHY. Never use memory-shrunk screening netlists for tapeout.

Read `README_V104_VI.md` for detailed implementation, tests, area warning and WSL commands.

Quick checks:

```bash
python3 scripts/verify_v104_static.py
bash scripts/run_v104_unit_tests.sh  # Requires Icarus Verilog; compares against V1.02 FIFO
python3 scripts/check_macro_views.py  # Intentionally BLOCKS unless real views exist
```
