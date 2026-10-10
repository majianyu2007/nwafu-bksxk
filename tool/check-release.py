#!/usr/bin/env python3
"""Refuse a tag whose version differs from the app's version."""
import os
from pathlib import Path
import re

text = Path('pubspec.yaml').read_text()
version = re.search(r'^version:\s*([^+\s]+)', text, re.M).group(1)
tag = os.environ.get('GITHUB_REF', '')
if tag.startswith('refs/tags/') and tag != f'refs/tags/v{version}':
    raise SystemExit(f'Tag {tag} does not match pubspec version {version}')
print(f'App version: {version}')
