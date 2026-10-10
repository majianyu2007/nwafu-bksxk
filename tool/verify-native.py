#!/usr/bin/env python3
"""Check packaged machine types, including plugins and OCR dependencies."""
import argparse
from pathlib import Path
import struct
import subprocess


def architectures(path):
    with path.open('rb') as stream:
        head = stream.read(64)
        if head[:2] == b'MZ':
            stream.seek(struct.unpack_from('<I', head, 60)[0])
            pe = stream.read(6)
            if pe[:4] != b'PE\0\0':
                raise ValueError(f'Invalid PE file: {path}')
            return {dict([(0x8664, 'x64'), (0xaa64, 'arm64'), (0x14c, 'x86')])
                    .get(struct.unpack_from('<H', pe, 4)[0], 'unknown')}
        if head[:4] == b'\x7fELF':
            endian = '<' if head[5] == 1 else '>'
            return {{62: 'x64', 183: 'arm64', 3: 'x86', 40: 'arm32'}
                    .get(struct.unpack_from(endian + 'H', head, 18)[0], 'unknown')}
        if head[:4] in [bytes.fromhex(x) for x in
                         ('feedface', 'cefaedfe', 'feedfacf', 'cffaedfe',
                          'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')]:
            result = subprocess.check_output(['lipo', '-archs', str(path)], text=True)
            return set(result.strip().split())
    return None


def verify(root, required):
    count = 0
    for path in sorted(root.rglob('*')):
        if not path.is_file() or path.is_symlink():
            continue
        found = architectures(path)
        if found is None:
            continue
        if not required <= found:
            raise ValueError(f'{path}: expected {sorted(required)}, got {sorted(found)}')
        count += 1
    if not count:
        raise ValueError(f'No native binaries found under {root}')
    print(f'Checked {count} native binaries: {", ".join(sorted(required))}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('architectures', nargs='+')
    args = parser.parse_args()
    verify(args.root, set(args.architectures))
