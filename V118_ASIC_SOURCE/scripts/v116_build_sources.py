#!/usr/bin/env python3
"""Prepare near-full ASIC compute RTL without modifying production source files.
Memory exceptions: external frame/feature/qparams via asic_ai_top;
ROM 96-bit and 24x4096 camera FIFO payload replaced by declared EMPTY macro interfaces.
"""
from pathlib import Path
import re, sys, hashlib
root=Path(__file__).resolve().parent.parent
out=root/'output/v116_nearfull'
out.mkdir(parents=True,exist_ok=True)
config=(root/'config/config.mk').read_text()
line=next((s for s in config.splitlines() if 'VERILOG_FILES' in s and s.strip().startswith('export VERILOG_FILES =')),None)
if not line: raise SystemExit('No VERILOG_FILES in config/config.mk')
srcs=[Path(s.removeprefix('/workspace/')) for s in re.findall(r'/workspace/[^\s]+',line)]
for x in srcs:
    if not (root/x).exists(): raise SystemExit('Missing source '+str(x))
# No imported onchip frame memory; asic_ai_top is existing complete compute/control memory-bus boundary.
if Path('asic/asic_ai_top.sv') not in srcs: raise SystemExit('Missing external memory AI top')
if Path('rtl/classifier/classifier_weight_rom96_banked.sv') not in srcs: raise SystemExit('Missing 96b weight ROM')
if Path('rtl/integration/handseg_async_pixel_fifo.sv') not in srcs: raise SystemExit('Missing camera FIFO')
# Replaced ROM DATA is genuinely unknown/undefined from absent memory, not a zero or fake weight.
rom='''// V1.16 ABSTRACT MEMORY ONLY: original ROM payload excluded. No weights are synthesized here.
module classifier_weight_rom96_banked #(
 parameter integer ROM_KIND=0, parameter integer BANK_COUNT=5
)(input wire clk, input wire rd_en, input wire [12:0] rd_addr, output wire [95:0] rd_data);
  v116_MISSING_WEIGHT_ROM u_external_rom (
    .CLK(clk), .EN(rd_en), .ADDR(rd_addr), .KIND(ROM_KIND != 0), .DATA(rd_data));
endmodule
'''
(out/'classifier_weight_rom96_banked.v').write_text(rom)
fifo=(root/'rtl/integration/handseg_async_pixel_fifo.sv').read_text()
a='(* ramstyle = "M10K, no_rw_check" *) logic [WIDTH-1:0] mem [0:DEPTH-1];'
b='''// V1.16: RAM storage is ABSENT; FIFO pointer/control logic is unchanged.
    wire [WIDTH-1:0] v116_payload_out;
    // Top instantiates WIDTH=24, ADDR_BITS=12. Other parameters are not supported in this physical trial.
    v116_MISSING_PIXEL_FIFO_RAM u_external_fifo_ram (
       .WCLK(wr_clk_i), .WEN(wr_valid_i && wr_ready_o),
       .WADDR(wr_bin_r[11:0]), .WDATA(wr_data_i[23:0]),
       .RADDR(rd_bin_r[11:0]), .RDATA(v116_payload_out));'''
if fifo.count(a)!=1:raise SystemExit('FIFO declaration changed; refusing unsafe rewrite')
fifo=fifo.replace(a,b)
start='''    always_ff @(posedge wr_clk_i) begin
        if (wr_valid_i && wr_ready_o)
            mem[wr_bin_r[ADDR_BITS-1:0]] <= wr_data_i;
    end
'''
if fifo.count(start)!=1:raise SystemExit('FIFO write source changed; refusing unsafe rewrite')
fifo=fifo.replace(start,'')
old='rd_data_r <= mem[rd_bin_r[ADDR_BITS-1:0]];'
if fifo.count(old)!=1:raise SystemExit('FIFO read source changed; refusing unsafe rewrite')
fifo=fifo.replace(old,'rd_data_r <= v116_payload_out;')
(out/'handseg_async_pixel_fifo.sv').write_text(fifo)
# RTL blackboxes define the only unimplemented cells, corresponding to marker GDS and LEF/LIB.
sub={Path('rtl/classifier/classifier_weight_rom96_banked.sv'):out/'classifier_weight_rom96_banked.v',
     Path('rtl/integration/handseg_async_pixel_fifo.sv'):out/'handseg_async_pixel_fifo.sv'}
sorted_srcs=sorted(srcs,key=lambda x:(x.name!='handseg_config_pkg.sv',str(x)))
chosen=[str(sub.get(s,root/s)) for s in sorted_srcs]
(out/'v116_sources.txt').write_text('\n'.join(chosen)+'\n')
(out/'v116_source_originals.txt').write_text('\n'.join(map(str,sorted_srcs))+'\n')
print(f'[V116] {len(sorted_srcs)} original source modules; replacing ONLY weight ROM payload and camera FIFO payload')
print('[V116] top=asic_ai_top, external 64-bit frame/feature/HandSeg parameter memory bus')
print('[V116] SRAM CNN (1KiB physical macros) remain enabled')
print('[V116] Do not describe GDS as working or tapeout-ready: absent memory placeholders')
