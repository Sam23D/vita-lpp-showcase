"""PARAM.SFO writer — a Python port of vitasdk's vita-mksfoex (same layout, same defaults).

build_sfo({"TITLE": ("str", "My App"), "TITLE_ID": ("str", "ABCD00001")})
  -> bytes of a Vita PARAM.SFO with mksfoex's default keys filled in.
build_sfo({...}, defaults=False) -> only the keys you pass (used for PSP-style SFOs).
"""
import struct

PSF_MAGIC = 0x46535000
PSF_VERSION = 0x00000101
TYPE_STR, TYPE_VAL = 2, 4

ATTRIBUTE_NO_COMMUNICATION_ZONE = 0x00008000
ATTRIBUTE2_MEM109 = 0x0000000C

# name -> (kind, value, fixed_total_size or 0); mirrors g_defaults in vita-mksfoex.c
DEFAULTS = {
    "APP_VER": ("str", "01.00", 0),
    "ATTRIBUTE": ("int", ATTRIBUTE_NO_COMMUNICATION_ZONE, 0),
    "ATTRIBUTE2": ("int", ATTRIBUTE2_MEM109, 0),
    "ATTRIBUTE_MINOR": ("int", 0x10, 0),
    "CATEGORY": ("str", "gd", 0),
    "CONTENT_ID": ("str", "HB0001-ABCD99999_00-0000000000000000", 48),
    "GC_RO_SIZE": ("int", 0, 0),
    "GC_RW_SIZE": ("int", 0, 0),
    "PARENTAL_LEVEL": ("int", 0, 0),
    "PSP2_DISP_VER": ("str", "00.000", 0),
    "PSP2_SYSTEM_VER": ("int", 0, 0),
    "REGION_DENY": ("int", 0, 0),
    "SAVEDATA_MAX_SIZE": ("int", 1048576, 0),
    "TITLE_ID": ("str", "ABCD99999", 0),
    "VERSION": ("str", "01.00", 0),
}
FIXED = {"TITLE": 0x80, "STITLE": 52, "CONTENT_ID": 48}


def build_sfo(values: dict, defaults: bool = True) -> bytes:
    entries = {}
    if defaults:
        for k, (kind, v, size) in DEFAULTS.items():
            entries[k] = (kind, v, size)
    for k, (kind, v) in values.items():
        entries[k] = (kind, v, FIXED.get(k, 0))
    if defaults:
        if "STITLE" not in values and "TITLE" in values:
            entries["STITLE"] = ("str", values["TITLE"][1][:51], 52)
        if "CONTENT_ID" not in values:
            tid = entries["TITLE_ID"][1]
            entries["CONTENT_ID"] = ("str", f"HB0001-{tid[:9]}_00-0000000000000000", 48)

    keys = sorted(entries)  # mksfoex sorts keys alphabetically
    index, key_tab, data_tab = b"", b"", b""
    for k in keys:
        kind, v, fixed = entries[k]
        key_off, data_off = len(key_tab), len(data_tab)
        key_tab += k.encode() + b"\0"
        if kind == "int":
            payload, valsize, total, t = struct.pack("<I", v), 4, 4, TYPE_VAL
        else:
            raw = v.encode("utf-8") + b"\0"
            valsize = len(raw)
            total = fixed or ((valsize + 3) & ~3)
            if valsize > total:
                raise ValueError(f"{k} too long ({valsize} > {total})")
            payload, t = raw.ljust(total, b"\0"), TYPE_STR
        index += struct.pack("<HBBIII", key_off, 4, t, valsize, total, data_off)
        data_tab += payload
    key_tab = key_tab.ljust((len(key_tab) + 3) & ~3, b"\0")
    key_ofs = 20 + len(index)
    header = struct.pack("<IIIII", PSF_MAGIC, PSF_VERSION, key_ofs, key_ofs + len(key_tab), len(keys))
    return header + index + key_tab + data_tab


def parse_sfo(blob: bytes) -> dict:
    """Inverse of build_sfo, used by the verifier."""
    magic, _ver, key_ofs, val_ofs, count = struct.unpack_from("<IIIII", blob, 0)
    assert magic == PSF_MAGIC, "bad SFO magic"
    out = {}
    for i in range(count):
        nofs, _align, t, valsize, _total, dofs = struct.unpack_from("<HBBIII", blob, 20 + i * 16)
        name = blob[key_ofs + nofs: blob.index(b"\0", key_ofs + nofs)].decode()
        raw = blob[val_ofs + dofs: val_ofs + dofs + valsize]
        out[name] = struct.unpack("<I", raw)[0] if t == TYPE_VAL else raw.rstrip(b"\0").decode()
    return out
