#!/usr/bin/env python3
"""Create explicitly NONFUNCTIONAL placeholder views (pin shapes, but no memory).
These views allow compute logic to be physically routed without storage implementation.
"""
from pathlib import Path
import struct, math
R=Path(__file__).resolve().parent.parent/'macros/v116_absent'
R.mkdir(parents=True,exist_ok=True)
macros={
'v116_MISSING_WEIGHT_ROM':{'size':(160.0,180.0),'input':['CLK','EN','KIND']+[f'ADDR[{i}]' for i in range(13)],'output':[f'DATA[{i}]' for i in range(96)]},
'v116_MISSING_PIXEL_FIFO_RAM':{'size':(100.0,110.0),'input':['WCLK','WEN']+[f'WADDR[{i}]' for i in range(12)]+[f'WDATA[{i}]' for i in range(24)]+[f'RADDR[{i}]' for i in range(12)],'output':[f'RDATA[{i}]' for i in range(24)]}}

def rect(n,width,height,direction,idx,total):
    # 1um met3 pin rectangles separated by >=0.25um.
    dy=(height-10)/max(total,1)
    cy=5+(idx+.5)*dy
    if direction=='INPUT': return (1.6, cy-.4,2.6,cy+.4)
    return (width-2.6,cy-.4,width-1.6,cy+.4)

all_lef=['VERSION 5.8 ;','BUSBITCHARS "[]" ;','DIVIDERCHAR "/" ;']
all_lib=['library (v116_memory_absent) {',' delay_model : table_lookup;',' time_unit : "1ns";',' voltage_unit : "1V";',' current_unit : "1mA";',' capacitive_load_unit (1, pf);',' leakage_power_unit : "1nW";',' default_max_transition : 100;']
# Liberty vector pins MUST be represented using a bus() with a corresponding
# type(), not pin("RDATA[0]") ... pin("RDATA[23]"). Otherwise Yosys
# read_liberty creates scalar literal pin names and cannot match RTL .RDATA.
for width in (12, 13, 24, 96):
    all_lib += [f' type (v116_bus{width}) {{',
                '  base_type : array;', '  data_type : bit;',
                f'  bit_width : {width};', f'  bit_from : {width-1};',
                '  bit_to : 0;', ' }']
pins_by_macro={}
for name,c in macros.items():
    w,h=c['size']; all_lef+= [f'MACRO {name}',f'  CLASS BLOCK ;','  ORIGIN 0 0 ;',f'  FOREIGN {name} 0 0 ;',f'  SIZE {w:g} BY {h:g} ;','  SYMMETRY X Y ;']
    all_lib += [f' cell ({name}) {{',f'   area : {w*h:.2f};','   is_macro_cell : true;','   pg_pin (vccd1) { voltage_name : "VDD"; pg_type : primary_power; }','   pg_pin (vssd1) { voltage_name : "VSS"; pg_type : primary_ground; }']
    pinboxes=[]
    for d in ['input','output']:
        names=c[d]
        for i,p in enumerate(names):
            x1,y1,x2,y2=rect(name,w,h,d.upper(),i,len(names))
            all_lef += [f'  PIN {p}',f'   DIRECTION {d.upper()} ;','   USE SIGNAL ;','   PORT','    LAYER met3 ;',f'    RECT {x1:.4f} {y1:.4f} {x2:.4f} {y2:.4f} ;','   END',f'  END {p}']
            pinboxes.append((p,70,20,(x1,y1,x2,y2)))
        # Aggregate Verilog vector ports into real Liberty bus() groups.
        buses = {}
        scalars = []
        for p in names:
            m = __import__('re').fullmatch(r'([A-Za-z_][A-Za-z_0-9]*)\[(\d+)\]', p)
            if m:
                buses.setdefault(m.group(1), []).append(int(m.group(2)))
            else:
                scalars.append(p)
        for p in scalars:
            all_lib.append(f'   pin ({p}) {{ direction : {d};'+
                           (' capacitance : 0.002;' if d == 'input' else ' max_capacitance : 0.3;')+' }')
        for p,indices in buses.items():
            n=len(indices)
            if sorted(indices) != list(range(n)) or n not in (12,13,24,96):
                raise RuntimeError(f'Invalid Liberty bus declaration {name}.{p} indices={indices}')
            all_lib += [f'   bus ({p}) {{', f'     bus_type : v116_bus{n};',
                        f'     direction : {d};',
                        ('     capacitance : 0.002;' if d == 'input' else '     max_capacitance : 0.3;'),
                        f'     pin ({p}[{n-1}:0]) {{ }}', '   }']
    for p,d,x1,x2 in [('vccd1','POWER',3.,4.),('vssd1','GROUND',w-4.,w-3.)]:
        all_lef += [f'  PIN {p}','   DIRECTION INOUT ;',f'   USE {d} ;','   PORT','    LAYER met4 ;',f'    RECT {x1:g} 2 {x2:g} {h-2:g} ;','   END',f'  END {p}']
        pinboxes.append((p,71,20,(x1,2,x2,h-2)))
    all_lef += [f'END {name}']
    all_lib += [' }']
    pins_by_macro[name]=pinboxes
all_lef.append('END LIBRARY')
all_lib.append('}')
(R/'v116_memory_absent.lef').write_text('\n'.join(all_lef)+'\n')
(R/'v116_memory_absent.lib').write_text('\n'.join(all_lib)+'\n')
# Minimal valid GDSII: for each placeholder, pin metal polygons ONLY. No storage transistors or circuits.
def rec(t,d=b''):
    if len(d)%2:d+=b'\x00'
    return struct.pack('>HBB',len(d)+4,t>>8,t&255)+d

def ascii_rec(t,s):return rec(t,s.encode())
def int2(t,n):return rec(t,struct.pack('>h',n))
def int4arr(t,values):return rec(t, b''.join(struct.pack('>i',v) for v in values))
def real8(v):
    if v==0:return b'\x00'*8
    ex=math.ceil(math.log(v,16)); mant=v/(16**ex)
    while mant<1/16: ex-=1;mant*=16
    while mant>=1: ex+=1; mant/=16
    m=int(mant*(1<<56));return bytes([0x40+ex])+m.to_bytes(7,'big')
now=[126,11,6,19,0,0]*2
buf=rec(0x0002,struct.pack('>h',600))+rec(0x0102,struct.pack('>12h',*now))+ascii_rec(0x0206,'V116_ABSENT_MEM')+rec(0x0305,real8(0.001)+real8(1.e-9))
for name,pinboxes in pins_by_macro.items():
    buf+=rec(0x0502,struct.pack('>12h',*now))+ascii_rec(0x0606,name)
    for p,layer,dtype,(x1,y1,x2,y2) in pinboxes:
        xy=[(int(round(x*1000)),int(round(y*1000))) for x,y in [(x1,y1),(x2,y1),(x2,y2),(x1,y2),(x1,y1)]]
        buf+=rec(0x0800)+int2(0x0D02,layer)+int2(0x0E02,dtype)+int4arr(0x1003,[v for pair in xy for v in pair])+rec(0x1100)
    buf+=rec(0x0700)
buf+=rec(0x0400)
(R/'v116_memory_absent.gds').write_bytes(buf)
(R/'NOTICE_NONFUNCTIONAL.txt').write_text('NO MEMORY STORAGE. LEF/LIB/GDS are geometry/timing placeholders only. GDS must never be submitted to a foundry. Use them exclusively for physical trials of non-memory compute/control logic.\n')
print('[V116] generated 2 NONFUNCTIONAL memory placeholder LEF/LIB/GDS cells')

# Quick cross-view sanity check. This is NOT physical or functional signoff.
lib=(R/'v116_memory_absent.lib').read_text()
for port in ('ADDR','DATA','WADDR','WDATA','RADDR','RDATA'):
    assert f'bus ({port})' in lib, f'Missing Liberty bus: {port}'
for port in ('RDATA','WDATA','DATA'):
    assert f'pin ("{port}[0]")' not in lib, f'Scalarized Liberty port: {port}'
print('[PASS] V116 missing-memory Liberty pins use true vector bus() declarations')
