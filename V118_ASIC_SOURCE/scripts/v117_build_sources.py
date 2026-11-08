#!/usr/bin/env python3
"""V117 near-full compute: remove only large SRAM payloads from synthesis.
Retain all original arithmetic/control logic and all other V116 source modules.
This is NONFUNCTIONAL without actual memory, not a working ASIC.
"""
from pathlib import Path
import subprocess, re, shutil, sys
root=Path(__file__).resolve().parent.parent
out=root/'output/v117_nearfull';out.mkdir(parents=True,exist_ok=True)
subprocess.run([sys.executable,str(root/'scripts/v116_build_sources.py')],check=True,cwd=root)
source_list=[Path(x) for x in (root/'output/v116_nearfull/v116_sources.txt').read_text().splitlines() if x.strip()]

res_p=root/'rtl/classifier/top_residual_vector_store_row4_streaming.v'
s=res_p.read_text()
pattern=r'\(\* ramstyle = "M10K" \*\)\s*reg \[PIXEL_BITS-1:0\] mem \[0:MEM_DEPTH-1\];'
if len(re.findall(pattern,s))!=1:raise SystemExit('Refusing residual SRAM rewrite: declaration changed')
s=re.sub(pattern,'// V117 storage payload missing; original control and packed-vector arithmetic retained.\n    wire [PIXEL_BITS-1:0] v117_ram_output;',s)
start=s.find('    // Dedicated synchronous memory access process:')
end=s.find('    // Preserve the external',start)
if start<0 or end<0:raise SystemExit('Refusing residual RAM rewrite: access block not found')
orig=s[start:end]
if 'mem[wr_mem_addr]' not in orig or 'mem[rd_mem_addr]' not in orig:raise SystemExit('Refusing residual rewrite: source access mismatch')
lines=['    // NONFUNCTIONAL physical boundary for residual store; all original FSMs retained.', '    generate']
for bits in [192,256,512,1024]:
 lines+= [f'      if (PIXEL_BITS == {bits}) begin : g_v117_absent_{bits}',
          f'        v117_MISSING_VECTOR_RAM{bits} u_missing_store(',
          '          .CLK(clk), .WE(wr_mem_we), .WADDR(wr_mem_addr),',
          '          .WDATA(wr_mem_data), .RADDR(rd_mem_addr), .RDATA(v117_ram_output));',
          '      end else']
lines += ['      begin : g_v117_unsupported_residual_width',
          '         // Unsupported widths must be treated as a configuration error.',
          '         initial $error("V117 unsupported residual vector width");',
          '         assign v117_ram_output = {PIXEL_BITS{1\'bx}};',
          '      end', '    endgenerate',
          '    always @(posedge clk) if (rst_n && rd_mem_re) rd_data_reg <= v117_ram_output;', '']
s=s[:start]+'\n'.join(lines)+'\n'+s[end:]
if re.search(r'\bmem\s*\[',s):raise SystemExit('Residual RAM accesses remain')
res_out=out/'top_residual_vector_store_row4_streaming.v';res_out.write_text(s)

row_p=root/'rtl/classifier/stream_row_buffer_3x3_parallel_hwc_stage2.v'
s=row_p.read_text()
parts=re.split(r'(?=^module\s+stream_row_buffer_3x3_parallel_hwc_stage2_banks[34]\b)',s, flags=re.M)
if len(parts)!=3:raise SystemExit(f'Row buffer unexpected module segmentation: {len(parts)}')
for part_i,rows in [(1,3),(2,4)]:
 t=parts[part_i]
 names=[f'm{r}{c}' for r in range(rows) for c in range(3)]
 for name in names:
  regex=r'\(\*\s*ramstyle\s*=\s*"M10K, no_rw_check"\s*\*\)\s*reg\s*\[7:0\]\s*'+name+r'\s*\[0:DEPTH-1\]\s*;'
  if len(re.findall(regex,t))!=1:raise SystemExit(f'Row buffer declaration mismatch {rows} {name}')
  t=re.sub(regex, f'wire [7:0] v117_read_{name}; // storage payload absent',t)
 # Find dedicated write+read block (but retain other always blocks)
 match=re.search(r'\balways\s*@\s*\(posedge\s+clk\)\s*begin',t)
 if not match:raise SystemExit(f'Row buffer {rows} access process absent')
 st=match.start();end_start=match.end()
 tokens=re.finditer(r'\b(begin|end)\b',t[end_start:])
 nesting=1;stop=None
 for tok in tokens:
  nesting+=1 if tok.group(1)=='begin' else -1
  if nesting==0:
   stop=end_start+tok.end();break
 if stop is None:raise SystemExit('Row buffer balanced always not found')
 orig=t[st:stop]
 if not all(f'{name}[wr_addr]' in orig and f'{name}[addr' in orig for name in names):
  raise SystemExit(f'Row buffer {rows} write/read incomplete')
 logic=['    // V117: SRAM payloads abstracted; original address, slot and 3x3 output logic retained.',
        '    wire v117_write = rst_n && wr_valid && wr_ready &&',
        '                      (wr_row < HEIGHT) && (wr_col < WIDTH) && (wr_channel < CHANNELS);']
 for r in range(rows):
  for c in range(3):
   name=f'm{r}{c}'
   logic.extend([f'    v117_MISSING_ROW_RAM u_v117_{name} (',
       f'      .CLK(clk), .WE(v117_write && (slot_of(wr_row) == {r}) && (wr_col_mod3 == {c})),',
       f'      .WADDR(wr_addr), .WDATA(wr_data), .RADDR(addr{c}), .RDATA(v117_read_{name}));'])
 logic+= ['    always @(posedge clk) begin','      if (rst_n && rd_valid) begin']
 for r in range(rows):
  for c in range(3):
   name=f'm{r}{c}'
   logic += [f'        q{r}{c} <= v117_read_{name};']
 logic+=['      end','    end']
 t=t[:st]+'\n'.join(logic)+t[stop:]
 for name in names:
  if re.search(r'\b'+name+r'\s*\[',t):raise SystemExit('Row buffer memory access survived '+name)
 parts[part_i]=t
s=''.join(parts)
row_out=out/'stream_row_buffer_3x3_parallel_hwc_stage2.v';row_out.write_text(s)

source_map={res_p:res_out, row_p:row_out}
new_sources=[str(source_map.get(x,x)) for x in source_list]
if len(new_sources)!=61:raise SystemExit('V117 expected 61 source files')
(out/'v117_sources.txt').write_text('\n'.join(new_sources)+'\n')
(out/'STORAGE_ABSTRACTIONS.txt').write_text('NONFUNCTIONAL MEMORY ONLY: banked CNN row 3x3 RAM payloads (9+12 array definitions), residual vectors (192/256/512/1024 bits), inherited V116 CNN weight ROM and 24-bit pixel FIFO. All remaining memory and all computation follows original source; not a working ASIC.\n')
print('[V117] source rewrite PASS: 61 files, original HandSeg/ROI/CNN arithmetic + controls retained')
print('[V117] abstracted: CNN row RAM payload 3/4-bank, residual vector RAM, V116 CNN weight ROM & pixel FIFO')
print('[LIMIT] Missing memory is NONFUNCTIONAL; not suitable for fabrication/inference')
