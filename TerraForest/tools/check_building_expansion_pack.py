# SPDX-License-Identifier: 0BSD
"""Verify candidate buildings, appearances and baked UI assets inside the PCK."""
import datetime
import hashlib
import json
from run import ROOT, parse_args
from run_godot_check import command_for, execute, revision_metadata, verify_pack_native


def main():
    config, _ = parse_args([])
    folder = ROOT/'reports/building_expansion/packed'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True)
    source = ROOT/'tests/building_expansion_pack.gd'
    driver = folder/'driver.gd'
    driver.write_bytes(source.read_bytes())
    native = verify_pack_native()
    command, cache = command_for(config.godot, 'building_expansion_pack', folder, [], headless=True)
    command[1:1] = ['--main-pack', str(ROOT/'dist/TerraForest.pck')]
    command[command.index('--path')+1] = str(ROOT/'dist')
    command[command.index('--script')+1] = str(driver)
    result = execute(command, folder, 120, 'BUILDING_EXPANSION_PACK checks=')
    record = dict(command=command, cache=cache, native_sha256=native, result=result,
                  test_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  pack_sha256=hashlib.sha256((ROOT/'dist/TerraForest.pck').read_bytes()).hexdigest(),
                  **revision_metadata())
    (folder/'run.json').write_text(json.dumps(record, indent=2)+'\n')
    print(('PASS ' if result['passed'] else 'FAIL ')+str(folder))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
