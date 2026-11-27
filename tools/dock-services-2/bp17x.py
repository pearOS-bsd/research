#!/usr/bin/env python3
"""bplist17 decoder (NSXPC "root"), ../iconservices/bp17.py plus the one-byte 0xbN objects seen in proxy (_NSXPCDistantObject) records."""
import sys, struct
def dec(buf):
    assert buf[:8]==b'bplist17'
    pos=[8]
    def u64(p): return struct.unpack_from('<Q',buf,p)[0]
    def length(low,p):
        if low!=0xf: return low,p
        t=buf[p]; assert t>>4==1,(hex(t),p)
        n=t&0xf; return int.from_bytes(buf[p+1:p+1+n],'little'),p+1+n
    def obj(p,depth=0):
        t=buf[p]; hi=t>>4; lo=t&0xf
        if t==0xe0: return ('nil',),p+1
        if t==0xc0: return False,p+1
        if t==0xc1: return True,p+1
        if t==0x22: return struct.unpack_from('<f',buf,p+1)[0],p+5
        if t==0x23: return struct.unpack_from('<d',buf,p+1)[0],p+9
        if hi==1:  # uint, lo bytes
            return int.from_bytes(buf[p+1:p+1+lo],'little'),p+1+lo
        if hi==0xb: return ('b%x'%lo,),p+1
        if hi==7:
            n,q=length(lo,p+1); s=buf[q:q+n]; return ('str',p,s.rstrip(b'\0').decode()),q+n
        if hi==6:
            n,q=length(lo,p+1); return ('u16',buf[q:q+2*n].decode('utf-16le')),q+2*n
        if hi==4:
            n,q=length(lo,p+1); return ('data',bytes(buf[q:q+n])),q+n
        if hi==8:
            n=lo; ref=int.from_bytes(buf[p+1:p+1+n],'little'); 
            return ("ref",ref,strat(ref) if ref<len(buf) else "?BAD"),p+1+n
        if hi in (0xa,0xd):
            end=u64(p+1); q=p+9; items=[]
            while q<=end:
                o,q=obj(q,depth+1); items.append(o)
            if hi==0xa: return ('arr',items),q
            d=[(items[i],items[i+1]) for i in range(0,len(items),2)]
            return ('dict',d),q
        raise Exception('tag %x at %d'%(t,p))
    def strat(off):
        o,_=obj(off); return o[2] if o[0]=='str' else o
    o,q=obj(8)
    return o,q
def show(o,ind=0):
    pad='  '*ind
    k=o[0] if isinstance(o,tuple) else None
    if k=='arr':
        print(pad+'['); [show(x,ind+1) for x in o[1]]; print(pad+']')
    elif k=='dict':
        print(pad+'{')
        for a,b in o[1]:
            ks=a[2] if a[0]=='str' else ('%s(ref@%s)'%(a[2],a[1]) if a[0]=='ref' else a)
            if isinstance(b,tuple) and b[0] in('arr','dict'): print(pad+'  %s:'%ks); show(b,ind+2)
            else: print(pad+'  %s: %s'%(ks,fmt(b)))
        print(pad+'}')
    else: print(pad+fmt(o))
def fmt(b):
    if isinstance(b,tuple):
        if b[0]=='str': return 'str@%d %r'%(b[1],b[2])
        if b[0]=='ref': return 'ref->@%d %r'%(b[1],b[2])
        if b[0]=='data': return 'data[%d] %s'%(len(b[1]),b[1][:48].hex()+('...' if len(b[1])>48 else ''))
        if b[0]=='u16': return 'u16 %r'%(b[1] if len(b[1])<120 else b[1][:120]+'...')
        return str(b)
    return repr(b)
if __name__=='__main__':
    for f in sys.argv[1:]:
        buf=open(f,'rb').read(); print('==',f,len(buf))
        o,q=dec(buf); show(o); print('consumed',q,'of',len(buf))
