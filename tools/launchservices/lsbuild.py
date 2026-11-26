#!/usr/bin/env python3
"""Builder of Launch Services databases (CSStore2, schema 0x01400019) with records: strings, arrays, property lists, aliases, containers, bundles
and the string-binding hash tables.  Layouts: docs/LAUNCHSERVICES-WIRE.md section 5.  Own code, BSD-2-Clause.

    db = LSDB(seq=2200, uuid=...)
    s  = db.string('com.example.app')                 # interned string id
    a  = db.array([id, id, ...])                       # unit ids; 16-bit packed when all ids < 65536
    p  = db.plist({'CFBundleIdentifier': 'x'})         # property list unit: 'lnch' + binary plist, keys/values compacted like lsd does
    db.bind('BundleIDBinding', 'com.example.app', bundle_unit_id)
    open(f, 'wb').write(db.build())
"""
import plistlib, struct, sys, os, uuid as uuidmod
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import csstore_write as w
import make_empty_store as mes

ESC = '\x08'
ALPHABET = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ~!@#$%^&*()_'
def abbreviation(n):
    """index n (0..255) of the common-string list -> its short form: base-64 digits, least significant first (LaunchServices: _LSPlistLookUpCompactedStringByIndex)"""
    out = ''
    while True:
        out += ALPHABET[n & 63]
        if n < 64: return out
        n >>= 6

def load_common(path=None):
    path = path or os.path.join(os.path.dirname(os.path.abspath(__file__)), 'plist_common_strings.txt')
    return open(path, encoding='utf8').read().split('\n') if os.path.exists(path) else []

class Compactor:
    """_LSPlistCompactString: a string that is in the common list becomes its short form; a string that already looks like a short form
    (or begins with the escape character) gets the escape character in front; everything else is stored as is."""
    def __init__(self, common):
        self.idx = {s: i for i, s in enumerate(common)}
        self.short = {abbreviation(i) for i in range(256)}
    def s(self, x):
        if x and (x[0] == ESC or x in self.short): return ESC + x
        i = self.idx.get(x)
        return abbreviation(i) if i is not None else x
    def walk(self, o):
        if isinstance(o, dict): return {self.s(k): self.walk(v) for k, v in o.items()}
        if isinstance(o, list): return [self.walk(v) for v in o]
        if isinstance(o, str): return self.s(o)
        return o

# the binding class names LaunchServices looks up (__CSGetStringForCharacters) before it accepts a store: kLSBindingInfo of LaunchServices, in table order
BINDING_CLASS_NAMES = ['com.apple.uniform-type-identifier', 'public.filename-extension', 'com.apple.ostype', 'public.mime-type', 'com.apple.nspboard-type',
                       'com.apple.device-model-code', 'public.bluetooth-vendor-product-id', 'public.url-scheme']
PACKED_ALPHABET = '\0 abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'    # kPackedAlphabet of CoreServicesStore: 64 bytes, index 0 is NUL (never matches a character)
def packed_id(s):
    """CSStore2::String::Find: a string of 1..5 characters, all in kPackedAlphabet, has no unit: its id is the 6-bit packed characters (first character
    most significant) * 4 + 1.  None when the string does not qualify."""
    if not s or len(s) > 5 or any(c not in PACKED_ALPHABET[1:] for c in s): return None
    v = 0
    for c in s: v = (v << 6) | PACKED_ALPHABET.index(c)
    return v * 4 + 1
def string_hash(b):
    """CSStore2::_StringFunctions::getHashCode(chars, len): h = len; h = byte + h*17 over the bytes (first and last 64 bytes when len > 128); ((h << (len & 7)) + h) & 0xffff"""
    n = len(b); h = n
    for c in (b if n <= 0x80 else b[:64] + b[n - 64:]): h = (c + h * 0x11) & 0xffffffff
    return (((h << (n & 7)) + h) & 0xffffffff) & 0xffff
def string_cache(strings, nbuckets=8192):
    """the persisted string cache the <string> table's extra points to: u32 nbuckets | nbuckets x {u32 count, u32 absolute file offset of the entries} | entries {u32 string id, u32 0x100 + retain count}"""
    def make(base):
        bk = [[] for _ in range(nbuckets)]
        for sid, b in strings.items(): bk[string_hash(b) % nbuckets].append(sid)
        out = struct.pack('<I', nbuckets); cur = base + 4 + 8 * nbuckets; ents = b''
        for l in bk:
            out += struct.pack('<II', len(l), cur if l else 0xffffffff)
            for sid in l: ents += struct.pack('<II', sid, 0x101); cur += 8
        return out + ents
    return make

PRIMES = [511, 1021, 2041, 4081, 8161, 16321, 32641, 65281]
EMPTY, DELETED = 0xeeeeeee1, 0xddddddd2

class LSDB:
    def __init__(self, seq=1, uid=None, when=None, common=None):
        self.tabs = {t.name: t for t in mes.tables(seq, uid, when)}
        self.strs = {}                           # str -> id
        self.binds = {}                          # table -> {key string id: [unit ids]}
        self.comp = Compactor(common if common is not None else load_common())
        self.seq = seq
        for n in BINDING_CLASS_NAMES: self.string(n)            # _LSSchemaConfigureBindingMap: these strings must exist (ids 4, 8, ... like in a real store)
    @classmethod
    def from_store(cls, data, seq=None):
        """a builder holding every unit of an existing store (to register records into it); the binding tables are read into key -> array id maps, the string cache is rebuilt"""
        import csstore
        st = csstore.Store(data); self = cls.__new__(cls)
        self.tabs = {}; self.binds = {}; self.strs = {}; self.comp = Compactor(load_common())
        for t in sorted(st.tables.values(), key=lambda t: t['id']):
            hdr, ln = struct.unpack_from('<II', st.d, t['off'])
            tab = w.Table(t['name'], t['id'], bytes(st.d[t['off'] + 8 + 72:t['off'] + 8 + ln]), t['nextid'])
            for uid, h, p in st.units(t['name']): tab.units[uid] = bytes(p)
            if t['name'] in ('<string>', '<array>'): tab.nbuckets = 8192
            self.tabs[t['name']] = tab
        for sid, p in self.tabs['<string>'].units.items(): self.strs[p.decode('utf8')] = sid
        for tname, tab in self.tabs.items():
            if tname.endswith('Binding'):
                uid = struct.unpack_from('<I', tab.extra, 4)[0]; p = tab.units[uid]; n = len(p) // 8
                ws = struct.unpack('<%dI' % (2 * n), p)
                self.binds[tname] = {ws[i]: ws[n + i] for i in range(n) if ws[i] not in (EMPTY, DELETED)}
        hdr = self.tabs['DB Header'].extra; self.seq = struct.unpack_from('<Q', hdr, 0x80)[0] if seq is None else seq
        return self
    def add(self, table, payload):
        return self.tabs[table].add(payload)
    def string(self, s):
        if s is None or s == '': return 0
        p = packed_id(s)
        if p is not None: return p
        if s not in self.strs: self.strs[s] = self.add('<string>', s.encode('utf8'))
        return self.strs[s]
    def array(self, ids):
        ids = list(ids)
        if all(i <= 0xffff for i in ids): return self.add('<array>', struct.pack('<I', len(ids) | 0x20000000) + struct.pack('<%dH' % len(ids), *ids))
        return self.add('<array>', struct.pack('<I', len(ids)) + struct.pack('<%dI' % len(ids), *ids))
    def string_array(self, strings): return self.array([self.string(s) for s in strings])
    def plist(self, obj, compact=True):
        if obj is None: return 0
        o = self.comp.walk(obj) if compact else obj
        return self.add('PropertyList', b'lnch' + plistlib.dumps(o, fmt=plistlib.FMT_BINARY))
    def alias(self, data): return self.add('Alias', data)
    def container(self, payload24):
        assert len(payload24) == 24; return self.add('Container', payload24)
    def bundle(self, rec588):
        assert len(rec588) == 588; return self.add('Bundle', rec588)
    def bind(self, table, key, unit):
        k = self.string(key); m = self.binds.setdefault(table, {})
        l = m.setdefault(k, [])
        if isinstance(l, int): l = m[k] = self.array_elements(l)          # a key that came from a loaded store: its array becomes a list again
        if unit not in l: l.append(unit)
    def array_elements(self, aid):
        p = self.tabs['<array>'].units[aid]; h, = struct.unpack_from('<I', p); n = h & 0xffffff
        return list(struct.unpack_from('<%d%s' % (n, 'H' if h >> 24 & 0x20 else 'I'), p, 4))
    def _bindings(self):
        for tname, m in self.binds.items():
            t = self.tabs[tname]
            uid = struct.unpack_from('<I', t.extra, 4)[0]
            vals = {k: (v if isinstance(v, int) else self.array(v)) for k, v in m.items()}
            n = next(p for p in PRIMES if len(vals) * 2 <= p) if vals else PRIMES[0]
            n = max(n, struct.unpack_from('<I', t.extra, 8)[0])                    # never smaller than the empty store's table
            keys = [EMPTY] * n; vs = [EMPTY] * n
            for k, v in vals.items():
                i = k % n
                while keys[i] != EMPTY: i = (i + 1) % n                            # linear probing, wrapping (CSMapFindBucketForKey)
                keys[i], vs[i] = k, v
            t.units[uid] = struct.pack('<%dI' % (2 * n), *keys, *vs)
            t.extra = struct.pack('<7I', 0, uid, n, n - len(vals), n // 2, EMPTY, DELETED) + t.extra[28:]
    def build(self):
        self._bindings()
        self.tabs['<string>'].raw = string_cache({i: s.encode('utf8') for s, i in self.strs.items()})
        return w.build(list(self.tabs.values()), generation=1)

if __name__ == '__main__':
    d = LSDB(seq=1)
    open(sys.argv[1], 'wb').write(d.build())
