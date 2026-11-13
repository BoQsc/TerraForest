# SPDX-License-Identifier: 0BSD
"""Render on an owned, non-input Windows desktop; never switch desktops."""
import ctypes as C
from ctypes import wintypes as W
import os
import subprocess
import time
import uuid


class StartupInfo(C.Structure):
    _fields_ = [("cb", W.DWORD), ("reserved", W.LPWSTR), ("desktop", W.LPWSTR),
                ("title", W.LPWSTR), ("x", W.DWORD), ("y", W.DWORD),
                ("width", W.DWORD), ("height", W.DWORD), ("chars_x", W.DWORD),
                ("chars_y", W.DWORD), ("fill", W.DWORD), ("flags", W.DWORD),
                ("show", W.WORD), ("reserved_size", W.WORD), ("reserved_bytes", C.c_void_p),
                ("stdin", W.HANDLE), ("stdout", W.HANDLE), ("stderr", W.HANDLE)]


class ProcessInfo(C.Structure):
    _fields_ = [("process", W.HANDLE), ("thread", W.HANDLE), ("pid", W.DWORD), ("tid", W.DWORD)]


class IsolatedRenderProcess:
    def __init__(self, command, cwd, stdout, **_kwargs):
        if os.name != "nt":raise OSError("Isolated rendered checks currently require Windows")
        import msvcrt
        self.user = C.WinDLL("user32", use_last_error=True)
        self.kernel = C.WinDLL("kernel32", use_last_error=True)
        self.user.CreateDesktopW.argtypes = [W.LPCWSTR, C.c_void_p, C.c_void_p, W.DWORD, W.DWORD, C.c_void_p]
        self.user.CreateDesktopW.restype = W.HANDLE
        self.user.CloseDesktop.argtypes = [W.HANDLE]
        self.kernel.CreateProcessW.argtypes = [W.LPCWSTR, W.LPWSTR, C.c_void_p, C.c_void_p, W.BOOL, W.DWORD, C.c_void_p, W.LPCWSTR, C.POINTER(StartupInfo), C.POINTER(ProcessInfo)]
        self.kernel.CreateProcessW.restype = W.BOOL
        self.kernel.CloseHandle.argtypes = [W.HANDLE]
        self.kernel.GetExitCodeProcess.argtypes = [W.HANDLE, C.POINTER(W.DWORD)]
        self.kernel.WaitForSingleObject.argtypes = [W.HANDLE, W.DWORD]
        self.kernel.TerminateProcess.argtypes = [W.HANDLE, W.UINT]
        self.name = "TerraForestCheck_" + uuid.uuid4().hex
        self.desktop = self.user.CreateDesktopW(self.name, None, None, 0, 0x01FF, None)
        if not self.desktop:raise C.WinError(C.get_last_error())
        self.handle = None
        self.returncode = None
        output = msvcrt.get_osfhandle(stdout.fileno())
        inherited = os.get_handle_inheritable(output)
        try:
            os.set_handle_inheritable(output, True)
            info = StartupInfo();info.cb = C.sizeof(info);info.desktop = self.name
            info.flags = 0x100 | 0x80  # USESTDHANDLES, FORCEOFFFEEDBACK
            info.stdout = output;info.stderr = output
            process = ProcessInfo()
            if not self.kernel.CreateProcessW(str(command[0]), C.create_unicode_buffer(subprocess.list2cmdline(command)), None, None, True, 0x08000000, None, str(cwd), C.byref(info), C.byref(process)):
                raise C.WinError(C.get_last_error())
            self.handle = process.process;self.pid = process.pid
            self.kernel.CloseHandle(process.thread)
        except BaseException:
            self.close();raise
        finally:
            os.set_handle_inheritable(output, inherited)

    def poll(self):
        if self.returncode is None and self.kernel.WaitForSingleObject(self.handle, 0) == 0:
            code = W.DWORD()
            if not self.kernel.GetExitCodeProcess(self.handle, C.byref(code)):raise C.WinError(C.get_last_error())
            self.returncode = code.value
        return self.returncode

    def wait(self, timeout=None):
        deadline = time.monotonic() + timeout if timeout is not None else float("inf")
        while self.poll() is None:
            if time.monotonic() >= deadline:raise subprocess.TimeoutExpired(self.name, timeout)
            time.sleep(.02)
        return self.returncode

    def kill(self):
        if self.poll() is None and not self.kernel.TerminateProcess(self.handle, 1):raise C.WinError(C.get_last_error())

    def close(self):
        if self.handle:self.kernel.CloseHandle(self.handle);self.handle = None
        if self.desktop:self.user.CloseDesktop(self.desktop);self.desktop = None
