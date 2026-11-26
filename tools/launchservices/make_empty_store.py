#!/usr/bin/env python3
"""Write an empty-but-structurally-complete Launch Services store (all 33 tables of macOS 26.7.2, no records) for the container tests.
usage: make_empty_store.py OUT.csstore [seq] [uuid]
The binding tables are open-addressing hash tables of 8-byte slots; an empty slot is 0xeeeeeee1/0xeeeeeee1 (tombstone 0xddddddd2)."""
import sys, struct, uuid, time
sys.path.insert(0, __import__('os').path.dirname(__file__))
import csstore_write as w

PLAIN = [(8,'Bundle'),(12,'Claim'),(16,'Service'),(20,'Type'),(24,'HandlerPref'),(28,'Container'),(32,'Alias'),(36,'Plugin'),(40,'ExtensionPoint'),
         (44,'BindingList'),(48,'PropertyList'),(52,'LocalizedString'),(56,'CanonicalString')]
# (table id, name, unit id of its hash table, slots)
BIND = [(60,'BindableKeyMap',0x14,8161),(64,'UTIBinding',0x14,8161),(68,'ExtensionBinding',0xc,2041),(72,'OSTypeBinding',8,1021),(76,'MIMEBinding',8,1021),
        (80,'NSPasteboardBinding',4,511),(84,'DeviceModelCodeBinding',0x10,4081),(88,'BluetoothVendorProductIDBinding',4,511),(92,'URLSchemeBinding',4,511),
        (96,'BundleIDBinding',8,1021),(100,'BundleNameBinding',0xc,2041),(104,'ActivityTypeBinding',0xc,2041),(108,'PluginBundleIDBinding',0xc,2041),
        (112,'PluginProtocolBinding',4,511),(116,'PluginUUIDBinding',0xc,2041),(120,'ExtensionPointIDBinding',4,511)]

def db_header(seq, uid, build=b'25G332', model=b'/iMac19,1', xcode=b'2416', sysver=(26, 7, 2, 0), when=None):
    h = struct.pack('<II', 0x01400019, 0xc0) + b''.join(struct.pack('<Q', x) for x in sysver)
    h += struct.pack('<II', 0x05000001, 0) + build.ljust(16, b'\0') + model.ljust(64, b'\0')
    h += struct.pack('<Q', seq) + uid.bytes + struct.pack('<II', when or int(time.time()), 0) + xcode.ljust(32, b'\0')
    assert len(h) == 0xc0 + 0, len(h)
    return h[:0xc0]

def tables(seq=1, uid=None, when=None):
    """the 33 empty tables as csstore_write.Table objects (the extension point of lsbuild.py)"""
    uid = uid or uuid.uuid4()
    tabs = [w.Table('DB Header', 4, db_header(seq, uid, when=when))]
    for tid, n in PLAIN: tabs.append(w.Table(n, tid))
    for tid, n, u, cap in BIND:
        ex = struct.pack('<7I', 0, u, cap, 0, cap // 2, 0xeeeeeee1, 0xddddddd2) + (b'\0' * 4 if n == 'BindableKeyMap' else b'')
        t = w.Table(n, tid, ex, u // 4); t.add(struct.pack('<II', 0xeeeeeee1, 0xeeeeeee1) * cap, uid=u); tabs.append(t)
    s = w.Table('<string>', 124, b'\xff\xff\xff\xff'); s.nbuckets = 8192; tabs.append(s)
    a = w.Table('<array>', 128); a.nbuckets = 8192; tabs.append(a)
    tabs.append(w.Table('<dictionary>', 132))
    return tabs

def build(seq=1, uid=None, when=None):
    return w.build(tables(seq, uid, when), generation=1)

if __name__ == '__main__':
    open(sys.argv[1], 'wb').write(build(int(sys.argv[2]) if len(sys.argv) > 2 else 1, uuid.UUID(sys.argv[3]) if len(sys.argv) > 3 else None))
