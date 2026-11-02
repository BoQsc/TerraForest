# SPDX-License-Identifier: 0BSD
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'addons/world_runtime/startup_index.json'
ENTRIES = ['demo/world.gd', 'addons/world_runtime/world_generation_plan.gd',
           'addons/world_runtime/generation_coordinator.gd',
           'addons/world_runtime/generate_world_task.gd',
           'addons/world_runtime/prepare_combined_world_task.gd',
           'addons/world_runtime/capture_world_previews_task.gd']
PATTERN = re.compile(r'\bpreload\s*\(\s*[\"\'](res://[^\"\']+)[\"\']\s*\)|^\s*extends\s+[\"\'](res://[^\"\']+)[\"\']', re.M)

def build():
    graph = {}
    def visit(path):
        if path in graph:
            return
        graph[path] = []
        source = (ROOT / path[6:]).read_text(encoding='utf-8-sig')
        for match in PATTERN.finditer(source):
            dependency = match.group(1) or match.group(2)
            if dependency not in graph[path]:
                graph[path].append(dependency)
            if dependency.endswith('.gd'):
                visit(dependency)
    for path in ENTRIES:
        visit('res://' + path)
    graph['res://addons/world_runtime/material_pickups.gd'].extend(
        'res://' + path.relative_to(ROOT).as_posix()
        for path in sorted((ROOT / 'addons/player_runtime/art/drops').glob('*.res')))
    return json.dumps(graph, indent=2, sort_keys=True) + '\n'

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    contents = build()
    if args.check:
        if not TARGET.exists() or TARGET.read_text(encoding='utf-8') != contents:
            raise SystemExit('Startup dependency index is stale; run tools/build_startup_index.py')
    else:
        TARGET.write_text(contents, encoding='utf-8', newline='\n')
    print('STARTUP_INDEX current')
