# SPDX-License-Identifier: 0BSD
"""Make the editor-capable source launcher use current Windows debug DLLs."""
from contextlib import redirect_stderr, redirect_stdout
import subprocess
import sys
import traceback

from build_native import ADDONS, ROOT, SHARED_HEADERS, build, build_lease
from development_storage import admit


def bundled_current(addon):
    root = ROOT / 'addons' / addon
    name = ('terrain_core.windows.x86_64.dll' if addon == 'volumetric_terrain'
            else f'{addon}.windows.template_debug.x86_64.dll')
    dll = root / 'bin' / name
    paths = [root / 'native', dll, ROOT / 'native_toolchain.lock.json']
    paths.extend(ROOT / 'addons' / name for name in SHARED_HEADERS.get(addon, ()))
    args = [str(path.relative_to(ROOT)) for path in paths]
    tracked = subprocess.run(['git', 'ls-files', '--error-unmatch', args[1]],
                             cwd=ROOT, capture_output=True)
    changes = subprocess.run(['git', 'status', '--porcelain', '--untracked-files=all', '--', *args],
                             cwd=ROOT, check=True, capture_output=True)
    if not dll.is_file() or tracked.returncode != 0 or changes.stdout:
        return False
    revision = subprocess.check_output(['git', 'log', '-1', '--format=%H', '--', args[1]],
                                       cwd=ROOT, text=True).strip()
    if not revision:
        return False
    return subprocess.run(['git', 'diff', '--quiet', revision, 'HEAD', '--', *args],
                          cwd=ROOT).returncode == 0


def prepare():
    with build_lease():
        for addon in ADDONS:
            if bundled_current(addon) or build('template_debug', addon, check_only=True):
                print(f'Current: {addon}', flush=True)
                continue
            admit(ROOT, report_bytes=2 * 2**20, world_bytes=0)
            print(f'Rebuilding changed native code: {addon}', flush=True)
            build('template_debug', addon)
            if not build('template_debug', addon, check_only=True):
                raise RuntimeError(f'{addon} changed during compilation. Retry when the edits have settled.')


if __name__ == '__main__':
    with (ROOT / 'reports/worlds_native.log').open('w', encoding='utf-8') as log:
        with redirect_stdout(log), redirect_stderr(log):
            try:
                prepare()
            except Exception:
                traceback.print_exc()
                sys.exit(1)
