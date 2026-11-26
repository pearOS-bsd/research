#!/usr/bin/env python3
"""Register an application bundle in a Launch Services database written with lsbuild.py: the Bundle record, its Alias, strings, property lists and bindings,
shaped like what lsd writes (docs/LAUNCHSERVICES-WIRE.md sections 5.12, 5.13).  Claims, types, services and plugins are not written yet (section 9, U3).
    python3 lsapp.py [--base STORE] OUT.csstore /path/to/App.app [...]
Own code, BSD-2-Clause."""
import os, struct, sys, time, plistlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lsbuild, bookmark

CF_EPOCH = 978307200
REVISION = 0xb                    # Bundle.revision lsd writes (offset 544): a record with another revision is ignored by bundleRecordWithURL:
FLAG_TMP = 1 << 47                # _bundleFlags bit: bundle below a temporary directory (/tmp, /private/tmp ...): bundleRecordWithBundleIdentifier: skips it
CLASS_APPLICATION = 2

def facts(path):
    """what the record needs from the file system: the resolved path, the file id of every component, times, owner"""
    path = os.path.abspath(path).rstrip('/'); real = os.path.realpath(path)
    comps = [c for c in real.split('/') if c]
    inodes = []; cur = ''
    for c in comps:
        cur += '/' + c; inodes.append(os.stat(cur).st_ino)
    st = os.stat(real); info = plistlib.load(open(os.path.join(real, 'Contents', 'Info.plist'), 'rb'))
    ex = os.path.join(real, 'Contents', 'MacOS', info.get('CFBundleExecutable', ''))
    est = os.stat(ex) if os.path.exists(ex) else st
    birth = getattr(st, 'st_birthtime', st.st_ctime)
    return dict(path=path, real=real, comps=comps, inodes=inodes, mtime=int(st.st_mtime) - CF_EPOCH, birth=birth - CF_EPOCH, uid=st.st_uid, info=info,
                exec_ino=est.st_ino, exec_mtime=int(est.st_mtime) - CF_EPOCH)

def version(s):
    """LSVersionNumber: 4 x u64 (major, minor, patch, 0) from '12.0' / '1828.6.1'"""
    p = [int(x) for x in str(s or '0').split('.')[:3] if x.isdigit()] + [0, 0, 0]
    return struct.pack('<QQQQ', p[0], p[1], p[2], 0)

def add_app(db, path, container=None, now=None):
    """add the Bundle record of the application at `path`; returns its unit id.  container = unit id of the volume's Container record (see volume_container)."""
    f = facts(path); info = f['info']; now = int((now or time.time()) - CF_EPOCH)
    bid = info['CFBundleIdentifier']; exe = info.get('CFBundleExecutable', '')
    tmp = f['real'].startswith(('/private/tmp', '/private/var/tmp', '/private/var/folders'))
    db.seq += 4
    b = bytearray(588)
    def S(o, s):
        if s: struct.pack_into('<I', b, o, db.string(s))
    struct.pack_into('<I', b, 0, db.alias(bookmark.for_path(f['path'], f['inodes'], f['birth'], components=f['comps'])))
    struct.pack_into('<I', b, 4, container if container is not None else volume_container(db))
    S(8, 'Contents/MacOS/' + exe); S(12, bid)
    struct.pack_into('<I', b, 24, 1); struct.pack_into('<i', b, 28, now)                       # platform (1 = macOS), registration time
    b[32:64] = version(info.get('CFBundleVersion'))
    S(104, info.get('CFBundleName')); S(112, info.get('CFBundleDisplayName') or info.get('CFBundleName'))
    struct.pack_into('<I', b, 124, db.plist(info))
    struct.pack_into('<B', b, 136, 0xff if tmp else 0)
    struct.pack_into('<I', b, 148, CLASS_APPLICATION)
    struct.pack_into('<Q', b, 152, 2 | (FLAG_TMP if tmp else 0))
    struct.pack_into('<I', b, 160, 0x10000); struct.pack_into('<I', b, 164, 0x10008a)       # 160 and 168.. copied from a registered Calculator; 164 itemFlags: lsd writes 0x10008e, but with bit 0x4 set bundleRecordWithBundleIdentifier: failed for our app in the home directory (cleared: found), see 5.13
    struct.pack_into('<I', b, 168, 0x05010005); struct.pack_into('<I', b, 172, 0x05010101); struct.pack_into('<I', b, 176, 5)
    struct.pack_into('<4s', b, 184, info.get('CFBundlePackageType', '????')[:4].encode()[::-1])     # _hfsType, big-endian four-char code in a little-endian u32
    struct.pack_into('<4s', b, 188, info.get('CFBundleSignature', '????')[:4].encode()[::-1])
    struct.pack_into('<Q', b, 192, f['inodes'][-1]); struct.pack_into('<Q', b, 200, f['exec_ino'])
    struct.pack_into('<i', b, 208, f['mtime'])                                                  # must equal the bundle's mtime: bundleRecordWithURL: compares it
    struct.pack_into('<I', b, 212, 1)
    struct.pack_into('<I', b, 280, f['uid']); struct.pack_into('<i', b, 284, f['exec_mtime'])
    struct.pack_into('<Q', b, 320, db.seq)
    S(340, bid.lower())                                                                          # identifier: lower case (exactIdentifier at 12 keeps the case)
    S(360, f['comps'][-1].lower()); S(364, info.get('CFBundleVersion')); S(368, info.get('CFBundleShortVersionString'))
    icon = info.get('CFBundleIconFile'); iname = info.get('CFBundleIconName')
    if icon or iname:
        S(480, iname or icon)
        prim = {k: v for k, v in (('CFBundleIconFile', icon), ('CFBundleIconName', iname)) if v}
        struct.pack_into('<I', b, 484, db.plist({'CFBundlePrimaryIcon': prim}))                # NOT the flat form: ISBundleIcon reads CFBundlePrimaryIcon
        if icon:
            rel = 'Contents/Resources/' + (icon if icon.endswith('.icns') else icon + '.icns')
            if os.path.exists(os.path.join(f['real'], rel)): struct.pack_into('<I', b, 488, db.string_array([rel]))
    acts = ['NOTIFICATION#:' + bid] + [a for a in info.get('NSUserActivityTypes', []) if isinstance(a, str)]
    struct.pack_into('<I', b, 532, db.string_array(acts))
    for o in (344, 348, 500, 520, 536): struct.pack_into('<I', b, o, db.array([]))
    struct.pack_into('<B', b, 544, REVISION); struct.pack_into('<i', b, 560, now)
    unit = db.bundle(bytes(b))
    db.bind('BundleIDBinding', bid.lower(), unit)
    db.bind('BundleNameBinding', f['comps'][-1].lower(), unit)
    if info.get('CFBundleName'): db.bind('BundleNameBinding', info['CFBundleName'], unit)
    for a in acts: db.bind('ActivityTypeBinding', a, unit)
    db.set_sequence(db.seq)
    return unit

def volume_container(db):
    """the Container record of the volume.  In an empty database one all-zero Container (24 bytes) is enough; in a populated one the bundle has to point at the
    Container of its volume (a new zero Container made lookups fail for the real store, section 5.13): the first existing one is used, pass `container=` to choose."""
    if not hasattr(db, '_container'):
        ex = sorted(db.tabs['Container'].units)
        db._container = ex[0] if ex else db.container(bytes(24))
    return db._container

if __name__ == '__main__':
    a = sys.argv[1:]; base = None
    if a and a[0] == '--base': base = a[1]; a = a[2:]
    db = lsbuild.LSDB.from_store(open(base, 'rb').read()) if base else lsbuild.LSDB(seq=1)
    for app in a[1:]: print(app, hex(add_app(db, app)))
    open(a[0], 'wb').write(db.build())
