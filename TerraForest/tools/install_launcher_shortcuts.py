# SPDX-License-Identifier: 0BSD
"""Install Windows desktop links to the Godot launcher (no runtime shell)."""
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import shutil
import uuid

ROOT = Path(__file__).resolve().parents[1]


def install():
    if os.name != "nt":
        raise SystemExit("This shortcut installer is Windows-only. Launch Godot with --path Launcher on other systems.")
    from development_storage import admit
    admit(report_bytes=1024 * 1024, world_bytes=0)
    output = ROOT / "reports/launcher_generation/shortcuts"
    output.mkdir(parents=True, exist_ok=True)
    ole = ctypes.OleDLL("ole32")
    ole.CoInitialize(None)
    def guid(text):
        return (ctypes.c_byte * 16).from_buffer_copy(uuid.UUID(text).bytes_le)
    def call(pointer, index, args, *values):
        address = ctypes.cast(pointer, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents[index]
        return ctypes.WINFUNCTYPE(ctypes.HRESULT, ctypes.c_void_p, *args)(address)(pointer, *values)
    shell_id = guid("00021401-0000-0000-c000-000000000046")
    link_id = guid("000214f9-0000-0000-c000-000000000046")
    persist_id = guid("0000010b-0000-0000-c000-000000000046")
    # Resolve the real Desktop known folder, including redirected desktops.
    desktop_id = guid("b4bfcc3a-db2c-424c-b029-7fe99a87c641")
    path = ctypes.c_wchar_p()
    ctypes.OleDLL("shell32").SHGetKnownFolderPath(ctypes.byref(desktop_id), 0, None, ctypes.byref(path))
    desktop = Path(path.value)
    ole.CoTaskMemFree(path)
    records = []
    try:
        for name, continuing in [("TerraForest", False), ("TerraForest Last World", True)]:
            destination = desktop / (name + ".lnk")
            backup = output / (name + ".original.lnk")
            if destination.exists() and not backup.exists():
                shutil.copy2(destination, backup)
            link = ctypes.c_void_p()
            ole.CoCreateInstance(ctypes.byref(shell_id), None, 1, ctypes.byref(link_id), ctypes.byref(link))
            persist = ctypes.c_void_p()
            try:
                call(link, 0, [ctypes.c_void_p, ctypes.c_void_p], ctypes.byref(persist_id), ctypes.byref(persist))
                target = str(ROOT / "TerraForest.exe")
                arguments = '--path "' + str(ROOT.parent / "Launcher") + '" --' + (' --continue-last' if continuing else '')
                for method, value in [(20, target), (9, str(ROOT)), (11, arguments), (7, "Prepare current TerraForest resources and launch with Godot")]:
                    call(link, method, [wintypes.LPCWSTR], value)
                call(link, 17, [wintypes.LPCWSTR, ctypes.c_int], target, 0)
                call(persist, 6, [wintypes.LPCWSTR, wintypes.BOOL], str(destination), True)
                # Verify the persisted link, not just our in-memory object.
                call(persist, 5, [wintypes.LPCWSTR, wintypes.DWORD], str(destination), 0)
                actual_target = ctypes.create_unicode_buffer(32768)
                actual_args = ctypes.create_unicode_buffer(32768)
                call(link, 3, [wintypes.LPWSTR, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD], actual_target, 32768, None, 0)
                call(link, 10, [wintypes.LPWSTR, ctypes.c_int], actual_args, 32768)
                if actual_target.value != target or actual_args.value != arguments:
                    raise RuntimeError("Shortcut verification failed: " + str(destination))
                records.append(dict(path=str(destination), target=target, arguments=arguments, backup=str(backup)))
            finally:
                if persist.value:call(persist, 2, [])
                if link.value:call(link, 2, [])
    finally:
        ole.CoUninitialize()
    (output / "installed.json").write_text(json.dumps(records, indent=2))
    print("Verified desktop shortcuts: " + ", ".join(row["path"] for row in records))


if __name__ == "__main__":
    install()
