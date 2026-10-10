import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


native = load('verify-native')
apks = load('verify-apks')


class PackagingTests(unittest.TestCase):
    def test_wrong_plugin_architecture_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            header = bytearray(70)
            header[:2] = b'MZ'
            struct.pack_into('<I', header, 60, 64)
            header[64:68] = b'PE\0\0'
            struct.pack_into('<H', header, 68, 0x8664)
            (root / 'ocr.dll').write_bytes(header)
            self.assertEqual(native.architectures(root / 'ocr.dll'), {'x64'})
            with self.assertRaisesRegex(ValueError, 'expected'):
                native.verify(root, {'arm64'})

    def test_empty_bundle_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'No native'):
                native.verify(Path(directory), {'arm64'})

    def test_elf_machine_is_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'ocr.so'
            header = bytearray(64)
            header[:6] = b'\x7fELF\x02\x01'
            struct.pack_into('<H', header, 18, 183)
            path.write_bytes(header)
            self.assertEqual(native.architectures(path), {'arm64'})

    def test_apks_require_each_abi_and_jni(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for abi in apks.EXPECTED:
                with zipfile.ZipFile(root / f'nwafu-bksxk-android-{abi}.apk', 'w') as archive:
                    for name in apks.REQUIRED:
                        archive.writestr(f'lib/{abi}/{name}', b'test')
            apks.verify(root)
            path = root / 'nwafu-bksxk-android-arm64-v8a.apk'
            with zipfile.ZipFile(path, 'a') as archive:
                archive.writestr('lib/x86_64/libflutter.so', b'test')
            with self.assertRaisesRegex(ValueError, 'expected only'):
                apks.verify(root)


if __name__ == '__main__':
    unittest.main()
