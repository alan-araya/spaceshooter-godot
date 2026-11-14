"""Troca o ícone de um .exe do Windows pelo icon.ico do projeto (API UpdateResource, sem rcedit).

    python -I tools/set_exe_icon.py <caminho do .exe> [icon.ico]

Substitui o grupo de ícones que já existe no executável (mesmo nome e idioma), então o Explorer, a barra de
tarefas e o atalho passam a mostrar o ícone do jogo. Só Windows.
"""
import ctypes
import struct
import sys
from ctypes import wintypes
from pathlib import Path

RT_ICON = 3
RT_GROUP_ICON = 14
LOAD_LIBRARY_AS_DATAFILE = 0x2

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
k32.LoadLibraryExW.restype = wintypes.HMODULE
k32.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
k32.FreeLibrary.argtypes = [wintypes.HMODULE]
k32.BeginUpdateResourceW.restype = wintypes.HANDLE
k32.BeginUpdateResourceW.argtypes = [wintypes.LPCWSTR, wintypes.BOOL]
k32.UpdateResourceW.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD,
                                ctypes.c_void_p, wintypes.DWORD]
k32.EndUpdateResourceW.argtypes = [wintypes.HANDLE, wintypes.BOOL]

ENUM_NAME = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
ENUM_LANG = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p,
                               wintypes.WORD, ctypes.c_void_p)
k32.EnumResourceNamesW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ENUM_NAME, ctypes.c_void_p]
k32.EnumResourceLanguagesW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p, ENUM_LANG,
                                       ctypes.c_void_p]


def _name(ptr) -> int | str:
    """Nome de recurso: inteiro (MAKEINTRESOURCE) ou texto."""
    return ptr if ptr < 0x10000 else ctypes.wstring_at(ptr)


def _ptr(name):
    return ctypes.c_void_p(name) if isinstance(name, int) else ctypes.c_wchar_p(name)


def existing(exe: str):
    """(grupos de ícone [(nome, idioma)], ids de RT_ICON) do executável."""
    h = k32.LoadLibraryExW(exe, None, LOAD_LIBRARY_AS_DATAFILE)
    if not h:
        raise OSError(ctypes.get_last_error(), "não abriu " + exe)
    groups, icons = [], []
    try:
        def on_lang(_h, _t, name, lang, _p, out):
            out.append((name, lang))
            return True

        def collect(rtype, out):
            def on_name(hm, _t, name, _p):
                n = _name(name)
                cb = ENUM_LANG(lambda a, b, c, lang, d: on_lang(a, b, n, lang, d, out))
                k32.EnumResourceLanguagesW(hm, ctypes.c_void_p(rtype), _ptr(n), cb, None)
                return True
            k32.EnumResourceNamesW(h, ctypes.c_void_p(rtype), ENUM_NAME(on_name), None)

        collect(RT_GROUP_ICON, groups)
        collect(RT_ICON, icons)
    finally:
        k32.FreeLibrary(h)
    return groups, icons


def read_ico(path: Path):
    data = path.read_bytes()
    _, kind, count = struct.unpack_from("<HHH", data, 0)
    if kind != 1:
        raise ValueError("não é um .ico")
    out = []
    for i in range(count):
        w, h, colors, _, planes, bpp, size, offset = struct.unpack_from("<BBBBHHII", data, 6 + 16 * i)
        out.append(((w, h, colors, planes, bpp, size), data[offset:offset + size]))
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    exe = str(Path(sys.argv[1]).resolve())
    ico = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "icon.ico"
    images = read_ico(ico)
    groups, icons = existing(exe)
    group_name, lang = groups[0] if groups else (1, 1033)
    first_id = 1
    h = k32.BeginUpdateResourceW(exe, False)
    if not h:
        raise OSError(ctypes.get_last_error(), "BeginUpdateResource")
    ok = False
    try:
        # apaga os ícones antigos (senão ficam órfãos no arquivo)
        for name, l in icons:
            k32.UpdateResourceW(h, ctypes.c_void_p(RT_ICON), _ptr(name), l, None, 0)
        for name, l in groups:
            if (name, l) != (group_name, lang):
                k32.UpdateResourceW(h, ctypes.c_void_p(RT_GROUP_ICON), _ptr(name), l, None, 0)
        grp = struct.pack("<HHH", 0, 1, len(images))
        for i, ((w, hh, colors, planes, bpp, size), blob) in enumerate(images):
            buf = ctypes.create_string_buffer(blob, len(blob))
            if not k32.UpdateResourceW(h, ctypes.c_void_p(RT_ICON), ctypes.c_void_p(first_id + i), lang,
                                       buf, len(blob)):
                raise OSError(ctypes.get_last_error(), "UpdateResource RT_ICON")
            grp += struct.pack("<BBBBHHIH", w, hh, colors, 0, planes, bpp, size, first_id + i)
        gbuf = ctypes.create_string_buffer(grp, len(grp))
        if not k32.UpdateResourceW(h, ctypes.c_void_p(RT_GROUP_ICON), _ptr(group_name), lang, gbuf, len(grp)):
            raise OSError(ctypes.get_last_error(), "UpdateResource RT_GROUP_ICON")
        ok = True
    finally:
        if not k32.EndUpdateResourceW(h, not ok):
            raise OSError(ctypes.get_last_error(), "EndUpdateResource")
    print(f"{exe}: {len(images)} tamanhos no grupo {group_name!r} (idioma {lang}); "
          f"{len(icons)} ícones antigos removidos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
