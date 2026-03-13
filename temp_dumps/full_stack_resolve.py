"""
Extract ALL stack frames from the minidump and resolve with PDB.
This finds every 8-byte value on the crash thread's stack that maps to
flutter_webrtc_plugin.dll code section and resolves the symbol.
"""
import struct
import ctypes
import ctypes.wintypes
import os
import sys

# ── DbgHelp setup ─────────────────────────────────────────────────────────
class SYMBOL_INFO(ctypes.Structure):
    _fields_ = [
        ("SizeOfStruct", ctypes.wintypes.ULONG),
        ("TypeIndex",    ctypes.wintypes.ULONG),
        ("Reserved",     ctypes.c_uint64 * 2),
        ("Index",        ctypes.wintypes.ULONG),
        ("Size",         ctypes.wintypes.ULONG),
        ("ModBase",      ctypes.c_uint64),
        ("Flags",        ctypes.wintypes.ULONG),
        ("Value",        ctypes.c_uint64),
        ("Address",      ctypes.c_uint64),
        ("Register",     ctypes.wintypes.ULONG),
        ("Scope",        ctypes.wintypes.ULONG),
        ("Tag",          ctypes.wintypes.ULONG),
        ("NameLen",      ctypes.wintypes.ULONG),
        ("MaxNameLen",   ctypes.wintypes.ULONG),
        ("Name",         ctypes.c_char * 2048),
    ]

class IMAGEHLP_LINE64(ctypes.Structure):
    _fields_ = [
        ("SizeOfStruct",  ctypes.wintypes.DWORD),
        ("Key",           ctypes.c_void_p),
        ("LineNumber",    ctypes.wintypes.DWORD),
        ("FileName",      ctypes.c_char_p),
        ("Address",       ctypes.c_uint64),
    ]

dbghelp  = ctypes.WinDLL("dbghelp.dll")
kernel32 = ctypes.WinDLL("kernel32.dll")

SYMOPT_UNDNAME        = 0x00000002
SYMOPT_DEFERRED_LOADS = 0x00000004
SYMOPT_LOAD_LINES     = 0x00000010

DLL_PATH = r"C:\rapid_cord\rapid_cord_flutter\build\windows\x64\plugins\flutter_webrtc\Debug\flutter_webrtc_plugin.dll"
PDB_PATH = r"C:\rapid_cord\rapid_cord_flutter\build\windows\x64\plugins\flutter_webrtc\Debug"
DUMP_PATH = r"C:\Users\porta\AppData\Local\CrashDumps\rapid_cord_flutter.exe.27916.dmp"

BASE      = 0x10000000  # Fake image base for DbgHelp loading

# ── Load DbgHelp ───────────────────────────────────────────────────────────
hProcess = kernel32.GetCurrentProcess()
dbghelp.SymSetOptions(SYMOPT_UNDNAME | SYMOPT_LOAD_LINES | SYMOPT_DEFERRED_LOADS)
if not dbghelp.SymInitialize(hProcess, PDB_PATH.encode(), False):
    print(f"SymInitialize failed: {kernel32.GetLastError()}")
    sys.exit(1)
dll_size = os.path.getsize(DLL_PATH)
mod_base = dbghelp.SymLoadModuleEx(hProcess, None, DLL_PATH.encode(), None, BASE, dll_size, None, 0)
if mod_base == 0:
    print(f"SymLoadModuleEx failed: {kernel32.GetLastError()}")
    dbghelp.SymCleanup(hProcess)
    sys.exit(1)
print(f"Symbols loaded at 0x{mod_base:x} (fake base)\n")

def resolve(rva):
    """Resolve an RVA (relative to dll_base_in_process) to a symbol name + source."""
    addr = BASE + rva
    sym_buf_size = ctypes.sizeof(SYMBOL_INFO)
    sym_buf = (ctypes.c_byte * sym_buf_size)()
    sym_info = ctypes.cast(sym_buf, ctypes.POINTER(SYMBOL_INFO))
    sym_info[0].SizeOfStruct = ctypes.sizeof(SYMBOL_INFO) - 2048
    sym_info[0].MaxNameLen   = 2048
    displacement = ctypes.c_uint64(0)
    ok = dbghelp.SymFromAddr(hProcess, ctypes.c_uint64(addr), ctypes.byref(displacement), sym_info)
    if not ok:
        return None, None, None
    name = sym_info[0].Name.split(b'\x00', 1)[0].decode(errors='replace')
    disp = displacement.value
    line_info = IMAGEHLP_LINE64()
    line_info.SizeOfStruct = ctypes.sizeof(IMAGEHLP_LINE64)
    ld = ctypes.wintypes.DWORD(0)
    src = None
    if dbghelp.SymGetLineFromAddr64(hProcess, ctypes.c_uint64(addr), ctypes.byref(ld), ctypes.byref(line_info)):
        fn = line_info.FileName
        src = (fn.decode(errors='replace') if fn else "?") + f":{line_info.LineNumber}"
    return name, disp, src

# ── Parse minidump — find thread stack memory ─────────────────────────────
MDMP_SIGNATURE = 0x504D444D  # 'MDMP'
MINIDUMP_STREAM_TYPE = {
    3:  "ThreadListStream",
    4:  "ModuleListStream",
    6:  "ExceptionStream",
    10: "MemoryListStream",
}

with open(DUMP_PATH, "rb") as f:
    raw = f.read()

sig, ver, num_streams, dir_rva = struct.unpack_from("<IIII", raw, 0)
assert sig == MDMP_SIGNATURE, f"Not a minidump! sig=0x{sig:x}"
print(f"Minidump: {num_streams} streams\n")

streams = {}
for i in range(num_streams):
    st_type, data_size, data_rva = struct.unpack_from("<III", raw, dir_rva + i * 12)
    streams[st_type] = (data_rva, data_size)

# ── Get module list (to find flutter_webrtc_plugin.dll base in dump) ─────
plugin_dll_base = None
plugin_dll_size = None
if 4 in streams:
    mod_rva, mod_sz = streams[4]
    (num_modules,) = struct.unpack_from("<I", raw, mod_rva)
    for i in range(num_modules):
        off = mod_rva + 4 + i * 108
        base_addr, mod_size = struct.unpack_from("<QI", raw, off)
        # MINIDUMP_MODULE: ModuleNameRva at offset 20
        (name_offset,) = struct.unpack_from("<I", raw, off + 20)
        # MINIDUMP_STRING: Length (in bytes) then WCHAR buffer
        if name_offset + 4 > len(raw):
            continue
        (name_len,) = struct.unpack_from("<I", raw, name_offset)
        if name_offset + 4 + name_len > len(raw):
            continue
        name_bytes = raw[name_offset + 4 : name_offset + 4 + name_len]
        mod_name = name_bytes.decode("utf-16-le", errors="replace")
        if "flutter_webrtc_plugin" in mod_name:
            plugin_dll_size_actual = mod_size
            plugin_dll_base = base_addr
            print(f"flutter_webrtc_plugin.dll: base=0x{base_addr:016x}, size=0x{mod_size:x}")
            break

if plugin_dll_base is None:
    print("ERROR: flutter_webrtc_plugin.dll not found in module list")
    sys.exit(1)

# ── Get exception thread + stack ─────────────────────────────────────────
crashing_thread_id = None
if 6 in streams:
    ex_rva, _ = streams[6]
    crashing_thread_id = struct.unpack_from("<I", raw, ex_rva)[0]
    print(f"Crashing thread ID: 0x{crashing_thread_id:x}")

# ── Walk thread list to find crashing thread's stack ──────────────────────
thread_stack_start = None
thread_stack_size  = None
if 3 in streams:
    tl_rva, _ = streams[3]
    (num_threads,) = struct.unpack_from("<I", raw, tl_rva)
    for i in range(num_threads):
        off = tl_rva + 4 + i * 48
        tid = struct.unpack_from("<I", raw, off)[0]
        # MINIDUMP_THREAD: ThreadId(4)+SuspendCount(4)+PriorityClass(4)+Priority(4)=16
        #                  Teb(8)=8  total=24 bytes before stack
        # Stack: MINIDUMP_MEMORY_DESCRIPTOR = StartVA(8)+DataSize(4)+Rva(4)=16
        stack_start_va, stack_size, stack_data_rva = struct.unpack_from("<QII", raw, off + 24)
        if tid == crashing_thread_id or (crashing_thread_id is None and i == 0):
            thread_stack_start = stack_start_va
            thread_stack_size  = stack_size
            stack_raw_offset   = stack_data_rva
            print(f"Thread 0x{tid:x}: stack VA=0x{stack_start_va:016x} size=0x{stack_size:x} rawOffset=0x{stack_data_rva:x}")
            break

if thread_stack_start is None:
    print("ERROR: Could not find crashing thread stack")
    sys.exit(1)

# ── Scan stack for return addresses into flutter_webrtc_plugin.dll ────────
plugin_end = plugin_dll_base + dll_size   # use actual DLL file size as approximation

print(f"\nScanning {thread_stack_size // 8} stack slots for addrs in [0x{plugin_dll_base:x}, 0x{plugin_end:x})...\n")

hits = []
for slot in range(0, thread_stack_size, 8):
    if stack_raw_offset + slot + 8 > len(raw):
        break
    val = struct.unpack_from("<Q", raw, stack_raw_offset + slot)[0]
    if plugin_dll_base <= val < plugin_end:
        rva = val - plugin_dll_base
        hits.append((thread_stack_start + slot, rva))

print(f"Found {len(hits)} potential return addresses.\n")
print(f"{'StackAddr':>18}  {'RVA':>10}  Function (source:line)")
print("-" * 100)

seen_funcs = set()
for (sp, rva) in hits:
    name, disp, src = resolve(rva)
    if name:
        # Skip MSVC run-time / std internal noise that's not useful
        if any(skip in name for skip in ['__GSHandlerCheck', 'operator new', 'operator delete',
                                          '__std_terminate', '__declspec',
                                          '__scrt_', 'invoke_main', 'mainCRT']):
            continue
        key = (name, src)
        if key in seen_funcs:
            continue
        seen_funcs.add(key)
        short_name = name[:80]
        print(f"0x{sp:016x}  +0x{rva:06x}  {short_name}")
        if src:
            # Show only the filename, not full path
            src_short = src.replace("C:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\BuildTools\\VC\\Tools\\MSVC\\14.29.30133\\include\\", "STL:")
            src_short = src_short.replace("C:\\rapid_cord\\", "SRC:")
            print(f"{'':>48}→ {src_short}")

dbghelp.SymCleanup(hProcess)
print("\nDone.")
