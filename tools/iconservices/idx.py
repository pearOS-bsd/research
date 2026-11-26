import struct,sys,uuid
d=open(sys.argv[1],'rb').read()
ver,flag,count,cap,unalloc=struct.unpack_from('<IIIII',d,0)
print('version',hex(ver),'flag',flag,'count',count,'capacity',cap,'unalloc',unalloc,'size',len(d))
tab=0x14; nodes=tab+cap*8
print('nodes base',hex(nodes), 'expected end',hex(nodes+unalloc))
def U(b): return str(uuid.UUID(bytes=bytes(b))).upper()
n=0; off=0; rows=[]
while off<unalloc:
    p=nodes+off
    selfoff,selfsz=struct.unpack_from('<II',d,p)
    key=d[p+8:p+24]; nxt,nsz=struct.unpack_from('<II',d,p+0x18); valid=d[p+0x20]
    pl=d[p+0x24:p+0x24+116]
    u0=pl[0:16]; w,h,sc=struct.unpack_from('<ddd',pl,16); x3=struct.unpack_from('<I',pl,40)[0]
    x4=pl[44:60]; x5=pl[60:76]; t0=pl[76:92]; t1=struct.unpack_from('<Q',pl,92)[0]; t2=pl[100:116]
    rows.append((off,selfoff,selfsz,U(key),nxt,nsz,valid,U(u0),w,h,sc,x3,U(x4),U(x5),U(t0),t1,U(t2)))
    off+=selfsz if selfsz else 152
print(len(rows))
import collections
for r in rows[:3]+rows[-3:]: print(r)
if len(sys.argv)>2:
    for r in rows:
        if sys.argv[2].upper() in r[3] or sys.argv[2].upper() in r[7]: print('MATCH',r)
# verify bucket lookup
bad=0
for r in rows:
    k=uuid.UUID(r[3]).bytes; a,b=struct.unpack('<QQ',k); key=(a^b)
    bi=key%cap; ref=struct.unpack_from('<II',d,tab+bi*8)
    ok=False
    o,s=ref
    seen=0
    while s and seen<100:
        if o==r[0]: ok=True;break
        nn=struct.unpack_from('<II',d,nodes+o+0x18); o,s=nn; seen+=1
    if not ok and r[6]==1: bad+=1
print('chain-verified; bad=',bad)
