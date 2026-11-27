# SPDX-License-Identifier: 0BSD
"""Admitted full-frame raw-pixel counterfactual, with bounded review videos."""
import hashlib
import json
import socket
import struct
import subprocess
import sys
import threading
import uuid
from pathlib import Path
from PIL import Image, ImageChops, ImageFilter, ImageStat

ROOT = Path(__file__).resolve().parents[1]
FFMPEG = Path.home() / 'AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0.2-full_build/bin/ffmpeg.exe'
CAP = 16 * 2**20
METADATA_CAP = 2**20

def check_output_budget(output):
    files=[p for p in output.iterdir() if p.is_file()]
    if sum(p.stat().st_size for p in files if p.suffix in ('.mp4','.png'))>CAP:
        raise ValueError('Full-frame media cap exceeded')
    if sum(p.stat().st_size for p in files)>20*2**20:
        raise ValueError('Admitted total report cap exceeded')

def receive(sock, size):
    data = bytearray()
    while len(data) < size:
        part = sock.recv(size - len(data))
        if not part: raise EOFError('Incomplete raw frame')
        data.extend(part)
    return bytes(data)

def count(mask):
    return sum(mask.histogram()[1:])

def metrics(im):
    lum = im.convert('L', (.2126, .7152, .0722, 0))
    median = lum.filter(ImageFilter.MedianFilter(3))
    low = lum.point(lambda x: 255 if x <= 12 else 0)
    high = lum.point(lambda x: 255 if x >= 243 else 0)
    dark_contrast = ImageChops.subtract(median, lum).point(lambda x: 255 if x >= 24 else 0)
    light_contrast = ImageChops.subtract(lum, median).point(lambda x: 255 if x >= 24 else 0)
    dark = ImageChops.multiply(low, dark_contrast)
    bright = ImageChops.multiply(high, light_contrast)
    speckle = ImageChops.lighter(dark, bright)
    tiles = [count(speckle.crop((x,y,x+160,y+120))) for y in range(0,1080,120) for x in range(0,1920,160)]
    red, green, blue = im.split()
    magenta = ImageChops.multiply(ImageChops.multiply(red.point(lambda x:255 if x>100 else 0),blue.point(lambda x:255 if x>100 else 0)),green.point(lambda x:255 if x<45 else 0))
    yellow = ImageChops.multiply(ImageChops.multiply(red.point(lambda x:255 if x>100 else 0),green.point(lambda x:255 if x>100 else 0)),blue.point(lambda x:255 if x<45 else 0))
    cyan = ImageChops.multiply(ImageChops.multiply(blue.point(lambda x:255 if x>100 else 0),green.point(lambda x:255 if x>100 else 0)),red.point(lambda x:255 if x<45 else 0))
    return dict(mean_luma=ImageStat.Stat(lum).mean[0]/255, low_pixels=count(low),high_pixels=count(high),dark_impulses=count(dark),bright_impulses=count(bright),local_dark_contrast=count(dark_contrast),local_bright_contrast=count(light_contrast),tiles=tiles,negative_witness_pixels=count(magenta),high_witness_pixels=count(yellow),nonfinite_witness_pixels=count(cyan)), speckle

def serve(listener, token, state):
    writers = {}; baseline = {}; rows = []; output = None
    planned_frames = 48
    try:
        listener.settimeout(600)
        with listener.accept()[0] as sock:
            sock.settimeout(90)
            while True:
                length = struct.unpack('<I', receive(sock,4))[0]
                if not 0 < length < 16384: raise ValueError('Invalid metadata size')
                meta = json.loads(receive(sock,length))
                if meta['token'] != token: raise ValueError('Run identity mismatch')
                if meta['kind'] == 'begin':
                    planned_frames=meta['frames']
                    if planned_frames not in (48,192): raise ValueError('Unbounded capture count')
                    output = Path(meta['output']).resolve()
                    if output.parent != (ROOT/'reports/checks').resolve(): raise ValueError('Unowned output')
                    receipt = json.loads((output/'run.json').read_text())
                    if '--lab-run-id='+token not in receipt['command']: raise ValueError('Receipt mismatch')
                    state['output'] = str(output)
                    (output/'run_vegetation_fullframe.py').write_bytes(Path(__file__).read_bytes())
                elif meta['kind'] == 'frame':
                    if meta['bytes'] != 1920*1080*3 or output is None: raise ValueError('Wrong raw frame size')
                    raw = receive(sock,meta['bytes']); case=meta['case']; frame=meta['frame']
                    im = Image.frombytes('RGB',(1920,1080),raw)
                    row, mask = metrics(im)
                    row.update(case=case,frame=frame,sha256=hashlib.sha256(raw).hexdigest(),camera=meta.get('camera'))
                    if case=='baseline': baseline[frame]=raw
                    elif case in ('bounded_edge','bounded_interpolants','baseline_repeat'):
                        difference=ImageChops.difference(im,Image.frombytes('RGB',im.size,baseline[frame]))
                        channels=difference.split(); changed=ImageChops.lighter(ImageChops.lighter(channels[0],channels[1]),channels[2])
                        row['changed_pixels']=count(changed)
                        row['mean_absolute_rgb_change']=sum(ImageStat.Stat(difference).mean)/3/255
                    elif case=='no_cover':
                        covered=Image.frombytes('RGB',im.size,baseline[frame]).convert('L',(.2126,.7152,.0722,0))
                        bare=im.convert('L',(.2126,.7152,.0722,0))
                        row['cover_bright_contrast']=count(ImageChops.subtract(covered,bare).point(lambda x:255 if x>=32 else 0))
                        row['cover_dark_contrast']=count(ImageChops.subtract(bare,covered).point(lambda x:255 if x>=32 else 0))
                    rows.append(row)
                    if frame == 24 and case in ('baseline','bounded_interpolants','invalid_witness','no_cover'):
                        im.save(output/f'{case}_{frame}.png')
                        if case=='baseline':mask.save(output/f'impulses_{frame}.png')
                    if case in ('baseline','bounded_edge','bounded_interpolants','gameplay'):
                        if case not in writers:
                            writers[case]=subprocess.Popen([str(FFMPEG),'-v','error','-f','rawvideo','-pixel_format','rgb24','-video_size','1920x1080','-framerate','60','-i','pipe:0','-an','-c:v','libx264','-preset','medium' if case=='gameplay' else 'veryfast','-crf','22' if case=='gameplay' else '18','-pix_fmt','yuv420p','-movflags','+faststart',str(output/(case+'.mp4'))],stdin=subprocess.PIPE)
                        writers[case].stdin.write(raw)
                    check_output_budget(output)
                elif meta['kind']=='end':
                    for writer in writers.values():
                        writer.stdin.close()
                        if writer.wait()!=0: raise RuntimeError('Review encoder failed')
                    writers.clear()
                    expected={'gameplay':planned_frames} if rows and rows[0]['case']=='gameplay' else {**{case:48 for case in ('baseline','bounded_edge','bounded_interpolants','invalid_witness','bounded_witness','interpolant_witness','no_cover')},'baseline_repeat':1}
                    if {case:sum(r['case']==case for r in rows) for case in {r['case'] for r in rows}}!=expected:
                        raise ValueError('Incomplete counterfactual frame inventory')
                    if any([r['frame'] for r in rows if r['case']==case]!=list(range(n)) for case,n in expected.items()):
                        raise ValueError('Repeated, missing or reordered frame identity')
                    if any(r.get('changed_pixels',0)!=0 for r in rows if r['case']=='baseline_repeat'):
                        raise ValueError('Reference repeat differs; causal comparison invalid')
                    summary = {case: {key:sum(r[key] for r in rows if r['case']==case)/sum(r['case']==case for r in rows) for key in ('mean_luma','low_pixels','high_pixels','dark_impulses','bright_impulses','local_dark_contrast','local_bright_contrast','negative_witness_pixels','high_witness_pixels','nonfinite_witness_pixels')} for case in {r['case'] for r in rows}}
                    record=dict(summary=summary,frames=rows,scope='Full viewport, no ROI. Extreme local impulses are a detector, not a guarantee of all flicker. Pair differences use raw RGB; H264 is review only. Legitimate UI/edges may trigger the detector.')
                    payload=json.dumps(record,indent=2)+'\n'
                    if len(payload.encode())>METADATA_CAP: raise ValueError('Full-frame analysis metadata cap exceeded')
                    (output/'analysis.json').write_text(payload)
                    check_output_budget(output)
                    state['summary']=summary
                    sock.sendall(b'\x01'); break
                else: raise ValueError('Unknown message')
                sock.sendall(b'\x01')
    except Exception as error:
        state['error']=repr(error)
        if output is not None:
            (output/'analysis.json').write_text(json.dumps(dict(incomplete=True,error=repr(error),frames=rows),indent=2)+'\n')
    finally:
        for writer in writers.values():
            writer.stdin.close(); writer.wait()

def main():
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gameplay',action='store_true')
    args=parser.parse_args()
    from run_vegetation_lab import active_render_jobs
    jobs=active_render_jobs()
    if isinstance(jobs,dict): jobs=[jobs]
    if any(not job['headless'] for job in jobs): print('Another graphical job is active; no launch.');return 2
    token=uuid.uuid4().hex; state={'other_headless_jobs':jobs,'timing_qualified':False}
    with socket.socket() as listener:
        listener.bind(('127.0.0.1',0)); listener.listen(1)
        worker=threading.Thread(target=serve,args=(listener,token,state),daemon=True);worker.start()
        test='vegetation_gameplay' if args.gameplay else 'vegetation_fullframe'
        command=[sys.executable,str(ROOT/'tools/run_godot_check.py'),test,'--isolated-render','--timeout','600','--require',test.upper()+' failures=0','--','--fullframe-port='+str(listener.getsockname()[1]),'--lab-run-id='+token,'--lab-visual-only']
        result=subprocess.run(command,cwd=ROOT)
        worker.join(timeout=5)
    print(json.dumps(state,indent=2))
    return result.returncode or (1 if 'error' in state or 'summary' not in state else 0)

if __name__=='__main__':sys.exit(main())
