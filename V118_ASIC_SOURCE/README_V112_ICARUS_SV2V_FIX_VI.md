# V1.12 Icarus Verilog `elab_type.cc:86` compatibility fix

## Symptom

```
rtl/config/handseg_config_pkg.sv:43: assert: elab_type.cc:86: failed assertion scope
Aborted (core dumped)
```

This is an Icarus elaboration assertion triggered by the packed struct type `handseg_config_pkg::residual_cfg_t`, before any simulation starts. It is not evidence that the residual engine or SRAM behavior is incorrect.

## Remedy

Reuses the **sv2v v0.0.13** binary already installed in V1.11 at `.tools/sv2v/v0.0.13/sv2v`. The following files are converted together, once per invocation:

- `rtl/config/handseg_config_pkg.sv`
- `rtl/engine/residual_word_engine.sv`
- `tests/tb_v112_residual_memory.sv`

Their converted copy is written to `output/v112_residual/v112_converted.v`, without modifying source. Icarus compiles this copy with the unchanged V1.09 physical feature SRAM RTL, V1.06 reference RAM, and original upstream OpenRAM 2KiB behavioral model. **No `SYNTHESIS` define and no simulation mocks.**

The script leaves existing V1.07–V1.11 checkpoints unchanged. This patch modifies **only** `scripts/run_v112_residual_integration.sh`. Your V1.12 testbench and comparator must already be installed.

## Run

From your WSL project directory:

```bash
python3 -m zipfile -e /mnt/c/Users/tienh/Downloads/AI_ASIC_V112_SV2V_ICARUS_FIX.zip .
bash scripts/run_v112_residual_integration.sh smoke
# Only after smoke PASS:
bash scripts/run_v112_residual_integration.sh stress
```

If anything fails, the script prints the relevant conversion, compile or simulation log. A clean conversion alone is not proof that the test passes. Full-frame functional equivalence and physical signoff remain unverified.
