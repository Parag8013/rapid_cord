"""
Use Windows DbgHelp API to resolve symbol names from flutter_webrtc_plugin.pdb
for the crash offsets identified from the minidump.
"""
import ctypes
import ctypes.wintypes
import os
import sys

# ── Constants ──────────────────────────────────────────────────────────────
SYMOPT_UNDNAME          = 0x00000002
SYMOPT_DEFERRED_LOADS   = 0x00000004
SYMOPT_LOAD_LINES       = 0x00000010
SYMOPT_OMAP_FIND_NEAREST = 0x00000020

# ── Structs ────────────────────────────────────────────────────────────────
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

# ── Setup ──────────────────────────────────────────────────────────────────
dbghelp = ctypes.WinDLL("dbghelp.dll")
kernel32 = ctypes.WinDLL("kernel32.dll")

# Crash offsets from minidump analysis (relative to DLL image base)
# The DLL is a PE; RVA = file_offset_ish but we use the base address we choose.
CRASH_OFFSETS = [
    0x1dc66,    # ← direct __report_gsfailure caller (the function with overflow)
    0x42af4,    # ← called the crashing function
    0x9f25,     # ← outermost plugin frame
    0x2ad2f,
    0x40871,
    0x194490,
    0x196d30,
    0x196c30,
]

DLL_PATH = r"C:\rapid_cord\rapid_cord_flutter\build\windows\x64\plugins\flutter_webrtc\Debug\flutter_webrtc_plugin.dll"
PDB_PATH = r"C:\rapid_cord\rapid_cord_flutter\build\windows\x64\plugins\flutter_webrtc\Debug"

# We load the DLL symbols at a fake base address to make RVA + base = address
BASE = 0x10000000

# Get current process handle
hProcess = kernel32.GetCurrentProcess()

# Set symbol options
dbghelp.SymSetOptions(SYMOPT_UNDNAME | SYMOPT_LOAD_LINES | SYMOPT_DEFERRED_LOADS)

# Initialize symbol handler
if not dbghelp.SymInitialize(hProcess, PDB_PATH.encode(), False):
    print(f"SymInitialize failed: {kernel32.GetLastError()}")
    sys.exit(1)

print(f"Symbol handler initialized. PDB search path: {PDB_PATH}")

# Load the module (DLL) — we specify the PDB path, fake base, real DLL size
dll_size = os.path.getsize(DLL_PATH)
mod_base = dbghelp.SymLoadModuleEx(
    hProcess,           # hProcess
    None,               # hFile (null = use file path)
    DLL_PATH.encode(),  # ImageName
    None,               # ModuleName
    BASE,               # BaseOfDll (fake, consistent base)
    dll_size,           # DllSize
    None,               # Data
    0,                  # Flags
)

if mod_base == 0:
    err = kernel32.GetLastError()
    print(f"SymLoadModuleEx failed. Error: {err}")
    dbghelp.SymCleanup(hProcess)
    sys.exit(1)

print(f"Module loaded at fake base 0x{mod_base:016x}\n")

# ── Resolve each offset ────────────────────────────────────────────────────
sym_buf_size = ctypes.sizeof(SYMBOL_INFO)
sym_buf = (ctypes.c_byte * sym_buf_size)()
sym_info = ctypes.cast(sym_buf, ctypes.POINTER(SYMBOL_INFO))
sym_info[0].SizeOfStruct = ctypes.sizeof(SYMBOL_INFO) - 2048  # without Name array
sym_info[0].MaxNameLen = 2048

print(f"{'Offset':>12}  {'Function'}")
print("-" * 80)

for off in CRASH_OFFSETS:
    addr = BASE + off
    displacement = ctypes.c_uint64(0)

    # Reset the struct
    sym_info[0].SizeOfStruct = ctypes.sizeof(SYMBOL_INFO) - 2048
    sym_info[0].MaxNameLen = 2048
    sym_info[0].Name = b'\x00' * 2048

    ok = dbghelp.SymFromAddr(
        hProcess,
        ctypes.c_uint64(addr),
        ctypes.byref(displacement),
        sym_info,
    )

    if ok:
        name = sym_info[0].Name.split(b'\x00', 1)[0].decode(errors='replace')
        disp = displacement.value
        print(f"+0x{off:06x}      {name}  (+0x{disp:x})")
    else:
        err = kernel32.GetLastError()
        print(f"+0x{off:06x}      <unresolved, error={err}>")

    # Try to get line info
    line = IMAGEHLP_LINE64()
    line.SizeOfStruct = ctypes.sizeof(IMAGEHLP_LINE64)
    line_disp = ctypes.wintypes.DWORD(0)
    if dbghelp.SymGetLineFromAddr64(hProcess, ctypes.c_uint64(addr), ctypes.byref(line_disp), ctypes.byref(line)):
        fname = line.FileName.decode(errors='replace') if line.FileName else "?"
        print(f"             → {fname}:{line.LineNumber}")

print()
dbghelp.SymCleanup(hProcess)
print("Done.")
