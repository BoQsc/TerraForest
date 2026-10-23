# SPDX-License-Identifier: 0BSD
"""Interrupt the actual generator child using a verified Windows process handle."""
import ctypes
from ctypes import wintypes as W
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid
from run import ROOT,parse_args
from play_checkpoint import revision_metadata

class ProcessEntry(ctypes.Structure):
    _fields_=[('size',W.DWORD),('usage',W.DWORD),('pid',W.DWORD),('heap',ctypes.c_size_t),('module',W.DWORD),('threads',W.DWORD),('parent',W.DWORD),('priority',W.LONG),('flags',W.DWORD),('exe',W.WCHAR*260)]

class ProcessHandle:
    def __init__(self,pid,parent,engine):
        self.api=ctypes.WinDLL('kernel32',use_last_error=True)
        self.api.OpenProcess.argtypes=[W.DWORD,W.BOOL,W.DWORD];self.api.OpenProcess.restype=W.HANDLE
        self.api.CloseHandle.argtypes=[W.HANDLE]
        self.api.WaitForSingleObject.argtypes=[W.HANDLE,W.DWORD];self.api.WaitForSingleObject.restype=W.DWORD
        self.api.TerminateProcess.argtypes=[W.HANDLE,W.UINT];self.api.TerminateProcess.restype=W.BOOL
        self.api.QueryFullProcessImageNameW.argtypes=[W.HANDLE,W.DWORD,W.LPWSTR,ctypes.POINTER(W.DWORD)];self.api.QueryFullProcessImageNameW.restype=W.BOOL
        self.api.CreateToolhelp32Snapshot.argtypes=[W.DWORD,W.DWORD];self.api.CreateToolhelp32Snapshot.restype=W.HANDLE
        self.api.Process32FirstW.argtypes=[W.HANDLE,ctypes.POINTER(ProcessEntry)];self.api.Process32FirstW.restype=W.BOOL
        self.api.Process32NextW.argtypes=[W.HANDLE,ctypes.POINTER(ProcessEntry)];self.api.Process32NextW.restype=W.BOOL
        self.handle=self.api.OpenProcess(0x100000|0x1000|1,False,pid)
        if not self.handle:raise ctypes.WinError(ctypes.get_last_error())
        try:
            image=ctypes.create_unicode_buffer(32768);length=W.DWORD(len(image))
            if not self.api.QueryFullProcessImageNameW(self.handle,0,image,ctypes.byref(length)):raise ctypes.WinError(ctypes.get_last_error())
            snapshot=self.api.CreateToolhelp32Snapshot(2,0)
            if snapshot in (None,ctypes.c_void_p(-1).value):raise ctypes.WinError(ctypes.get_last_error())
            actual_parent=None
            try:
                entry=ProcessEntry();entry.size=ctypes.sizeof(entry)
                more=self.api.Process32FirstW(snapshot,ctypes.byref(entry))
                while more:
                    if entry.pid==pid:actual_parent=entry.parent;break
                    more=self.api.Process32NextW(snapshot,ctypes.byref(entry))
            finally:self.api.CloseHandle(snapshot)
            if actual_parent!=parent or Path(image.value).resolve()!=engine.resolve():raise RuntimeError('Child identity/parent does not match the owned coordinator')
            self.identity=dict(pid=pid,parent=actual_parent,image=image.value)
        except BaseException:self.close();raise
    def alive(self):return self.api.WaitForSingleObject(self.handle,0)==258
    def terminate(self):
        if self.alive() and not self.api.TerminateProcess(self.handle,97):raise ctypes.WinError(ctypes.get_last_error())
    def close(self):
        if self.handle:self.api.CloseHandle(self.handle);self.handle=None

def read_json(path):
    try:
        if path.stat().st_size>256*1024:return {}
        data=json.loads(path.read_text(encoding='utf-8'))
        return data if isinstance(data,dict) else {}
    except (OSError,ValueError):return {}

def main():
    if sys.platform!='win32':raise RuntimeError('This process-handle qualification targets Windows')
    args,_=parse_args();engine=Path(args.godot).resolve()
    slot='interrupted_'+uuid.uuid4().hex[:16]
    folder=ROOT/'reports/generation_interruption'/slot;folder.mkdir(parents=True)
    worlds=Path(os.environ['APPDATA'])/'Godot/app_userdata/TerraForest/worlds'
    root=worlds/(slot+'.trw')
    report=dict(slot=slot,scope='Actual production child terminated after intermediate checkpoints; same public name is regenerated through the real coordinator. Windows process handles verify liveness, parent and executable. Not physical power-loss or partial-bake resume.',**revision_metadata())
    def start(name):
        target=folder/name;target.mkdir()
        command=[str(engine),'--headless','--path',str(ROOT),'--log-file',str(target/'engine.log'),'--script','res://addons/world_runtime/generation_job.gd','--','--destination='+slot,'--seed=1703','--generator=19','--settlement-layout=connected','--status-file='+str(target/'status.json'),'--cancel-file='+str(target/'cancel'),'--capture-generation-ui']
        stream=(target/'console.log').open('w',encoding='utf-8')
        process=subprocess.Popen(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        return target,command,stream,process
    def child_for(process,status):
        source=Path(status.get('report',''))
        metadata=read_json(source/'run.json')
        stage=metadata.get('stage','');phases=metadata.get('phases',[])
        if metadata.get('destination')!=slot or not re.fullmatch(r'combined_stage_[0-9a-f]{32}',stage) or not phases:return None,None
        if '--world-slot='+stage not in phases[0].get('arguments',[]):raise RuntimeError('Child arguments do not match owned staging')
        return ProcessHandle(int(phases[0]['pid']),process.pid,engine),stage
    active=None;process=None;stream=None
    try:
        target,command,stream,process=start('interrupted');report['first_command']=command
        deadline=time.monotonic()+30;stage=None;observed=0
        while process.poll() is None and time.monotonic()<deadline:
            status=read_json(target/'status.json')
            if active is None:active,stage=child_for(process,status)
            if active:
                observed=len(list((worlds/(stage+'.trw.terrain')).glob('*.tindex')))
                if active.alive() and 3<=observed<7:break
                if not active.alive():raise RuntimeError('Generator child finished before the interruption point')
            time.sleep(.008)
        if not active or not active.alive() or not 3<=observed<7:raise RuntimeError('No confirmed intermediate bake reached')
        report['terminated_child']=active.identity;report['observed_checkpoints']=observed;report['interrupted_stage']=stage
        active.terminate();process.wait(timeout=15)
        status=read_json(target/'status.json');report['interrupted_status']=status
        if status.get('state')!='failed' or root.exists():raise RuntimeError('Interrupted world was published or not reported failed')
        active.close();active=None;stream.close();stream=None
        inspect_command=[str(engine),'--headless','--path',str(ROOT),'--script','res://tests/generation_interruption_inspect.gd','--','--owned-stage='+stage,'--inspection-output='+str(folder/'inspection.json')]
        inspected=subprocess.run(inspect_command,cwd=ROOT,capture_output=True,text=True,timeout=20,creationflags=subprocess.CREATE_NO_WINDOW)
        (folder/'inspection.log').write_text(inspected.stdout+inspected.stderr,encoding='utf-8');report['inspection']=read_json(folder/'inspection.json')
        if inspected.returncode:raise RuntimeError('Checkpoint inspection process failed; see inspection.log')
        if not report['inspection'].get('ok'):raise RuntimeError('Completed private checkpoints did not survive')
        target,command,stream,process=start('regenerated');report['regeneration_command']=command
        deadline=time.monotonic()+130;observations=[];previous={}
        while process.poll() is None and time.monotonic()<deadline:
            status=read_json(target/'status.json')
            if active is None:active,_=child_for(process,status)
            progress=read_json(Path(status.get('report',''))/'creating_progress.json')
            record={key:progress.get(key) for key in ['stage','completed','total','details']}
            if record!=previous and len(observations)<256:observations.append(record);previous=record
            time.sleep(.05)
        if process.poll() is None:raise RuntimeError('Regeneration timed out')
        status=read_json(target/'status.json');metadata=read_json(Path(status.get('report',''))/'run.json')
        report.update(regenerated_status=status,regeneration=metadata,progress=observations)
        if process.returncode or status.get('state')!='ready' or not root.exists() or metadata.get('stage')==stage or not metadata.get('validation',{}).get('ok'):raise RuntimeError('Same-name regeneration did not complete verification/publication')
        report['canonical_sha256']=hashlib.sha256(root.read_bytes()).hexdigest();report['passed']=True
    except BaseException as error:
        report['passed']=False;report['error']=repr(error)
        raise
    finally:
        if active:
            active.terminate();active.close()
        if process and process.poll() is None:process.terminate();process.wait(timeout=10)
        if stream:stream.close()
        (folder/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        (ROOT/'reports/generation_interruption.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        print('GENERATION_INTERRUPTION passed=',report.get('passed',False),' slot=',slot,flush=True)

if __name__=='__main__':main()
