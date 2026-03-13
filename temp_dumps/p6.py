import struct

DUMP = r"C:\Users\porta\AppData\Local\CrashDumps\rapid_cord_flutter.exe.27916.dmp"
# Crashing thread id from exception stream: 0x1600
# ExceptionStream (type=6) at rva=0x660
# ThreadListStream (type=3) at rva=0x708, size=3892
# MINIDUMP_THREAD = 48 bytes; Stack = MINIDUMP_MEMORY_DESCRIPTOR (StartOfMemoryRange=8, DataSize+Rva=8) at offset 24
# Context = MINIDUMP_LOCATION_DESCRIPTOR (DataSize=4, Rva=4) at offset 40

CRASHING_TID = 0x1600

def parse_modules(f):
    f.seek(0x1648)
    n = struct.unpack("<I", f.read(4))[0]
    mods = []
    for _ in range(n):
        raw = f.read(108)
        if len(raw) < 108: break
        base = struct.unpack_from("<Q", raw, 0)[0]
        size = struct.unpack_from("<I", raw, 8)[0]
        nrva = struct.unpack_from("<I", raw, 20)[0]
        mods.append((base, size, nrva))
    return mods

def get_mod_name(f, nrva):
    f.seek(nrva)
    nl = struct.unpack("<I", f.read(4))[0]
    return f.read(min(nl,512)).decode("utf-16-le","replace").rstrip("\x00")

def addr_to_mod(mods, addr):
    for base, size, nrva in mods:
        if base <= addr < base+size:
            return base, size, nrva, addr-base
    return None

with open(DUMP,"rb") as f:
    mods = parse_modules(f)
    
    # Parse thread list
    f.seek(0x708)
    num_threads = struct.unpack("<I", f.read(4))[0]
    print("Threads:", num_threads)
    
    for i in range(num_threads):
        t = f.read(48)
        if len(t) < 48: break
        tid = struct.unpack_from("<I", t, 0)[0]
        stack_start = struct.unpack_from("<Q", t, 24)[0]
        stack_size  = struct.unpack_from("<I", t, 32)[0]
        stack_rva   = struct.unpack_from("<I", t, 36)[0]
        ctx_size    = struct.unpack_from("<I", t, 40)[0]
        ctx_rva     = struct.unpack_from("<I", t, 44)[0]
        print("  Thread 0x{:x}: stack={:#x} ssize={:#x} ctx_rva={:#x} ctx_size={}".format(
               tid, stack_start, stack_size, ctx_rva, ctx_size))
        if tid == CRASHING_TID:
            print("  *** THIS IS THE CRASHING THREAD ***")
            # Parse CONTEXT (x64): RIP is at offset 248, RSP at 152
            cur = f.tell()
            f.seek(ctx_rva)
            ctx = f.read(ctx_size)
            if len(ctx) >= 256:
                rip = struct.unpack_from("<Q", ctx, 248)[0]
                rsp = struct.unpack_from("<Q", ctx, 152)[0]
                print("  RIP={:#x}  RSP={:#x}".format(rip, rsp))
                # Walk the stack looking for return addresses
                f.seek(stack_rva)
                stack_data = f.read(stack_size)
                print("  Scanning stack for return addresses...")
                hits = []
                for off in range(0, len(stack_data)-7, 8):
                    val = struct.unpack_from("<Q", stack_data, off)[0]
                    if 0x00007fff00000000 < val < 0x00007fffffffffff:
                        r = addr_to_mod(mods, val)
                        if r:
                            hits.append((stack_start + off, val, r))
                print("  Stack hits:")
                for sp, addr, (base, size, nrva, off) in hits[:30]:
                    nm = get_mod_name(f, nrva)
                    short = nm.split("\\")[-1]
                    print("    sp={:#x}  ret={:#x}  {}+{:#x}".format(sp, addr, short, off))
            f.seek(cur)
