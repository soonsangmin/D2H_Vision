# ASIC V118 HandSeg / ROI / CNN

Source package from the current V118 OpenROAD project.

Top module: asic_ai_top
Target PDK: SKY130
RTL source files, configuration, synthesis scripts,
macro views and constraints are included where available.

Current engineering status:
- Yosys hierarchical synthesis completed.
- ABC technology mapping completed.
- 1_synth.odb generated using a diagnostic flow.
- OpenDB audit passed.
- Floorplan and physical implementation NOT validated.
- Some SRAM/ROM/FIFO components are NONFUNCTIONAL placeholders.
- NOT tapeout-ready.

Tiny Tapeout compatibility:
This is the original large ASIC source for review and
porting, NOT a directly runnable Tiny Tapeout project.
It requires architecture reduction, a Tiny Tapeout
top-level wrapper, I/O remapping, verification, and
physical-design checks before submission.
