"""Repackage the validated LAB rootfs with the NAT fix and a new version only."""
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile

source = Path('original/meticulous-rootfs.tar.gz')
target = Path('meticulous-rootfs.tar.gz')
old_rules = Path('/tmp/original-rules.v4').read_bytes()
new_rules = Path('config/etc/iptables/rules.v4').read_bytes()
new_version = os.environ['BUILD_VERSION'].encode() + b'\n'
expected_old_version = b'2026M1418-lab_certification'
rule_paths = {'etc/iptables/rules.v4', 'etc/etc/iptables/rules.v4'}
version_path = 'opt/image-build-version'
changed = []
before = {}


def digest_file(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


class HashReader:
    def __init__(self, raw):
        self.raw = raw
        self.digest = hashlib.sha256()

    def read(self, size=-1):
        data = self.raw.read(size)
        self.digest.update(data)
        return data


def normalized(name):
    return name.removeprefix('./').rstrip('/')


def metadata(member):
    encoded_fields = {'path', 'linkpath', 'size', 'mtime', 'uid', 'gid', 'uname', 'gname'}
    extra = {key: value for key, value in member.pax_headers.items() if key not in encoded_fields}
    return (member.type.decode('ascii'), member.mode, member.uid, member.gid,
            member.mtime, member.linkname, member.uname, member.gname,
            extra)


assert old_rules != new_rules
assert old_rules.replace(b'-A POSTROUTING -s 10.42.42.0/24 -j MASQUERADE\n', b'').replace(
    b'-A POSTROUTING -j MASQUERADE\n', b'') == new_rules
with target.open('wb') as packed:
    compressor = subprocess.Popen(['pigz', '-c'], stdin=subprocess.PIPE, stdout=packed)
    with tarfile.open(source, 'r|gz') as src, tarfile.open(fileobj=compressor.stdin, mode='w|') as dst:
        for member in src:
            name = normalized(member.name)
            if name in before:
                raise RuntimeError(f'Duplicate archive member: {name}')
            original_meta = metadata(member)
            data_stream = src.extractfile(member) if member.isfile() else None
            new_digest = None
            size = member.size
            if name in rule_paths or name == version_path:
                if not member.isfile():
                    raise RuntimeError(f'Expected regular file: {name}')
                original = data_stream.read()
                old_digest = hashlib.sha256(original).hexdigest()
                if name in rule_paths:
                    if original != old_rules:
                        raise RuntimeError(f'Unexpected original NAT configuration: {name}: {original!r}')
                    replacement = new_rules
                else:
                    assert original.strip() == expected_old_version, original
                    replacement = new_version
                member = copy.copy(member)
                member.size = len(replacement)
                member.pax_headers = dict(member.pax_headers)
                if 'size' in member.pax_headers:
                    member.pax_headers['size'] = str(member.size)
                size = member.size
                new_digest = hashlib.sha256(replacement).hexdigest()
                dst.addfile(member, io.BytesIO(replacement))
                changed.append({'path': name, 'old_sha256': old_digest, 'new_sha256': new_digest})
            elif data_stream is not None:
                reader = HashReader(data_stream)
                dst.addfile(member, reader)
                new_digest = reader.digest.hexdigest()
            else:
                dst.addfile(member)
            before[name] = {'metadata': original_meta, 'size': size, 'sha256': new_digest}
    compressor.stdin.close()
    assert compressor.wait() == 0

changed_names = {item['path'] for item in changed}
assert 'etc/iptables/rules.v4' in changed_names, changed_names
assert version_path in changed_names, changed_names
assert changed_names <= rule_paths | {version_path}, changed_names
seen = set()
with tarfile.open(target, 'r|gz') as check:
    for member in check:
        name = normalized(member.name)
        assert name not in seen, name
        seen.add(name)
        expected = before[name]
        assert metadata(member) == expected['metadata'], name
        assert member.size == expected['size'], name
        if member.isfile():
            actual = hashlib.file_digest(check.extractfile(member), 'sha256').hexdigest()
            assert actual == expected['sha256'], name
assert seen == set(before)
report = {
    'source_run': int(os.environ['SOURCE_RUN']),
    'source_image': expected_old_version.decode(),
    'source_machine_commit': os.environ['SOURCE_SHA'],
    'image_version': os.environ['BUILD_VERSION'],
    'original_rootfs_sha256': digest_file(source),
    'rebuilt_rootfs_sha256': digest_file(target),
    'archive_entries_verified': len(before),
    'changed_files': changed,
    'all_other_file_contents_and_metadata_identical': True,
    'hardware_validation': 'Not performed',
}
Path('verification.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
