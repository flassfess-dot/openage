"""Read-only Windows process CPU/memory sampling for arena diagnostics."""
import os,time

class ProcessMetrics:
    def __enter__(self): return self
    def __exit__(self,*_): self.close()
    def __init__(self,pid):
        self.started=time.monotonic(); self.handle=None; self.samples=[]; self.count=0
        self.peak_working_set=0; self.peak_private=0; self.cpu_seconds=None; self.error=None
        if os.name!='nt': self.error='Windows process counters unavailable'; return
        try:
            import ctypes as c
            from ctypes import wintypes as w
            class Counters(c.Structure):
                _fields_=[('cb',w.DWORD),('faults',w.DWORD)]+[(name,c.c_size_t) for name in (
                    'peak_working_set','working_set','peak_paged','paged','peak_nonpaged','nonpaged','pagefile','peak_pagefile','private')]
            self.c=c; self.Counters=Counters
            self.kernel=c.WinDLL('kernel32',use_last_error=True); self.psapi=c.WinDLL('psapi',use_last_error=True)
            self.kernel.OpenProcess.argtypes=[w.DWORD,w.BOOL,w.DWORD]; self.kernel.OpenProcess.restype=w.HANDLE
            self.kernel.CloseHandle.argtypes=[w.HANDLE]; self.kernel.CloseHandle.restype=w.BOOL
            self.kernel.GetProcessTimes.argtypes=[w.HANDLE,*([c.POINTER(w.FILETIME)]*4)]; self.kernel.GetProcessTimes.restype=w.BOOL
            self.psapi.GetProcessMemoryInfo.argtypes=[w.HANDLE,c.POINTER(Counters),w.DWORD]; self.psapi.GetProcessMemoryInfo.restype=w.BOOL
            self.Filetime=w.FILETIME
            self.handle=self.kernel.OpenProcess(0x1000|0x0010,False,pid)
            if not self.handle: self.error='OpenProcess failed: '+str(c.get_last_error())
        except (OSError,AttributeError) as exc: self.error=str(exc)

    def sample(self,retain=False):
        if not self.handle: return
        c=self.c; values=[self.Filetime() for _ in range(4)]
        if self.kernel.GetProcessTimes(self.handle,*(c.byref(value) for value in values)):
            ticks=lambda v:(int(v.dwHighDateTime)<<32)|int(v.dwLowDateTime)
            self.cpu_seconds=(ticks(values[2])+ticks(values[3]))/10_000_000
        data=self.Counters(); data.cb=c.sizeof(data)
        if not self.psapi.GetProcessMemoryInfo(self.handle,c.byref(data),c.sizeof(data)): return
        self.count+=1; self.peak_working_set=max(self.peak_working_set,int(data.peak_working_set))
        self.peak_private=max(self.peak_private,int(data.private),int(data.peak_pagefile))
        if retain and len(self.samples)<4096:
            self.samples.append({'seconds':round(time.monotonic()-self.started,3),'working_set_bytes':int(data.working_set),
                'private_bytes':int(data.private),'cpu_seconds':self.cpu_seconds})

    def close(self):
        # Exit reclaims the address space; that drop is not an in-match memory
        # trend. Still collect final CPU time and kernel peak counters.
        self.sample(retain=False)
        if self.handle: self.kernel.CloseHandle(self.handle); self.handle=None

    def report(self):
        return {'available':self.count>0,'error':self.error,'samples':self.count,'cpu_seconds':self.cpu_seconds,
            'peak_working_set_bytes':self.peak_working_set if self.count else None,
            'peak_private_bytes':self.peak_private if self.count else None,'memory_trend':self.samples}
