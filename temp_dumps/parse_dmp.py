import struct

dmp_path = r"C:\Users\porta\AppData\Local\CrashDumps\rapid_cord_flutter.exe.27916.dmp"
CRASH_ADDR = 0x00007ffa32abb00c
STREAM_RVA = 0x2fc41

with open(dmp_path,"rb") as f:
    f.seek(STREAM_RVA)
    num_modules = struct.unpack("<I", f.read(4))[0]
    print("modules:", num_modules)
    results = []
    for i in range(num_modules):
        b = f.read(108)
        if len(b) < 108:
            break
        base = struct.unpack_from("<Q", b, 0)[0]
        size = struct.unpack_from("<I", b, 8)[0]
        name_rva = struct.unpack_from("<I", b, 20)[0]
        if base <= CRASH_ADDR < base + size:
            results.append((base, size, name_rva, CRASH_ADDR - base))
    for base, size, name_rva, offset in results:
        f.seek(name_rva)
        name_len = struct.unpack("<I", f.read(4))[0]
        name_bytes = f.read(name_len)
        name = name_bytes.decode("utf-16-le","replace").rstrip("\x00")
        print("CRASH: {} base={:#x} offset={:#x}".format(name, base, offset))
