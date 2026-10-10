#!/usr/bin/env python3
"""Reject missing/incorrect APK ABIs (including the JNI OCR library)."""
from pathlib import Path
import sys
import zipfile

EXPECTED = ('armeabi-v7a', 'arm64-v8a', 'x86_64')
REQUIRED = ('libflutter.so', 'libapp.so', 'libonnxruntime.so', 'libonnxruntime4j_jni.so')


def verify(root):
    for abi in EXPECTED:
        paths = list(root.glob(f'nwafu-bksxk-android-{abi}*.apk'))
        if len(paths) != 1:
            raise ValueError(f'Expected exactly one {abi} APK, got {paths}')
        with zipfile.ZipFile(paths[0]) as archive:
            names = set(archive.namelist())
        actual = {n.split('/')[1] for n in names if n.startswith('lib/') and n.endswith('.so')}
        if actual != {abi}:
            raise ValueError(f'{paths[0]}: contains {actual}, expected only {abi}')
        for library in REQUIRED:
            if f'lib/{abi}/{library}' not in names:
                raise ValueError(f'{paths[0]}: missing {library}')
        print(f'{paths[0].name}: {paths[0].stat().st_size / 1024**2:.1f} MiB; ABI/JNI verified')


if __name__ == '__main__':
    verify(Path(sys.argv[1]))
