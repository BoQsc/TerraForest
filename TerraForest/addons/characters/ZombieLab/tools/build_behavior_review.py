"""Encode the recorded native four-view pose sequence without retiming.

Uses Python standard library and the installed ffmpeg/ffprobe executables.
Frames remain in recorded order at the authored 60 Hz. Endpoint frames are
included as labelled inspection samples rather than discarded as loop duplicates.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', type=Path, action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--ffmpeg', default='ffmpeg')
    parser.add_argument('--ffprobe', default='ffprobe')
    args = parser.parse_args()
    rows = []
    chapters = []
    inputs = []
    for manifest in args.manifest:
        data = json.loads(manifest.read_text())
        if not data.get('passed') or data.get('frame_step') != 1:
            raise ValueError('Only complete, exact, every-frame native captures may be encoded: ' + str(manifest))
        inputs.append({'path': str(manifest.resolve()), 'sha256': hashlib.sha256(manifest.read_bytes()).hexdigest(),
                       'model_sha256': data['source_sha256']['assets/Zombie.r4.glb'], 'frames': data['frame_count'],
                       'detail_mode': data['detail_mode']})
        last_clip = None
        for frame in data['frames']:
            source = manifest.parent / frame['file']
            if not source.is_file():
                raise FileNotFoundError(source)
            actual = hashlib.sha256(source.read_bytes()).hexdigest()
            if actual != frame['image_sha256']:
                raise ValueError('Captured image changed: ' + str(source))
            if frame['clip'] != last_clip:
                if chapters:
                    chapters[-1]['last_frame_exclusive'] = len(rows)
                chapters.append({'clip': frame['clip'], 'detail': data['detail_mode'], 'first_frame': len(rows)})
                last_clip = frame['clip']
            rows.append(source.resolve())
    if len({item['model_sha256'] for item in inputs}) != 1:
        raise ValueError('Capture inputs do not use the same R4 model bytes.')
    chapters[-1]['last_frame_exclusive'] = len(rows)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='zombie-r4-review-') as temporary:
        tmp = Path(temporary)
        for index, source in enumerate(rows):
            (tmp / ('%06d.png' % index)).symlink_to(source)
        metadata = [';FFMETADATA1', 'title=R4 actions and mouth detail — native four-view frame review',
                    'comment=All authored integer frames, 60 Hz. Actual lab interactions are provided separately.']
        for chapter in chapters:
            label = chapter['clip'].removeprefix('Zombie_').replace('_', ' ')
            metadata += ['[CHAPTER]', 'TIMEBASE=1/60', 'START=' + str(chapter['first_frame']),
                         'END=' + str(chapter['last_frame_exclusive']),
                         'title=' + label + ' / ' + chapter['detail']]
        meta_path = tmp / 'chapters.txt'
        meta_path.write_text('\n'.join(metadata) + '\n')
        command = [args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '60',
                   '-i', str(tmp / '%06d.png'), '-f', 'ffmetadata', '-i', str(meta_path),
                   '-map', '0:v:0', '-map_metadata', '1', '-map_chapters', '1', '-an',
                   '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p',
                   '-movflags', '+faststart', str(args.output)]
        subprocess.run(command, check=True)
    probe = subprocess.run([args.ffprobe, '-v', 'error', '-count_frames', '-select_streams', 'v:0',
                            '-show_entries', 'stream=width,height,nb_read_frames,r_frame_rate,duration',
                            '-of', 'json', str(args.output)], capture_output=True, text=True, check=True)
    stream = json.loads(probe.stdout)['streams'][0]
    passed = int(stream['nb_read_frames']) == len(rows) and stream['r_frame_rate'] == '60/1'
    report = {'passed': passed, 'movie': args.output.name,
              'sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(), 'bytes': args.output.stat().st_size,
              'native_capture_inputs': inputs, 'source_frame_count': len(rows), 'encoded_stream': stream,
              'chapters': chapters, 'sampling': 'One labelled image per authored integer frame, including each clip endpoint.',
              'limits': ['This is animation inspection at authored speed. The demonstration recording validates interaction and root physics separately.']}
    args.output.with_suffix('.manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    if not passed:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
