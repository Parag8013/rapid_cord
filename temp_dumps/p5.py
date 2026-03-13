import struct

f = open(r"C:\Users\porta\AppData\Local\CrashDumps\rapid_cord_flutter.exe.27916.dmp","rb")
# ModuleListStream (type=4) is at rva=0x1648, size=13288
f.seek(0x1648)
n = struct.unpack("<I", f.read(4))[0]
print("Modules:", n)
ADDR = 0x00007ffa32abb00c
all_mods = []
for i in range(n):
    raw = f.read(108)
    if len(raw) < 108: break
    base = struct.unpack_from("<Q", raw, 0)[0]
    size = struct.unpack_from("<I", raw, 8)[0]
    nrva = struct.unpack_from("<I", raw, 20)[0]
    all_mods.append((base, size, nrva))
    if base <= ADDR < base + size:
        cur = f.tell()
        f.seek(nrva)
        nl = struct.unpack("<I", f.read(4))[0]
        name = f.read(min(nl, 512)).decode("utf-16-le","replace").rstrip("\x00")
        f.seek(cur)
        print("MATCH [{:3d}]: {}".format(i, name))
        print("  base={:#x}  size={:#x}  off={:#x}".format(base, size, ADDR-base))

print("Closest mods to crash addr:")
diffs = [(abs(ADDR - b), b, s, nr) for b,s,nr in all_mods]
diffs.sort()
for diff, b, s, nr in diffs[:5]:
    f.seek(nr)
    nl = struct.unpack("<I", f.read(4))[0]
    name = f.read(min(nl,512)).decode("utf-16-le","replace").rstrip("\x00")
    print("  diff={:#x} base={:#x} size={:#x} :: {}".format(diff,b,s,name))
f.close()
