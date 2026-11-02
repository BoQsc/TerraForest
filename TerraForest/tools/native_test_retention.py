# SPDX-License-Identifier: 0BSD
"""Release byte-verified native library copies created by a completed test run."""
import hashlib
import re
import stat
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def ordinary(path):
    information = path.lstat()
    if stat.S_ISLNK(information.st_mode) or getattr(information, 'st_file_attributes', 0) & 0x400:
        raise ValueError('Linked test-library path: ' + str(path))
    return information


def checked_path(path, root):
    path = Path(path).absolute()
    for parent in [path, *path.parents]:
        ordinary(parent)
        if parent.resolve() == root:
            break
    return path.resolve()


def release_copies(projects, passed, root=ROOT):
    receipt = dict(removed=[], errors=[], bytes=0,
                   scope='Only verified native library copies made for this successful run; logs, fixtures, images, source and installed libraries retained')
    if passed is not True:
        receipt['retained_failed_run'] = True
        return receipt
    root = root.resolve()
    candidates = []
    try:
        for project, libraries in projects.items():
            project = checked_path(project, root)
            relative = project.relative_to(root)
            if not relative.parts or relative.parts[0] not in ('reports', '.build') or not any(re.fullmatch(r'(?:building_contract_release_)?[0-9]{8}T[0-9]{12}Z', part) for part in relative.parts):
                raise ValueError('Expected a unique test project, not a reusable checkout')
            for path, expected in libraries.items():
                path = checked_path(path, root)
                parts = path.relative_to(project).parts
                if len(parts) != 4 or parts[0] != 'addons' or parts[2] != 'bin' or not re.fullmatch(r'[a-z0-9_.-]+\.dll', parts[3]) or not re.fullmatch(r'[0-9a-f]{64}', expected):
                    raise ValueError('Unexpected test-library identity')
                for parent in [path, *path.parents]:
                    ordinary(parent)
                    if parent == root:
                        break
                if not path.resolve().is_relative_to(project.resolve()) or not path.is_file():
                    raise ValueError('Test library escapes project')
                information = ordinary(path)
                if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    raise ValueError('Test library changed after verification: ' + str(path))
                candidates.append((path, expected, information))
    except (OSError, ValueError) as error:
        receipt['errors'].append(str(error))
        return receipt
    for path, expected, before in candidates:
        try:
            current = ordinary(path)
            if (current.st_ino, current.st_size, current.st_mtime_ns) != (before.st_ino, before.st_size, before.st_mtime_ns):
                raise ValueError('Test library identity changed before release')
            path.unlink()
            receipt['removed'].append(dict(path=str(path.relative_to(root)), bytes=before.st_size, sha256=expected))
            receipt['bytes'] += before.st_size
        except (OSError, ValueError) as error:
            receipt['errors'].append(str(error))
    return receipt
