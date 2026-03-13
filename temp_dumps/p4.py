import struct

f = open(r'C:\Users\porta\AppData\Local\CrashDumps\rapid_cord_flutter.exe.27916.dmp','rb')
f.seek(0x2fc41)
n = struct.unpack('<I', f.read(4))[0]
print('N:', n)
ADDR = 0x00007ffa32abb00c
found = False
for i in range(n):
    raw = f.read(108)
    if len(raw) < 108:
        print('short read at', i)
        break
    base = struct.unpack_from('<Q', raw, 0)[0]
    size = struct.unpack_from('<I', raw, 8)[0]
    nrva = struct.unpack_from('<I', raw, 20)[0]
    if base <= ADDR < base + size:
        cur = f.tell()
        f.seek(nrva)
        nl = struct.unpack('<I', f.read(4))[0]
        name = f.read(min(nl, 512)).decode('utf-16-le', 'replace').rstrip('\x00')
        f.seek(cur)
        print('MATCH mod', i, ':', name)
        print('  base={:#x} size={:#x} off={:#x}'.format(base, size, ADDR-base))
        found = True
f.close()
if not found:
    print('No module found containing', hex(ADDR))
    print('Checking if minidump has full module list...')
