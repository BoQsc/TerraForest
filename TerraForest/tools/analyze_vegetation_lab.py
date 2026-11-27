# SPDX-License-Identifier: 0BSD
"""Report controlled lab observations without automatically approving a solution."""
import argparse
import hashlib
import io
import json
import math
import statistics
import struct
from pathlib import Path
from PIL import Image, ImageFilter, ImageStat

ROOT = Path(__file__).resolve().parents[1]


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[int((len(ordered) - 1) * fraction)] if ordered else None


def paired_windows(report, witness):
    """Keep window observations separate from whole-run environment qualification."""
    if not report.get('cost_settings',{}).get('order','').startswith('ABBA'):
        return []
    rows=report['cost']; result=[]
    if len(rows)%4:raise ValueError('Incomplete ABBA windows')
    for offset in range(0,len(rows),4):
        batch=rows[offset:offset+4];names=[r['case'] for r in batch]
        if names[0]!=names[3] or names[1]!=names[2] or names[0]==names[1]:
            raise ValueError('Invalid ABBA identities')
        start=batch[0]['start_unix_s'];end=batch[-1]['end_unix_s']
        known=bool(witness and witness.get('monitor_started_unix_s') and witness.get('monitor_error') is None)
        overlaps=[o for o in witness['observations'] if start-6<=witness['monitor_started_unix_s']+o['seconds']<=end+6] if known else []
        item=dict(round=offset//4,cases_ABBA=names,start_unix_s=start,end_unix_s=end,
                  other_job_observed_near_window=bool(overlaps) if known else None,
                  scope='Five-second engine-job inventory, six-second window margin; not proof against short or unrelated GPU interference.')
        for key in ('gpu_ms','cpu_ms','draws'):
            medians=[statistics.median(r[key]) for r in batch]
            tails=[percentile(r[key],.95) for r in batch]
            item[key]=dict(medians_ABBA=medians,delta_median=(medians[1]+medians[2]-medians[0]-medians[3])/2,
                           p95_ABBA=tails,delta_p95=(tails[1]+tails[2]-tails[0]-tails[3])/2)
        result.append(item)
    return result


def temporal(row):
    frames = [f['samples'] for f in row['frames']]
    if [f['frame'] for f in row['frames']]!=list(range(32)) or min(map(len, frames), default=0) < 12:
        raise ValueError('Missing complete temporal samples or verified anchors')
    if len({len(f) for f in frames}) != 1:
        raise ValueError('Anchor identities changed during replay')
    if any(not math.isfinite(v) or not 0<=v<=1 for f in frames for v in f):
        raise ValueError('Invalid display luminance: offscreen/extrapolated temporal samples')
    differences = [statistics.mean(abs(a-b) for a,b in zip(previous,current))
                   for previous,current in zip(frames,frames[1:])]
    return dict(mean=statistics.mean(differences), p95=percentile(differences,.95))


def contrast(image):
    image = image.convert('RGB')
    mean = sum(a*b for a,b in zip(ImageStat.Stat(image).mean,(.2126,.7152,.0722)))/255
    luminance = image.convert('L',(.2126,.7152,.0722,0))
    local = luminance.filter(ImageFilter.MedianFilter(5))
    pairs = list(zip(luminance.tobytes(),local.tobytes()))
    return dict(mean_display_luma=mean,
                dark_outliers=sum(b-a>25.5 for a,b in pairs),
                bright_outliers=sum(a>122.4 and a-b>25.5 for a,b in pairs))


def packet(data):
    if len(data)>8*2**20:
        raise ValueError('Lab packet exceeds admitted cap')
    offset = 0
    while offset<len(data):
        parts = []
        for maximum in (4096, 1024*1024):
            if offset+4>len(data):raise ValueError('Truncated lab frame')
            size, = struct.unpack_from('<I',data,offset);offset+=4
            if not 0<size<=min(maximum,len(data)-offset):raise ValueError('Invalid lab frame length')
            parts.append(data[offset:offset+size]);offset+=size
        metadata = json.loads(parts[0])
        with Image.open(io.BytesIO(parts[1])) as image:
            if image.size!=(320,128):raise ValueError('Unexpected lab frame dimensions')
            if 'rgb_sha256' in metadata and hashlib.sha256(image.convert('RGB').tobytes()).hexdigest()!=metadata['rgb_sha256']:
                raise ValueError('Captured pixels changed during encoding or decoding')
            yield metadata,image.convert('RGB')


def summarize(report):
    valid = report.get('fixture_valid') is True and report.get('failures') == 0
    valid &= all(report.get('near_parity',{}).get(name) is True for name in ('filtered_candidate','filtered_optimized'))
    valid &= report.get('field',{}).get('grass_changed_pixels',0)>=128 and len(report.get('field',{}).get('anchors',[]))>=12
    valid &= report.get('field',{}).get('distance_isolated') is True
    results = {}
    invalid_samples=[]
    for row in report['rows']:
        try:metrics=temporal(row)
        except ValueError as error:
            valid=False;metrics=dict(invalid=str(error))
            invalid_samples.append(dict(case=row['case'],path=row['path'],reason=str(error)))
        results.setdefault(row['case'],dict(paths={},cost=[]))['paths'][row['path']]=metrics
        if row.get('fern_frames'):
            try:fern_metrics=temporal(dict(frames=row['fern_frames']))
            except ValueError as error:
                valid=False;fern_metrics=dict(invalid=str(error));invalid_samples.append(dict(case=row['case'],path='fern_'+row['path'],reason=str(error)))
            results[row['case']].setdefault('fern_paths',{})[row['path']]=fern_metrics
        for kind in ('stone','flower'):
            if not row.get(kind+'_frames'):continue
            try:metrics=temporal(dict(frames=row[kind+'_frames']))
            except ValueError as error:
                valid=False;metrics=dict(invalid=str(error));invalid_samples.append(dict(case=row['case'],path=kind+'_'+row['path'],reason=str(error)))
            field=report.get(kind+'_field',{})
            valid &= field.get('distance_isolated') is True and field.get('plants',0)>=4 and len(field.get('anchors',[]))>=12
            results[row['case']].setdefault(kind+'_paths',{})[row['path']]=metrics
    for row in report['cost']:
        results.setdefault(row['case'],dict(paths={},cost=[]))['cost'].append({
            'round':row['round'],
            **{key:dict(median=statistics.median(row[key]),p95=percentile(row[key],.95))
               for key in ('gpu_ms','cpu_ms','draws')}})
    # Subtract the matched species-removal control at each registered source
    # anchor. Background motion/texture is otherwise part of the raw residual.
    for kind in ('stone','flower'):
        for row in report['rows']:
            if not row.get(kind+'_frames'):continue
            removed=next((r for r in report['rows'] if r['case']==kind+'_removed' and r['path']==row['path']),None)
            if not removed or not removed.get(kind+'_frames'):continue
            own=row[kind+'_frames'];base=removed[kind+'_frames']
            if len(own)!=32 or len(base)!=32:continue
            contributions=[[a-b for a,b in zip(f['samples'],g['samples'])] for f,g in zip(own,base)]
            changes=[statistics.mean(abs(a-b) for a,b in zip(previous,current)) for previous,current in zip(contributions,contributions[1:])]
            results[row['case']].setdefault(kind+'_contribution_paths',{})[row['path']]=dict(mean=statistics.mean(changes),p95=percentile(changes,.95),mean_signed_luma=statistics.mean(v for frame in contributions for v in frame),scope='Matched far-only removal difference at identical source anchors; includes true occlusion/wind, not a universal flicker percentage.')
    for path in report['matrix']['paths']:
        reference = [r for r in report['rows'] if r['case']=='reference' and r['path']==path]
        repeated = [r for r in report['rows'] if r['case']=='reference_repeat' and r['path']==path]
        valid &= len(reference)==len(repeated)==1 and reference[0]['hashes']==repeated[0]['hashes']
    for case in report['matrix']['cases']:
        if case['id'] not in results:continue
        row = results[case['id']];row['parent']=case['parent'];row['question']=case['question'];row['change']=case['change']
        parent = results.get(case['parent'])
        if parent:
            for path,metrics in row['paths'].items():
                if 'mean' not in metrics or 'mean' not in parent['paths'][path]:continue
                base = parent['paths'][path]['mean']
                metrics['parent_residual_ratio']=metrics['mean']/base if base>0 else None
    surface_parity = None
    fern_surface_parity = None
    if 'filtered_candidate' in results and 'filtered_optimized' in results:
        surface_parity = all(
            next(r for r in report['rows'] if r['case']=='filtered_candidate' and r['path']==path)['hashes']
            ==next(r for r in report['rows'] if r['case']=='filtered_optimized' and r['path']==path)['hashes']
            for path in report['matrix']['paths'])
    if 'fern_optimized' in results:
        valid &= report.get('fern_field',{}).get('distance_isolated') is True and len(report.get('fern_field',{}).get('anchors',[]))>=12
        fern_surface_parity=all(next(r for r in report['rows'] if r['case']=='fern_early' and r['path']==path)['hashes']==next(r for r in report['rows'] if r['case']=='fern_optimized' and r['path']==path)['hashes'] for path in report['matrix']['paths'])
    return dict(fixture_valid=bool(valid),invalid_temporal_samples=invalid_samples,surface_removal_exact_motion_parity=surface_parity,
                fern_surface_removal_exact_motion_parity=fern_surface_parity,
                near_parity=report['near_parity'],human_approved=False,production_promotion=False,
                cases=results,limitations=[
                    'Registered luminance residual includes wind, silhouette motion and occlusion; it is not a pure flicker percentage.',
                    'Removed-species contributions can overlap; brightness is reported separately from temporal residual.',
                    'Lab camera replay freezes world simulation; physical gameplay and streaming must pass separately.',
                    'Forward/reverse lab GPU windows are observations; concurrent jobs or drift invalidate cost qualification.',
                    'Images and motion need human review; no score automatically approves a production change.'])


def analyze(folder, review_case=None):
    folder = folder.resolve()
    receipt = json.loads((folder/'run.json').read_text())
    result = receipt.get('result',{})
    if (not folder.is_relative_to(ROOT/'reports/checks')
            or 'res://tests/vegetation_lab.gd' not in receipt.get('command',[])
            or '--check-evidence-dir='+str(folder) not in receipt['command']
            or result.get('exit_code') is None
            or result.get('development_storage',{}).get('planned_report_bytes')!=20*2**20):
        raise ValueError('Expected completed admitted lab receipt')
    report = json.loads((folder/'lab.json').read_text())
    summary = summarize(report)
    summary['runner_passed']=result.get('passed',False)
    summary['fixture_valid'] &= summary['runner_passed']
    witness_path=folder/'interference.json'
    witness=json.loads(witness_path.read_text()) if witness_path.is_file() else None
    summary['gpu_environment_observation_valid']=bool(witness and not witness['overlap_observed'] and witness['monitor_error'] is None)
    summary['gpu_environment']=witness
    summary['paired_windows']=paired_windows(report,witness)
    frames = {}
    faithful=True
    for metadata,image in packet((folder/'lab.frames').read_bytes()):
        faithful &= 'rgb_sha256' in metadata
        name,path = metadata['case'],metadata['path']
        row=summary['cases'][name]
        row.setdefault('captured_contrast',{}).setdefault(path,[]).append(dict(frame=metadata['frame'],**contrast(image)))
        if name in ('reference','filtered_previous','filtered_optimized','fern_optimized','fern_cluster','fern_vertex','fern_trim','fern_unlit','stone_filtered','flower_filtered','combined_filtered','detail_clustered','detail_lookup','detail_runtime','detail_early','taa') and path=='strafe':
            frames.setdefault(name,[]).append((metadata['frame'],image))
    review_source='filtered_previous' if len(frames.get('filtered_previous',[]))==16 else 'reference'
    review_target='filtered_optimized' if len(frames.get('filtered_optimized',[]))==16 else 'taa'
    if len(frames.get('fern_optimized',[]))==16:review_source='filtered_optimized';review_target='fern_optimized'
    if len(frames.get('fern_cluster',[]))==16:review_source='filtered_optimized';review_target='fern_cluster'
    if review_case:
        if len(frames.get(review_case,[]))!=16:raise ValueError('Requested review case lacks complete captured strafe')
        review_source='fern_cluster' if review_case in ('stone_filtered','flower_filtered','combined_filtered','detail_clustered','detail_lookup','detail_runtime','detail_early') else 'filtered_optimized';review_target=review_case
    if len(frames.get(review_source,[]))==len(frames.get(review_target,[]))==16:
        previews=[]
        for (a,left),(b,right) in zip(frames[review_source],frames[review_target]):
            if a!=b:raise ValueError('Mismatched review frames')
            paired=Image.new('RGB',(640,128));paired.paste(left);paired.paste(right,(320,0));previews.append(paired)
        stream=io.BytesIO()
        previews[0].save(stream,format='WEBP',save_all=True,append_images=previews[1:],duration=33,loop=0,lossless=True)
        if stream.tell()>3*2**20:raise ValueError('Review exceeds admitted 3 MiB cap')
        (folder/'review.webp').write_bytes(stream.getvalue())
        summary['review']='Left: '+('previous 0.06/0.10 filter' if review_source=='filtered_previous' else 'original opaque reference')+'. Right: '+('complete candidate' if review_target=='filtered_optimized' else 'TAA diagnostic control')+'. Matched deterministic strafe, native pixels, nominal simulation cadence; not normal physical gameplay.'
        if review_target=='fern_optimized':summary['review']='Left: current grass-only candidate. Right: laboratory far-fern filter. Matched deterministic strafe, native pixels; not normal physical gameplay or a promoted production change.'
        if review_target=='fern_cluster':summary['review']='Left: current grass-only candidate. Right: laboratory seven-frond filter. Matched deterministic strafe, native pixels; not normal physical gameplay or a promoted production change.'
        if review_target in ('fern_vertex','fern_trim','fern_unlit'):summary['review']='Left: current grass-only candidate. Right: laboratory '+review_target+'. Matched deterministic strafe, native pixels; diagnostic only, not normal physical gameplay or a promoted production change.'
        if review_target in ('stone_filtered','flower_filtered','combined_filtered','detail_clustered','detail_lookup','detail_runtime','detail_early'):summary['review']='Left: integrated grass/fern baseline. Right: lab-only far-detail coverage. Matched source-view strafe, native lossless pixels; physical gameplay and production promotion are separate.'
    if review_case=='detail_runtime' and 'review' in summary:summary['review']='Left: integrated grass/fern baseline. Right: actual production far stone/flower helper. Matched deterministic strafe, native lossless pixels; ordinary physical gameplay is a separate gate.'
    summary['capture_pixels_verified']=faithful
    if not faithful:summary['limitations'].append('Legacy packet used lossy WebP. Raw temporal samples and near/reference hashes remain valid; preview-derived contrast counts and images are not pixel-faithful evidence.')
    (folder/'analysis.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(dict(fixture_valid=summary['fixture_valid'],cases=len(summary['cases']),human_approved=False,
                         summary=str(folder/'analysis.json')),indent=2))
    return summary


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('folder',type=Path)
    parser.add_argument('--review-case',choices=('fern_cluster','fern_vertex','fern_trim','fern_unlit','stone_filtered','flower_filtered','combined_filtered','detail_clustered','detail_lookup','detail_runtime','detail_early'))
    args=parser.parse_args();analyze(args.folder,args.review_case)
