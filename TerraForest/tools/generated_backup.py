# SPDX-License-Identifier: 0BSD
"""Lossless project artifact volumes; explicit inputs only, no source deletion.

Catalog and restore are offline. Publish requires an explicit GitHub repository,
existing backup branch and draft release tag. Credentials stay in memory.
"""
import argparse
import gzip
import hashlib
import http.client
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import urllib.parse
import urllib.error
import urllib.request
import zipfile

from retained_artifacts import ordinary, ordinary_ancestors, relative_name, digest, identity
from resource_limits import require_free_space

SECRET = re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9_-]{32,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)')
TEXT = {'.json', '.log', '.txt', '.cfg', '.ini', '.py', '.gd', '.md', '.yaml', '.yml', '.toml', '.csv'}
SKIP = {'.git', '.godot', '.codex', '__pycache__', 'node_modules', 'zig-local-cache', 'zig-global-cache'}
PRIVATE = {'auth.json', 'credentials.json', 'credentials', 'id_rsa', 'id_ed25519'}


def write_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.pending')
    temporary.write_text(json.dumps(value, separators=(',', ':')), encoding='utf-8')
    temporary.replace(path)


def catalog(spec, output):
    """Snapshot explicit roots with exact bytes/hashes, deduplicating full files."""
    files, exclusions, directories = [], list(spec.get('exclusions', [])), []
    for label, value in spec['roots'].items():
        relative_name(label)
        root = Path(value).absolute()
        ordinary_ancestors(root); ordinary(root)
        for folder, dirs, names in os.walk(root, followlinks=False):
            rel = Path(folder).relative_to(root)
            directories.append((Path(label) / rel).as_posix())
            for name in list(dirs):
                path = Path(folder) / name
                try:
                    ordinary(path)
                    allowed = (name not in SKIP and not str(path).lower().endswith('\\.build\\native')
                               and not name.startswith(('retention_verify_', 'generated_backup_', 'artifact_backup_')))
                except ValueError:
                    allowed = False
                if not allowed:
                    dirs.remove(name)
                    exclusions.append(dict(path=(Path(label) / rel / name).as_posix(), reason='rebuildable cache, private state, verification duplicate, or linked target'))
            for name in sorted(names):
                path = Path(folder) / name
                logical = (Path(label) / rel / name).as_posix()
                if name.lower() in PRIVATE or name.startswith('.env') or path.suffix.lower() in ('.key', '.pem'):
                    exclusions.append(dict(path=logical, reason='credential-like file; retained locally'))
                    continue
                try:
                    before = identity(path)
                except ValueError:
                    exclusions.append(dict(path=logical, reason='linked/special file; retained locally'))
                    continue
                checksum = hashlib.sha256()
                carry = b''
                with path.open('rb') as stream:
                    while data := stream.read(1024 * 1024):
                        checksum.update(data)
                        if path.suffix.lower() in TEXT and SECRET.search(carry + data):
                            raise ValueError('Credential-like content blocks backup: ' + logical)
                        carry = data[-256:]
                if identity(path) != before:
                    raise ValueError('Changed during catalog: ' + logical)
                files.append(dict(path=logical, sha256=checksum.hexdigest(), bytes=before[2], mtime_ns=before[3]))
                if len(files) % 10000 == 0:
                    print('Cataloged', len(files), 'files', flush=True)
    unique = {r['sha256']: r['bytes'] for r in files}
    result = dict(schema=1, roots=spec['roots'], directories=directories, files=files, exclusions=exclusions,
                  logical_bytes=sum(r['bytes'] for r in files), unique_bytes=sum(unique.values()))
    write_json(output, result)
    print(json.dumps(dict(files=len(files), unique_files=len(unique), logical_gib=result['logical_bytes']/2**30,
                          unique_gib=result['unique_bytes']/2**30, exclusions=len(exclusions))), flush=True)
    return result


def source_path(record, row):
    choices = sorted(record['roots'], key=len, reverse=True)
    for label in choices:
        if row['path'] == label:
            return Path(record['roots'][label])
        if row['path'].startswith(label + '/'):
            return Path(record['roots'][label]) / relative_name(row['path'][len(label)+1:])
    raise ValueError('No explicit root for ' + row['path'])


def groups(record, maximum=512*2**20):
    # Keep related paths near one another so a single report restore does not
    # require every volume. Shared objects retain their first catalog owner.
    objects = {}
    for row in record['files']:
        objects.setdefault(row['sha256'], row)
    batch, size = [], 0
    for row in sorted(objects.values(), key=lambda r:r['path']):
        if row['bytes'] > 1800 * 2**20:
            raise ValueError('Object requires chunking before publication: ' + row['path'])
        if batch and size + row['bytes'] > maximum:
            yield batch
            batch, size = [], 0
        batch.append(row); size += row['bytes']
    if batch:
        yield batch


def make_volume(record, rows, destination):
    buffered = isinstance(destination, io.BytesIO)
    if not buffered:
        require_free_space(destination.parent, sum(r['bytes'] for r in rows) + 8*2**20)
    with zipfile.ZipFile(destination, 'w' if buffered else 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=3) as output:
        for row in rows:
            source = source_path(record, row)
            ordinary_ancestors(source)
            before = identity(source)
            checksum = hashlib.sha256()
            with source.open('rb') as incoming, output.open(row['sha256'], 'w', force_zip64=True) as outgoing:
                while data := incoming.read(1024*1024):
                    outgoing.write(data); checksum.update(data)
            if identity(source) != before or before[2] != row['bytes'] or checksum.hexdigest() != row['sha256']:
                raise ValueError('Source changed since catalog: ' + row['path'])
    with zipfile.ZipFile(destination) as check:
        if check.testzip() is not None:
            raise ValueError('Volume CRC verification failed')
    if buffered:
        destination.seek(0)
        result = dict(bytes=destination.getbuffer().nbytes, sha256=hashlib.file_digest(destination, 'sha256').hexdigest())
        destination.seek(0)
        return result
    return dict(bytes=destination.stat().st_size, sha256=digest(destination))


class GitHub:
    def __init__(self, repository):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
            raise ValueError('Invalid repository')
        credentials = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n',
            text=True, capture_output=True, check=True, env=dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='never'))
        values = dict(line.split('=', 1) for line in credentials.stdout.splitlines() if '=' in line)
        self.headers = {'Authorization': 'Bearer ' + values['password'], 'Accept': 'application/vnd.github+json',
                        'User-Agent': 'TerraForest-generated-backup'}
        self.base = 'https://api.github.com/repos/' + repository

    def request(self, path, data=None, method=None):
        body = None if data is None else json.dumps(data).encode()
        request = urllib.request.Request(self.base + path, data=body,
            headers={**self.headers, 'Content-Type':'application/json'}, method=method)
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)

    def upload(self, release, stream, name, expected):
        # Only send the credential to GitHub's documented upload host.
        endpoint = urllib.parse.urlsplit(release['upload_url'].split('{')[0])
        if endpoint.scheme != 'https' or endpoint.netloc != 'uploads.github.com':
            raise ValueError('Unexpected asset upload destination')
        connection = http.client.HTTPSConnection(endpoint.netloc, timeout=60)
        try:
            connection.putrequest('POST', endpoint.path + '?name=' + urllib.parse.quote(name))
            for key, value in self.headers.items():
                connection.putheader(key, value)
            connection.putheader('Content-Type', 'application/octet-stream')
            connection.putheader('Content-Length', str(expected['bytes']))
            connection.endheaders()
            stream.seek(0)
            while block := stream.read(1024*1024):
                connection.send(block)
            response = connection.getresponse()
            payload = json.load(response)
            if response.status != 201:
                raise OSError('Asset upload failed with HTTP ' + str(response.status))
        finally:
            connection.close()
        self.verify_asset(payload, expected)
        return payload

    def verify_asset(self, asset, expected):
        remote = self.request('/releases/assets/' + str(asset['id']))
        if remote.get('state') != 'uploaded' or remote.get('size') != expected['bytes']:
            raise ValueError('Remote asset is incomplete')
        if remote.get('digest') != 'sha256:' + expected['sha256']:
            raise ValueError('Remote SHA-256 differs or is unavailable; local volume retained')

    def download(self, asset_id):
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        request = urllib.request.Request(self.base + '/releases/assets/' + str(asset_id),
            headers={**self.headers, 'Accept':'application/octet-stream'})
        try:
            return urllib.request.build_opener(NoRedirect).open(request, timeout=60)
        except urllib.error.HTTPError as error:
            if error.code != 302:
                raise
            location = error.headers['Location']
            target = urllib.parse.urlsplit(location)
            if target.scheme != 'https' or target.hostname != 'release-assets.githubusercontent.com':
                raise ValueError('Unexpected asset download destination')
            # Signed object URL needs no GitHub credential; never forward it.
            return urllib.request.urlopen(location, timeout=60)


def read_json(path):
    opener = gzip.open if path.suffix == '.gz' else open
    with opener(path, 'rt', encoding='utf-8') as source:
        return json.load(source)


def download(catalog_path, receipt_path, folder, prefix=''):
    record, receipt = read_json(catalog_path), read_json(receipt_path)
    if receipt.get('complete') is not True:
        raise ValueError('Backup publication is incomplete')
    wanted = {r['sha256'] for r in record['files'] if r['path'].startswith(prefix)}
    assets = [a for a in receipt['assets'] if wanted.intersection(a['objects'])]
    if wanted - {key for a in assets for key in a['objects']}:
        raise ValueError('Backup index omits required objects')
    ordinary_ancestors(folder); folder.mkdir(parents=True, exist_ok=True)
    require_free_space(folder, sum(a['bytes'] for a in assets if not (folder / a['name']).exists()))
    api = GitHub(receipt['repository'])
    for asset in assets:
        if not re.fullmatch(r'objects-[0-9]{3}\.zip', asset['name']):
            raise ValueError('Unsafe volume name')
        destination = folder / asset['name']
        if destination.exists():
            ordinary(destination)
            if destination.stat().st_size != asset['bytes'] or digest(destination) != asset['sha256']:
                raise ValueError('Existing download differs; retained for inspection')
            continue
        api.verify_asset(asset, asset)
        checksum, size = hashlib.sha256(), 0
        with api.download(asset['id']) as source, destination.open('xb') as output:
            while block := source.read(1024*1024):
                size += len(block)
                if size > asset['bytes']:
                    raise ValueError('Download exceeds recorded size')
                output.write(block); checksum.update(block)
        if size != asset['bytes'] or checksum.hexdigest() != asset['sha256']:
            raise ValueError('Downloaded volume failed verification')
        print('Downloaded and verified', asset['name'], flush=True)


def publish(catalog_path, folder, repository, branch, tag):
    record = json.loads(catalog_path.read_text(encoding='utf-8'))
    folder.mkdir(parents=True, exist_ok=True)
    ordinary_ancestors(folder)
    receipt_path = folder / 'upload.json'
    receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else dict(schema=1, repository=repository, branch=branch, tag=tag, assets=[])
    if any(receipt[k] != v for k, v in [('repository',repository),('branch',branch),('tag',tag)]):
        raise ValueError('Upload ownership mismatch')
    catalog_sha = digest(catalog_path)
    if receipt.get('catalog_sha256', catalog_sha) != catalog_sha:
        raise ValueError('Catalog changed during publication')
    receipt['catalog_sha256'] = catalog_sha
    api = GitHub(repository)
    if 'release_id' in receipt:
        release = api.request('/releases/' + str(receipt['release_id']))
    else:
        releases = api.request('/releases?per_page=100')
        release = next((r for r in releases if r['tag_name'] == tag), None)
        if release is None:
            release = api.request('/releases', dict(tag_name=tag, target_commitish=branch, draft=True,
                name='Generated artifact backup — 2026-11-10',
                body='Lossless archival backup of TerraForest development evidence. Draft backup, not a gameplay release. '
                     'Catalog and restore instructions are on branch ' + branch + '. Private Codex sessions, credentials and rebuildable tool caches are excluded.'))
        receipt['release_id'] = release['id']; receipt['release_url'] = release['html_url']
        write_json(receipt_path, receipt)
    if not release['draft'] or release['tag_name'] != tag:
        raise ValueError('Expected the dedicated draft backup release')
    existing = {a['name']: a for a in api.request('/releases/' + str(release['id']) + '/assets?per_page=100')}
    all_groups = list(groups(record))
    for index, rows in enumerate(all_groups, 1):
        name = f'objects-{index:03d}.zip'
        prior = next((a for a in receipt['assets'] if a['name'] == name), None)
        if prior:
            api.verify_asset(prior, prior)
            print('Verified existing', name, flush=True)
            continue
        with io.BytesIO() as volume:
            print('Packing', name, index, '/', len(all_groups), flush=True)
            expected = make_volume(record, rows, volume)
            print('Uploading', name, round(expected['bytes']/2**20, 1), 'MiB', flush=True)
            asset = existing.get(name)
            if asset is not None:
                api.verify_asset(asset, expected)
            else:
                asset = api.upload(release, volume, name, expected)
        receipt['assets'].append(dict(name=name, id=asset['id'], url=asset['browser_download_url'],
                                     objects=[r['sha256'] for r in rows], **expected))
        write_json(receipt_path, receipt)
        # One bounded memory buffer; source evidence remains on disk throughout.
        print('Remote SHA-256 verified', name, flush=True)
    receipt['complete'] = True
    write_json(receipt_path, receipt)
    return receipt


def restore(catalog_path, volumes, destination, prefix=''):
    record = read_json(catalog_path)
    ordinary_ancestors(destination)
    if destination.exists():
        raise FileExistsError('Restore requires a new directory')
    rows = [r for r in record['files'] if r['path'].startswith(prefix)]
    for row in rows:
        relative_name(row['path'])
    needed = {r['sha256'] for r in rows}
    locations = {}
    for volume in sorted(volumes.glob('objects-*.zip')):
        with zipfile.ZipFile(volume) as source:
            for name in source.namelist():
                if name in needed:
                    locations[name] = volume
    if needed - locations.keys():
        raise ValueError('Required backup volumes are missing')
    parent = destination.parent
    while not parent.exists():
        parent = parent.parent
    require_free_space(parent, sum(r['bytes'] for r in rows))
    destination.mkdir(parents=True)
    for row in rows:
        path = destination / row['path']; path.parent.mkdir(parents=True, exist_ok=True)
        ordinary_ancestors(path)
        checksum = hashlib.sha256(); size = 0
        with zipfile.ZipFile(locations[row['sha256']]) as source, source.open(row['sha256']) as incoming, path.open('xb') as output:
            while block := incoming.read(1024*1024):
                checksum.update(block); size += len(block); output.write(block)
        if size != row['bytes'] or checksum.hexdigest() != row['sha256']:
            raise ValueError('Restored hash mismatch: ' + row['path'])
    for name in record['directories']:
        if name.startswith(prefix):
            relative_name(name); (destination / name).mkdir(parents=True, exist_ok=True)
    return dict(files=len(rows), bytes=sum(r['bytes'] for r in rows))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    make = sub.add_parser('catalog'); make.add_argument('spec', type=Path); make.add_argument('output', type=Path)
    send = sub.add_parser('publish'); send.add_argument('catalog', type=Path); send.add_argument('folder', type=Path)
    send.add_argument('--repository', required=True); send.add_argument('--branch', required=True); send.add_argument('--tag', required=True)
    fetch = sub.add_parser('download'); fetch.add_argument('catalog', type=Path); fetch.add_argument('receipt', type=Path); fetch.add_argument('folder', type=Path); fetch.add_argument('--prefix', default='')
    unpack = sub.add_parser('restore'); unpack.add_argument('catalog', type=Path); unpack.add_argument('volumes', type=Path); unpack.add_argument('destination', type=Path); unpack.add_argument('--prefix', default='')
    args = parser.parse_args()
    if args.action == 'catalog':
        catalog(json.loads(args.spec.read_text()), args.output)
    elif args.action == 'publish':
        publish(args.catalog, args.folder, args.repository, args.branch, args.tag)
    elif args.action == 'download':
        download(args.catalog, args.receipt, args.folder, args.prefix)
    else:
        print(restore(args.catalog, args.volumes, args.destination, args.prefix))
