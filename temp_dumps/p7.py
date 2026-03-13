import struct

DUMP = r"C:\Users\porta\AppData\Local\CrashDumps\rapid_cord_flutter.exe.27916.dmp"
CRASHING_TID = 0x1600

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
    # Modules
    f.seek(0x1648)
    n = struct.unpack("<I", f.read(4))[0]
    mods = []
    for _ in range(n):
        raw = f.read(108)
        if len(raw) < 108: break
        mods.append((struct.unpack_from("<Q",raw,0)[0], struct.unpack_from("<I",raw,8)[0], struct.unpack_from("<I",raw,20)[0]))

    # Thread list at 0x708
    f.seek(0x708)
    num_threads = struct.unpack("<I", f.read(4))[0]
    for i in range(num_threads):
        raw = f.read(48)
        tid = struct.unpack_from("<I", raw, 0)[0]
        if tid != CRASHING_TID: continue

        stack_vaddr = struct.unpack_from("<Q", raw, 24)[0]
        stack_data_size = struct.unpack_from("<I", raw, 32)[0]
        stack_data_rva  = struct.unpack_from("<I", raw, 36)[0]
        ctx_data_size   = struct.unpack_from("<I", raw, 40)[0]
        ctx_data_rva    = struct.unpack_from("<I", raw, 44)[0]
        print("Thread 0x{:x}: stack_vaddr={:#x} stack_data_size={:#x} stack_data_rva={:#x}".format(
               tid, stack_vaddr, stack_data_size, stack_data_rva))
        print("  ctx_data_size={} ctx_data_rva={:#x}".format(ctx_data_size, ctx_data_rva))

        # Read the CONTEXT
        f.seek(ctx_data_rva)
        ctx = f.read(ctx_data_size)
        rip = struct.unpack_from("<Q", ctx, 248)[0]
        rsp = struct.unpack_from("<Q", ctx, 152)[0]
        rbp = struct.unpack_from("<Q", ctx, 160)[0]
        print("  RIP={:#x} RSP={:#x} RBP={:#x}".format(rip, rsp, rbp))

        # Read stack from thread descriptor (if any)
        if stack_data_rva > 0 and stack_data_size > 0:
            f.seek(stack_data_rva)
            stack_bytes = f.read(stack_data_size)
            print("  Stack bytes read:", len(stack_bytes))
            hits = []
            for off in range(0, len(stack_bytes)-7, 8):
                val = struct.unpack_from("<Q", stack_bytes, off)[0]
                if 0x00007ff000000000 <= val <= 0x00007fffffffffff:
                    r = addr_to_mod(mods, val)
                    if r:
                        hits.append((stack_vaddr + off, val, r))
            for sp, addr, (base, size, nrva, off) in hits[:40]:
                nm = get_mod_name(f, nrva).split("\\")[-1]
                print("    sp={:#x}  {:<48s}  +{:#x}".format(sp, nm, off))
        else:
            print("  No inline stack data (stack_data_rva=0)")
            # Try MemoryListStream (type=5) at rva=0x2fc41
            f.seek(0x2fc41)
            num_regions = struct.unpack("<I", f.read(4))[0]
            print("  Scanning {} memory regions for stack at RSP={:#x}...".format(num_regions, rsp))
            for _ in range(num_regions):
                reg = f.read(16)
                if len(reg) < 16: break
                mstart = struct.unpack_from("<Q", reg, 0)[0]
                msize  = struct.unpack_from("<I", reg, 8)[0]
                mrva   = struct.unpack_from("<I", reg, 12)[0]
                if mstart <= rsp < mstart + msize:
                    offset_in_region = rsp - mstart
                    cur = f.tell()
                    f.seek(mrva + offset_in_region)
                    stack_bytes = f.read(msize - offset_in_region)
                    print("  Found stack in MemoryList: region vaddr={:#x} size={:#x} rva={:#x}".format(mstart, msize, mrva))
                    hits = []
                    for off in range(0, len(stack_bytes)-7, 8):
                        val = struct.unpack_from("<Q", stack_bytes, off)[0]
                        if 0x00007ff000000000 <= val <= 0x00007fffffffffff:
                            r = addr_to_mod(mods, val)
                            if r:
                                hits.append((rsp + off, val, r))
                    for sp2, addr, (base, size, nrva, off2) in hits[:40]:
                        nm = get_mod_name(f, nrva).split("\\")[-1]
                        print("    sp={:#x}  {:<48s}  +{:#x}".format(sp2, addr, nm, off2))
                    f.seek(cur)
