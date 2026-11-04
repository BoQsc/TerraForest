# SPDX-License-Identifier: 0BSD
"""Install the Python packages the Steam tools need, silently, on first click.

`install_to_steam.pyw` runs under `pythonw`, so there is no console to explain a missing
package in and nothing is preinstalled for a fresh copy of the project. Everything the
install chain imports is in the standard library except Pillow, which
`steam/app_icon/make_app_icon.py` needs when `terraforest.ico` has to be rebuilt; without
it an install stops and asks someone who only double-clicked a file to run pip.

`bootstrap()` checks the table below and, when an import is missing, installs it with the
interpreter already running the launcher - into the user site first, then into
`steam/vendor` for interpreters that refuse `--user` (Store Python, managed virtualenvs) -
so one double-click is still all it takes. Notes go to `steam/logs/install.log`; the check
never raises and never blocks the install it is preparing.

`tkinter` is checked too but is not a pip package: it ships with the Windows Python
installer, and without it the launcher falls back to the headless tool.
"""
from pathlib import Path
import importlib.util
import site
import subprocess
import sys

STEAM = Path(__file__).resolve().parent.parent
VENDOR = STEAM/'vendor'

# module name -> distribution spec installed when that import is missing
PACKAGES = {'PIL': 'Pillow'}

# stdlib with a Windows installer option, so a missing one cannot be pip-installed
OPTIONAL = {'tkinter'}


def present(module):
    """True when `module` can be imported, without importing it."""
    try:
        return importlib.util.find_spec(module) is not None
    except (ImportError, ValueError):
        return False


def missing(packages=None):
    """The module names from `packages` (default: PACKAGES) that cannot be imported."""
    return sorted(name for name in (packages or PACKAGES) if not present(name))


def _run(args):
    """Run pip without a console window and keep its output for the log."""
    flags = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
    try:
        return subprocess.run(args, capture_output=True, text=True, creationflags=flags)
    except OSError as exc:
        return subprocess.CompletedProcess(args, 1, '', str(exc))


def has_pip():
    return _run([sys.executable, '-m', 'pip', '--version']).returncode == 0


def add_pip():
    """Last resort: a bare interpreter still ships ensurepip."""
    return _run([sys.executable, '-m', 'ensurepip', '--user', '--upgrade']).returncode == 0


def install(spec, target=None):
    """pip install one distribution; `target` keeps it out of site-packages.

    Returns the completed process, so the caller can log why an install failed.
    """
    args = [sys.executable, '-m', 'pip', 'install', '--no-input',
            '--disable-pip-version-check', '--quiet', '--retries', '1', '--timeout', '20']
    args += ['--target', str(target)] if target else ['--user']
    return _run(args + [spec])


def _refresh():
    """Make a freshly created user/vendor directory importable in this process."""
    for folder in (site.getusersitepackages(), str(VENDOR)):
        if folder not in sys.path and Path(folder).is_dir():
            site.addsitedir(folder)
    importlib.invalidate_caches()


def ensure(packages=None, sink=None):
    """Check the dependencies, install what is missing, report what is still absent.

    Returns the module names that could not be imported afterwards (empty is healthy).
    `sink` receives a list of log lines; the default writes them to `steam/logs/install.log`.
    """
    table = dict(PACKAGES if packages is None else packages)
    notes = []
    need = missing(table)
    if need:
        notes.append(f'missing: {", ".join(need)}')
        have_pip = has_pip() or add_pip()
        if not have_pip:
            notes.append('pip is unavailable; install by hand: '
                         + ', '.join(table[name] for name in need))
        for name in need:
            if not have_pip:
                break
            spec = table[name]
            result = install(spec)
            if result.returncode != 0:
                notes.append(f'{spec}: user install failed, trying {VENDOR.name}/')
                result = install(spec, VENDOR)
            _refresh()
            if present(name):
                notes.append(f'{spec}: installed')
            else:
                detail = (result.stderr or result.stdout or '').strip().splitlines()
                notes.append(f'{spec}: install failed ({detail[-1] if detail else "no output"})')
    for name in sorted(OPTIONAL):
        if not present(name):
            notes.append(f'{name} is missing: the launcher runs headless; reinstall Python '
                         'with Tcl/Tk to get the window')
    still = missing(table)
    if not notes:
        notes.append(f'ok: {", ".join(sorted(table))} present')
    _report(notes, sink)
    return still


def _report(notes, sink=None):
    for line in notes:
        if sink is not None:
            sink(line)
            continue
        try:
            import install_log
            if install_log.CURRENT is not None:
                print(f'deps     : {line}')
            else:
                with install_log.run('dependency_check', []) as run:
                    print(f'deps     : {line}')
        except OSError:
            pass


def bootstrap():
    """The `.pyw` entry point for this module: never raises, always logged."""
    try:
        return ensure()
    except Exception as exc:  # noqa: BLE001 - a failed check must not block the click
        _report([f'check failed: {type(exc).__name__}: {exc}'])
        return missing()


def main(argv=None):
    """`python steam/lib/ensure_deps.py [--check]` - report only, install with --check."""
    args = list(sys.argv[1:] if argv is None else argv)
    if '--check' in args:
        still = ensure(sink=print)
        return 1 if still else 0
    status = ', '.join(f'{name} {"ok" if present(name) else "missing"}'
                       for name in sorted(PACKAGES) + sorted(OPTIONAL))
    print(f'{status}; pip {"ok" if has_pip() else "missing"}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
