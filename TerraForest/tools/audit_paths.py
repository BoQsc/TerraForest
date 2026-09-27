"""Check literal Godot paths and cross-addon dependency direction."""
from pathlib import Path
import re
import sys

root=Path(__file__).resolve().parents[1]
errors=[]
for file in root.rglob('*'):
    if file.suffix not in {'.gd','.gdshader','.gdshaderinc','.tscn','.gdextension'}:
        continue
    if '.godot' in file.parts:
        continue
    for line in file.read_text(encoding='utf-8').splitlines():
        if line.lstrip().startswith(('#','//')):
            continue
        for path in re.findall(r'"(res://[^"\n]+)"',line):
            if '%' in path or path.endswith('/') or path.startswith('res://reports/'):
                continue
            if not (root/path[6:]).exists():
                errors.append(f'{file.relative_to(root)}: missing {path}')
            for addon in ['vegetation','volumetric_terrain']:
                if f'addons/{addon}/' in file.as_posix() and not path.startswith(f'res://addons/{addon}/'):
                    errors.append(f'{file.relative_to(root)}: outward dependency {path}')
print('\n'.join(errors) if errors else 'PASS all literal resource paths and core addon boundaries')
sys.exit(bool(errors))
