#!/usr/bin/env bash
# V112 compatibility fix: Icarus can crash on the SystemVerilog package packed
# struct in residual_word_engine's port. Convert only package+engine+testbench
# with the same sv2v already used by the V111 full-AI hierarchy flow.
# Keep the V106/V109 memory source and upstream OpenRAM behavioral model real.
set -euo pipefail
cd "$(dirname "$0")/.."

for command_name in iverilog vvp python3; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "[BLOCKED] Missing executable: $command_name" >&2
        exit 2
    fi
done

model=macros/sky130_2k/sky130_sram_2kbyte_1rw1r_32x512_8.v
if [[ ! -s "$model" ]]; then
    echo '[BLOCKED] Missing actual 2KiB OpenRAM model. Run bash scripts/v107_fetch_macro_views.sh' >&2
    exit 2
fi

mode="${1:-smoke}"
case "$mode" in
    smoke) WORDS=4 ;;
    stress) WORDS=513 ;;
    *) echo 'Usage: bash scripts/run_v112_residual_integration.sh [smoke|stress]' >&2; exit 2 ;;
esac

if [[ -n "${SV2V_BIN:-}" ]]; then
    sv2v_bin="$SV2V_BIN"
elif [[ -x .tools/sv2v/v0.0.13/sv2v ]]; then
    sv2v_bin=.tools/sv2v/v0.0.13/sv2v
elif command -v sv2v >/dev/null 2>&1; then
    sv2v_bin="$(command -v sv2v)"
elif [[ -f scripts/v111_install_sv2v.py ]]; then
    echo '[INFO] Reusing V111 installer for official sv2v binary'
    sv2v_bin="$(python3 scripts/v111_install_sv2v.py)"
else
    echo '[BLOCKED] sv2v unavailable. Install V111 sv2v frontend first, or set SV2V_BIN' >&2
    exit 2
fi
if [[ ! -x "$sv2v_bin" ]]; then
    echo "[BLOCKED] sv2v is not executable: $sv2v_bin" >&2
    exit 2
fi

out=output/v112_residual
mkdir -p "$out"
echo '[INFO] sv2v frontend converts the original HandSeg package, residual engine and testbench'
echo '[INFO] SRAM wrappers, OpenRAM model and original RTL files are not modified'
echo '[START] sv2v compatibility conversion (no SYNTHESIS define, no mocks)'
if ! "$sv2v_bin" \
    rtl/config/handseg_config_pkg.sv \
    rtl/engine/residual_word_engine.sv \
    tests/tb_v112_residual_memory.sv \
    > "$out/v112_converted.tmp.v" 2> "$out/sv2v.log"; then
    echo '[FAIL] sv2v conversion' >&2
    tail -n 70 "$out/sv2v.log" >&2
    rm -f "$out/v112_converted.tmp.v"
    exit 3
fi
if ! grep -Eq '^[[:space:]]*module[[:space:]]+tb_v112_residual_memory\b' "$out/v112_converted.tmp.v"; then
    echo '[FAIL] sv2v output lacks tb_v112_residual_memory' >&2
    exit 3
fi
mv "$out/v112_converted.tmp.v" "$out/v112_converted.v"
echo '[PASS] Converted package/engine/testbench for Icarus Verilog'

for backend in golden hard; do
    defines=()
    if [[ "$backend" == hard ]]; then
        defines=(-DV107_HARD_FEATURE_SRAM -DV109_SINGLE_COPY_SRAM)
    fi
    echo "[START] V112 $backend residual engine + memory, WORDS=$WORDS"
    if ! iverilog -g2012 -s tb_v112_residual_memory -I . "${defines[@]}" \
        -o "$out/${backend}.vvp" \
        sim/v107_openram_model_include.sv \
        rtl/memory/v109_handseg_feature_sram_bank.sv \
        rtl/memory/v109_handseg_feature_memory_macro.sv \
        rtl/memory/reference_feature_memory.sv \
        "$out/v112_converted.v" \
        > "$out/${backend}_compile.log" 2>&1; then
        echo "[FAIL] V112 $backend compilation" >&2
        tail -n 70 "$out/${backend}_compile.log" >&2
        exit 4
    fi
    if ! vvp "$out/${backend}.vvp" "+WORDS=${WORDS}" \
        > "$out/${backend}.log" 2>&1; then
        echo "[FAIL] V112 $backend simulation" >&2
        tail -n 70 "$out/${backend}.log" >&2
        exit 5
    fi
    if ! grep -F "PASS tb_v112_residual_memory WORDS=${WORDS} WRITES=${WORDS}" \
             "$out/${backend}.log"; then
        echo "[FAIL] V112 $backend missing PASS marker" >&2
        tail -n 70 "$out/${backend}.log" >&2
        exit 6
    fi
    grep '^TRACE ' "$out/${backend}.log" > "$out/${backend}.trace"
done

python3 scripts/v112_compare_residual.py \
    "$out/golden.trace" "$out/hard.trace" "$WORDS"
