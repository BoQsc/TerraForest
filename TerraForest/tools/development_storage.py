# SPDX-License-Identifier: 0BSD
"""Admission limits for developer outputs, independent of gameplay budgets."""
import json
import os
from pathlib import Path
import stat

from resource_limits import require_free_space

ROOT = Path(__file__).resolve().parents[1]
GIB = 1024**3
LIMITS = {'reports': 4*GIB, 'scratch': 2*GIB, 'archive': 10*GIB,
          'compiler_cache': 4*GIB, 'import_cache': 2*GIB}


def usage(root):
    root = Path(root)
    total = dict.fromkeys(LIMITS, 0)
    for name in ('reports', '.build', '.godot'):
        base = root/name
        if not base.exists():
            continue
        info = base.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info,'st_file_attributes',0)&0x400:
            raise OSError('Development-output root is linked; inspect it before capture')
        for folder, dirs, files in os.walk(base, followlinks=False):
            directory = Path(folder)
            dirs[:] = [n for n in dirs if not ((directory/n).lstat().st_file_attributes & 0x400)] if os.name == 'nt' else [n for n in dirs if not (directory/n).is_symlink()]
            rel = directory.relative_to(base).parts
            category = ('archive' if name == 'reports' and rel and rel[0] == 'retained_artifacts' else
                        'reports' if name == 'reports' else
                        'import_cache' if name == '.godot' else
                        'compiler_cache' if rel and rel[0] in ('native','zig-local-cache','zig-global-cache') else 'scratch')
            for filename in files:
                info = (directory/filename).lstat()
                if stat.S_ISREG(info.st_mode) and not getattr(info,'st_file_attributes',0)&0x400:
                    total[category] += info.st_size
    return total


def admit(root=ROOT, report_bytes=256*2**20, scratch_bytes=0, limits=None):
    if report_bytes < 0 or scratch_bytes < 0:
        raise ValueError('Planned output must be nonnegative')
    limits = LIMITS if limits is None else limits
    require_free_space(root, report_bytes + scratch_bytes)
    current = usage(root)
    planned = dict(current)
    planned['reports'] += report_bytes
    planned['scratch'] += scratch_bytes
    excess = {k:dict(bytes=planned[k], limit=v) for k,v in limits.items() if planned[k] > v}
    if excess:
        raise OSError('Development output budget reached; verify backup and retire obsolete outputs before new work: ' + json.dumps(excess))
    return dict(bytes=current, limits=limits, planned_report_bytes=report_bytes, planned_scratch_bytes=scratch_bytes)


if __name__ == '__main__':
    print(json.dumps(dict(bytes=usage(ROOT),limits=LIMITS),indent=2))
