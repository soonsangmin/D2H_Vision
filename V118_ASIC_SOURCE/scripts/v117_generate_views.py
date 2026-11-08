#!/usr/bin/env python3
"""Generate NONFUNCTIONAL physical interface cells for excluded SRAM payloads.
Never send these GDS views to fabrication: pin shapes only, NO memory circuit.
"""
from pathlib import Path
import math, re, struct
R=Path(__file__).resolve().parent.parent/'macros/v117_absent'
R.mkdir(parents=True,exist_ok=True)
macros={'v117_MISSING_ROW_RAM':(8,16)}
macros.update({f'v117_MISSING_VECTOR_RAM{n}':(n,10) for n in (192,256,512,1024)})
lef=['VERSION 5.8 ;','BUSBITCHARS "[]" ;','DIVIDERCHAR "/" ;']
lib=['library (v117_memory_absent) {',' delay_model : "table_lookup";',' time_unit : "1ns";',' voltage_unit : "1V";',' current_unit : "1mA";',' capacitive_load_unit (1, pf);',' leakage_power_unit : "1nW";',' default_max_transition : 100;']
for n in sorted(set([8,10,16,192,256,512,1024])):
 lib+= [f' type (v117_bus{n}) {{','  base_type : array;', '  data_type : bit;',f'  bit_width : {n};',f'  bit_from : {n-1};','  bit_to : 0;', ' }']
pins_all={}
for name,(bits,abits) in macros.items():
 inputs=['CLK','WE']+[f'WADDR[{i}]' for i in range(abits)]+[f'WDATA[{i}]' for i in range(bits)]+[f'RADDR[{i}]' for i in range(abits)]
 outputs=[f'RDATA[{i}]' for i in range(bits)]
 h=max(120,10+1.2*len(inputs),10+1.2*len(outputs));w=200
 lef += [f'MACRO {name}',' CLASS BLOCK ;',' ORIGIN 0 0 ;',f' FOREIGN {name} 0 0 ;',f' SIZE {w:g} BY {h:.3f} ;',' SYMMETRY X Y ;']
 lib += [f' cell ({name}) {{',f'   area : {w*h:.2f};','   is_macro_cell : true;', '   pg_pin (vccd1) { voltage_name : "VDD"; pg_type : primary_power; }', '   pg_pin (vssd1) { voltage_name : "VSS"; pg_type : primary_ground; }']
 all_pins=[]
 for direction,names in [('input',inputs),('output',outputs)]:
  for i,p in enumerate(names):
   yy=5+(i+.5)*1.2
   x1,x2=(1.6,2.6) if direction=='input' else (w-2.6,w-1.6)
   xy=(x1,yy-.4,x2,yy+.4)
   lef += [f' PIN {p}',f'  DIRECTION {direction.upper()} ;','  USE SIGNAL ;','  PORT','   LAYER met3 ;',f'   RECT {xy[0]:.4f} {xy[1]:.4f} {xy[2]:.4f} {xy[3]:.4f} ;','  END',f' END {p}']
   all_pins.append((p,70,20,xy))
  groups={};scalars=[]
  for p in names:
   m=re.fullmatch(r'([A-Za-z_][A-Za-z_0-9]*)\[(\d+)\]',p)
   if m:groups.setdefault(m.group(1),[]).append(int(m.group(2)))
   else:scalars.append(p)
  for p in scalars:
   lib.append(f'   pin ({p}) {{ direction : {direction};'+ (' capacitance : 0.002;' if direction=='input' else ' max_capacitance : 0.3;') + ' }')
  for port,ids in groups.items():
   n=len(ids)
   if sorted(ids)!=list(range(n)):raise RuntimeError('Non-contiguous bus '+port)
   lib += [f'   bus ({port}) {{',f'     bus_type : v117_bus{n};',f'     direction : {direction};',('     capacitance : 0.002;' if direction=='input' else '     max_capacitance : 0.3;'),f'     pin ({port}[{n-1}:0]) {{ }}','   }']
 for pin,typ,x1,x2 in [('vccd1','POWER',3,4),('vssd1','GROUND',w-4,w-3)]:
  xy=(x1,2,x2,h-2)
  lef += [f' PIN {pin}','  DIRECTION INOUT ;',f'  USE {typ} ;','  PORT','   LAYER met4 ;',f'   RECT {x1:g} 2 {x2:g} {h-2:.3f} ;','  END',f' END {pin}']
  all_pins.append((pin,71,20,xy))
 lef.append(f'END {name}')
 lib.append(' }')
 pins_all[name]=all_pins
lef.append('END LIBRARY');lib.append('}')
(R/'v117_memory_absent.lef').write_text('\n'.join(lef)+'\n')
(R/'v117_memory_absent.lib').write_text('\n'.join(lib)+'\n')
# GDSII boundary/met3 and met4 drawings only. There are no SRAM storage bits.
def rec(t,d=b''):
 if len(d)%2:d+=b'\x00'
 return struct.pack('>HBB',len(d)+4,t>>8,t&255)+d
def asc(t,s):return rec(t,s.encode('ascii'))
def i2(t,n):return rec(t,struct.pack('>h',n))
def i4(t,v):return rec(t,b''.join(struct.pack('>i',n) for n in v))
def real8(x):
 if not x:return b'\x00'*8
 exponent=math.ceil(math.log(x,16));mant=x/(16**exponent)
 while mant<1/16:exponent-=1;mant*=16
 while mant>=1:exponent+=1;mant/=16
 return bytes([0x40+exponent])+int(mant*(1<<56)).to_bytes(7,'big')
ts=[126,11,6,20,0,0]*2
buf=rec(0x0002,struct.pack('>h',600))+rec(0x0102,struct.pack('>12h',*ts))+asc(0x0206,'V117_ABSENT_MEM')+rec(0x0305,real8(0.001)+real8(1e-9))
for name,pins in pins_all.items():
 buf+=rec(0x0502,struct.pack('>12h',*ts))+asc(0x0606,name)
 for p,layer,dtype,(x1,y1,x2,y2) in pins:
  xy=[(int(round(x*1000)),int(round(y*1000))) for x,y in [(x1,y1),(x2,y1),(x2,y2),(x1,y2),(x1,y1)]]
  buf+=rec(0x0800)+i2(0x0D02,layer)+i2(0x0E02,dtype)+i4(0x1003,[v for a in xy for v in a])+rec(0x1100)
 buf+=rec(0x0700)
buf+=rec(0x0400)
(R/'v117_memory_absent.gds').write_bytes(buf)
(R/'NOTICE_NONFUNCTIONAL.txt').write_text('V117 CELL IS A NONFUNCTIONAL PIN/GEOMETRY PLACEHOLDER ONLY. NO SRAM ARRAY OR TRANSISTORS. DO NOT FABRICATE OR CLAIM FUNCTIONAL INFERENCE.\n')
print(f'[V117] generated {len(macros)} NONFUNCTIONAL SRAM physical boundary cells; actual storage is absent')
for typ in ('WADDR','WDATA','RADDR','RDATA'):
 if f'bus ({typ})' not in (R/'v117_memory_absent.lib').read_text():raise RuntimeError('Missing liberty bus '+typ)
