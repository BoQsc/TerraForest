# SPDX-License-Identifier: 0BSD
"""Verify bounded transition packets; compare resident-page counterfactuals."""
import hashlib
import io
import json
import struct
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageStat


def frames(path):
    if path.stat().st_size > 9*2**20:
        raise ValueError('Motion cap exceeded')
    with path.open('rb') as stream:
        while prefix := stream.read(4):
            size = struct.unpack('<I', prefix)[0]
            if not 0 < size < 16384:
                raise ValueError('Invalid metadata size')
            meta = json.loads(stream.read(size))
            size = struct.unpack('<I', stream.read(4))[0]
            if not 0 < size < 2**20:
                raise ValueError('Invalid frame size')
            image = Image.open(io.BytesIO(stream.read(size))).convert('RGB')
            if image.size != (1024,128) or hashlib.sha256(image.tobytes()).hexdigest() != meta['rgb_sha256']:
                raise ValueError('Pixel identity mismatch')
            yield meta, image


def delta(a,b):
    diff = ImageChops.difference(a,b)
    r,g,b = diff.split()
    maximum = ImageChops.lighter(r,ImageChops.lighter(g,b))
    hist = maximum.histogram()
    return dict(rgb_abs_sum=sum(ImageStat.Stat(diff).sum),pixels_over_8=sum(hist[9:]),maximum=max(i for i,n in enumerate(hist) if n))


def analyze(folder):
    folder = Path(folder).resolve()
    receipt = json.loads((folder/'run.json').read_text())
    if not receipt.get('result',{}).get('passed'):
        raise ValueError('Expected completed successful receipt')
    baseline = {}; production = {}; backgrounds = {}; previous = {}; summaries = {}; records = []; seen = {}
    for meta,image in frames(folder/'transition.frames'):
        case=meta['case']; frame=meta['frame']
        if frame != seen.get(case,0): raise ValueError('Nonconsecutive packet')
        seen[case]=frame+1
        row={k:meta[k] for k in ('case','frame','distance_m','selection')}
        row['mean_luma']=ImageStat.Stat(image.convert('L',(.2126,.7152,.0722,0))).mean[0]
        if case in previous: row['step']=delta(image,previous[case])
        previous[case]=image
        if case=='no_cover': backgrounds[frame]=image
        else:
            bare=backgrounds[frame]
            row['object_contrast']=sum(ImageStat.Stat(ImageChops.difference(image,bare)).sum)
            row['object_signed_luma']=ImageStat.Stat(image.convert('L',(.2126,.7152,.0722,0))).sum[0]-ImageStat.Stat(bare.convert('L',(.2126,.7152,.0722,0))).sum[0]
            if case=='source':baseline[frame]=image
            else:row['versus_source']=delta(image,baseline[frame])
            if case=='production':production[frame]=image
            if case=='individual_front':row['versus_production_instances']=delta(image,production[frame])
        if case=='tagged':
            r,g,b=image.split()
            row['red_pixels']=sum(ImageChops.subtract(r,b).histogram()[100:])
            row['blue_pixels']=sum(ImageChops.subtract(b,r).histogram()[100:])
        records.append(row)
    plan=json.loads((folder/'transition.json').read_text())
    expected={k:(1 if k=='repeat' else plan['frame_count']) for k in plan['cases']}
    if seen != expected: raise ValueError('Incomplete controls')
    if records[-1]['versus_source']['maximum']: raise ValueError('Baseline repeat differs')
    for case in expected:
        rows=[r for r in records if r['case']==case]
        steps=sorted((r for r in rows if 'step' in r),key=lambda r:r['step']['rgb_abs_sum'],reverse=True)
        changes=[r for i,r in enumerate(rows) if i and r['selection']!=rows[i-1]['selection']]
        summaries[case]=dict(largest_steps=steps[:8],surface_changes=changes,
            frames_different_from_source=sum(r.get('versus_source',{}).get('maximum',0)>0 for r in rows))
        if case=='individual_front':
            summaries[case]['independent_instance_parity']={
                'max_channel_delta':max(r['versus_production_instances']['maximum'] for r in rows),
                'max_rgb_abs_sum':max(r['versus_production_instances']['rgb_abs_sum'] for r in rows),
                'total_pixels_over_8':sum(r['versus_production_instances']['pixels_over_8'] for r in rows)}
    result=dict(summary=summaries,rows=records,scope='Fixed resident objects, constant population, no streaming/spawn. Raw lossless field strip, exact repeated baseline. Step changes include normal approach motion; paired controls isolate mechanisms. Not a gameplay or timing qualification.')
    data=(json.dumps(result,indent=2)+'\n').encode()
    if len(data)>2**20: raise ValueError('Analysis budget')
    (folder/'transition_analysis.json').write_bytes(data)
    print(json.dumps({case:{'largest_step_distances':[(r['distance_m'],r['step']['rgb_abs_sum']) for r in value['largest_steps'][:4]],'surface_change_distances':[r['distance_m'] for r in value['surface_changes']],'different_from_source':value['frames_different_from_source']} for case,value in summaries.items()},indent=2))


if __name__=='__main__': analyze(sys.argv[1])
