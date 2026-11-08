#!/usr/bin/env python3
"""Conservative per-bank address extent from the frozen HandSeg schedule.

Checks active static schedule entries, geometry, engine address formulas.
Does NOT prove cycle-accurate correctness or cover arbitrary new schedules.
"""
from pathlib import Path
from collections import defaultdict
import re,csv,json
ROOT=Path(__file__).resolve().parents[1]
def block_dict(text,pattern,stem):
    result={}
    for m in re.finditer(pattern,text):
        body=text[m.end():].split("end",1)[0]
        vals={k:(int(v) if v.isdigit() else v) for k,v in re.findall(
            rf"{stem}\.(\w+)\s*=\s*(?:\d+'[dh])?([a-zA-Z_0-9]+)",body)}
        assert vals, m.group(0)
        result[int(m.group(1))]=vals
    return result
text=lambda f:(ROOT/f).read_text()
sched=block_dict(text('rtl/config/network_schedule_rom.sv'),r"7'd(\d+): begin",'cmd_o')
layer=block_dict(text('rtl/config/layer_descriptor_rom.sv'),r"7'd(\d+): begin",'cfg_o')
concat=block_dict(text('rtl/config/concat_descriptor_rom.sv'),r"2'd(\d+): begin",'cfg_o')
assert len(sched)==82 and len(layer)==65 and len(concat)==3
names=['BANK_A','BANK_B','BANK_TEMP','BANK_SKIP80','BANK_SKIP40','BANK_SKIP20','BANK_AUX','BANK_MASK']
seen=defaultdict(list)
def add(bank,words,pc,kind,role):
    assert bank in names and 0 < words <= 131072, (bank,pc,words)
    seen[bank].append((words,pc,kind,role))
for pc,c in sorted(sched.items()):
    op=c['op']; id_=c['id']
    if op=='CMD_CONV':
        l=layer[id_]
        assert l['hin']*l['win']*l['in_groups8']<=131072
        add(c['src0_bank'],l['hin']*l['win']*l['in_groups8'],pc,f'conv{id_} input','read')
        add(c['dst_bank'],l['hout']*l['wout']*l['out_groups8'],pc,f'conv{id_} output','write')
    elif op=='CMD_RESIDUAL':
        for key,role in [('src0_bank','read0'),('src1_bank','read1'),('dst_bank','write')]:
            add(c[key],c['word_count'],pc,f'residual{id_}',role)
    elif op=='CMD_CONCAT':
        q=concat[id_]
        pixels=q['out_width']*q['out_height']; fg=q['feature_groups']; sg=q['skip_groups']
        assert q['out_width']%2==0 and q['out_height']%2==0
        add(c['src0_bank'],(pixels//4)*fg,pc,f'concat{id_} feature','read')
        add(c['src1_bank'],pixels*sg,pc,f'concat{id_} skip','read')
        add(c['dst_bank'],pixels*(fg+sg),pc,f'concat{id_} output','write')
    elif op=='CMD_GAP':
        eng=text('rtl/engine/presence_gap_engine.sv')
        assert 'localparam integer GROUPS  = 20;' in eng
        assert 'localparam integer SPATIAL = 80;' in eng
        add(c['src0_bank'],20*80,pc,'GAP','read')
        add(c['dst_bank'],20,pc,'GAP','write')
    elif op=='CMD_PRESENCE': add(c['src0_bank'],1,pc,'presence','read')
    elif op=='CMD_ROI':
        assert 'localparam integer W=80,H=64,N=5120;' in text('rtl/engine/mask_roi_engine.sv')
        add(c['src0_bank'],5120,pc,'ROI','read')
    else: assert op=='CMD_DONE', (pc,op)
# Check key engine formulas remain compatible. Refuse reusing audit after RTL changes.
conv=text('rtl/engine/conv_layer_engine.sv')
coneng=text('rtl/engine/concat_upsample_engine.sv')
reseng=text('rtl/engine/residual_word_engine.sv')
for needle in ["out_pixel_base_r <= out_pixel_base_r + {11'd0,cfg_r.out_groups8}",
               "mem_wr_addr_o  = out_pixel_base_r + {11'd0,out_group_r}",
               'pw_input_addr_c = in_y_base_words_r + in_x_base_words_r']:
    assert needle in conv, ('conv engine changed; re-audit',needle)
for needle in ['feature_pixel_index_c = mul9x9_shiftadd((y_r >> 1)',
               'skip_pixel_index_c    = mul9x9_shiftadd(y_r, cfg_r.out_width)',
               "dst_addr_r <= dst_addr_r + 1'b1"]:
    assert needle in coneng, ('concat engine changed; re-audit',needle)
assert 'assign rd0_req_addr_o = index_r;' in reseng
assert 'assign wr_addr_o = index_r;' in reseng
# Stage0 input 320x256*1 group
add('BANK_A',320*256,0,'camera preprocessed input','write')
# Canonical expected observed maxima, fail closed on edited descriptors
EXPECTED=[122880,61440,46080,5120,1280,320,46080,5120]
allocated=[122880,61440,46080,5120,1280,384,46080,5120]
maxima=[]
for k,expected,alloc in zip(names,EXPECTED,allocated):
    worst=max(seen[k]); maximum=worst[0]
    assert maximum==expected,(k,maximum,expected)
    assert alloc>=maximum and alloc%128==0
    maxima.append(maximum)
    print(f'[BANK] {k:<11} required={maximum:>6} words alloc={alloc:>6} words '
          f' ({alloc*8/1024:,.1f} KiB) worst=PC{worst[1]} {worst[2]}')
# Compare with actual RTL bank sizes and scheme
rtl=text('rtl/memory/reference_feature_memory.sv')
for i,n in enumerate(allocated):
    assert re.search(rf'B{i}_WORDS\s*=.*?{n}\s*;',rtl),i
print(f'[OK] descriptor audit: {len(sched)} commands, {len(layer)} layers, '
      f'{len(concat)} concat variants')
print(f'[OK] 8 RAM banks allocated {sum(allocated)*8/1048576:.6f} MiB '
      f'vs reference {8*131072*8/1048576:.1f} MiB')
report=ROOT/'docs/V106_HANDSEG_BANK_CAPACITY.csv'
with report.open('w',newline='') as f:
    writer=csv.writer(f)
    writer.writerow(['bank_id','bank_name','min_words_from_schedule','allocated_words','allocated_kiB','worst_pc','worst_access','source'])
    for i,name in enumerate(names):
        worst=max(seen[name]);writer.writerow([i,name,maxima[i],allocated[i],allocated[i]*8/1024,worst[1],worst[2],worst[3]])
print('[OK] report:',report.relative_to(ROOT))
print('[NOTE] Addresses bounded by static schedule assumptions; dynamic RTL simulation and hard macro mapping still required')
