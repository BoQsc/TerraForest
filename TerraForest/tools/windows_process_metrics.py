"""Read Windows cumulative CPU times and process memory without installing a monitor."""
# SPDX-License-Identifier: 0BSD
import ctypes
from ctypes import wintypes
import time


class MemoryCounters(ctypes.Structure):
    _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD)] + [
        (name, ctypes.c_size_t) for name in ['PeakWorkingSetSize', 'WorkingSetSize',
        'QuotaPeakPagedPoolUsage', 'QuotaPagedPoolUsage', 'QuotaPeakNonPagedPoolUsage',
        'QuotaNonPagedPoolUsage', 'PagefileUsage', 'PeakPagefileUsage', 'PrivateUsage']]


def ticks(value):
    return (value.dwHighDateTime << 32) | value.dwLowDateTime


class ProcessMetrics:
    def __init__(self, pid):
        self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        self.psapi = ctypes.WinDLL('psapi', use_last_error=True)
        self.kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        self.kernel.OpenProcess.restype = wintypes.HANDLE
        self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        self.kernel.CloseHandle.restype = wintypes.BOOL
        file_pointer = ctypes.POINTER(wintypes.FILETIME)
        self.kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [file_pointer]*4
        self.kernel.GetProcessTimes.restype = wintypes.BOOL
        self.kernel.GetSystemTimes.argtypes = [file_pointer]*3
        self.kernel.GetSystemTimes.restype = wintypes.BOOL
        self.kernel.GetActiveProcessorCount.argtypes = [wintypes.WORD]
        self.kernel.GetActiveProcessorCount.restype = wintypes.DWORD
        self.psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD]
        self.psapi.GetProcessMemoryInfo.restype = wintypes.BOOL
        self.logical_processors = self.kernel.GetActiveProcessorCount(0xffff)
        self.handle = self.kernel.OpenProcess(0x0400 | 0x0010, False, pid)
        if not self.handle:
            raise ctypes.WinError(ctypes.get_last_error())
        self.previous = None

    def close(self):
        if self.handle:
            self.kernel.CloseHandle(self.handle)
            self.handle = None

    def sample(self):
        created, exited, kernel, user = [wintypes.FILETIME() for _ in range(4)]
        idle, system_kernel, system_user = [wintypes.FILETIME() for _ in range(3)]
        if not self.kernel.GetProcessTimes(self.handle, *[ctypes.byref(v) for v in (created, exited, kernel, user)]):
            raise ctypes.WinError(ctypes.get_last_error())
        if not self.kernel.GetSystemTimes(*[ctypes.byref(v) for v in (idle, system_kernel, system_user)]):
            raise ctypes.WinError(ctypes.get_last_error())
        memory = MemoryCounters()
        memory.cb = ctypes.sizeof(memory)
        if not self.psapi.GetProcessMemoryInfo(self.handle, ctypes.byref(memory), memory.cb):
            raise ctypes.WinError(ctypes.get_last_error())
        current = {'monotonic_s': time.perf_counter(), 'utc_unix_s': time.time(),
                   'process_cpu_100ns': ticks(kernel)+ticks(user), 'system_idle_100ns': ticks(idle),
                   'system_total_100ns': ticks(system_kernel)+ticks(system_user)}
        result = {**current, 'logical_processors': self.logical_processors,
                  'working_set_bytes': memory.WorkingSetSize, 'private_commit_bytes': memory.PrivateUsage}
        if self.previous:
            elapsed = current['monotonic_s']-self.previous['monotonic_s']
            cpu_s = (current['process_cpu_100ns']-self.previous['process_cpu_100ns'])/10_000_000
            total = current['system_total_100ns']-self.previous['system_total_100ns']
            idle_delta = current['system_idle_100ns']-self.previous['system_idle_100ns']
            if elapsed > 0 and total > 0 and self.logical_processors:
                result.update(interval_s=elapsed, interval_start_utc_unix_s=self.previous['utc_unix_s'],
                              process_cpu_ms=cpu_s*1000,
                              process_one_core_percent=100*cpu_s/elapsed,
                              process_machine_percent=100*cpu_s/elapsed/self.logical_processors,
                              system_busy_percent=100*(total-idle_delta)/total)
        self.previous = current
        return result
