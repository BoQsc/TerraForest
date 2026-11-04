# SPDX-License-Identifier: 0BSD
"""Discover local Windows Godot sources without running Steam or the engine.

Original AI-assisted implementation for TerraForest's Steam installer; no
third-party parser or discovery code is incorporated.
"""
import os
from pathlib import Path
import re
import shutil


def unique_paths(paths):
    """Preserve search order while collapsing equivalent Windows paths."""
    found = []
    seen = set()
    for path in paths:
        path = Path(path)
        key = os.path.normcase(os.path.abspath(path))
        if key not in seen:
            seen.add(key)
            found.append(path)
    return found


def read_vdf(path):
    """Read the quoted text KeyValues subset used by Steam's local manifests.

    Unlike line splitting, tokenization handles compact files, comments and
    escaped backslashes. Incomplete/unreadable metadata is just a missed hint.
    """
    try:
        text = path.read_text('utf-8-sig', errors='replace')
    except OSError:
        return {}
    tokens = re.findall(r'//[^\n]*|"(?:\\.|[^"\\])*"|[{}]', text)
    tokens = iter(token for token in tokens if not token.startswith('//'))

    def unquote(token):
        if not token.startswith('"'):
            raise ValueError('expected quoted KeyValues string')
        return re.sub(r'\\([\\"])', r'\1', token[1:-1])

    def dictionary(nested=False):
        result = {}
        for token in tokens:
            if token == '}':
                if not nested:
                    raise ValueError('unexpected closing brace')
                return result
            key = unquote(token)
            value = next(tokens)
            result[key.lower()] = dictionary(True) if value == '{' else unquote(value)
        if nested:
            raise ValueError('missing closing brace')
        return result

    try:
        return dictionary()
    except (ValueError, StopIteration, RecursionError):
        return {}


def steam_libraries(roots):
    libraries = list(roots)
    for root in roots:
        metadata = read_vdf(root/'steamapps'/'libraryfolders.vdf')
        folders = metadata.get('libraryfolders', {})
        if not isinstance(folders, dict):
            continue
        for index, entry in folders.items():
            if not index.isdigit():
                continue
            # Current Steam uses {"path": ...}; older clients used "1": path.
            path = entry.get('path') if isinstance(entry, dict) else entry
            if isinstance(path, str) and path:
                libraries.append(Path(path))
    return unique_paths(libraries)


def godot_directories(library):
    common = library/'steamapps'/'common'
    state = read_vdf(library/'steamapps'/'appmanifest_404790.acf').get('appstate', {})
    installed = state.get('installdir') if isinstance(state, dict) else None
    directories = []
    if isinstance(installed, str) and installed:
        # installdir is relative to common, never a path outside that library.
        folder = Path(installed)
        if not folder.is_absolute() and '..' not in folder.parts:
            directories.append(common/folder)
    return unique_paths([*directories, common/'Godot Engine'])


def source_candidates(project, roots):
    """Export, explicit environment override, Steam libraries, then PATH."""
    found = [project/'dist'/'TerraForest.exe']
    override = os.environ.get('GODOT_EXE', '').strip().strip('"')
    if override:
        found.append(Path(os.path.expandvars(override)).expanduser())
    for library in steam_libraries(roots):
        for folder in godot_directories(library):
            # Prefer the engine itself over Steam's launcher when both exist.
            found.extend([folder/'godot.windows.opt.tools.64.exe',
                          folder/'Godot Engine.exe'])
            # Standalone/versioned Windows builds may be placed in the library.
            found.extend(sorted(folder.glob('Godot*_win64*.exe'),
                                key=lambda p: ('console' in p.name.lower(), p.name.lower())))
    for command in ('godot', 'godot4'):
        executable = shutil.which(command)
        if executable and Path(executable).suffix.lower() == '.exe':
            found.append(Path(executable))
    return unique_paths(found)
