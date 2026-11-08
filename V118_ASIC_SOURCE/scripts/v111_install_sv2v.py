#!/usr/bin/env python3
"""Install pinned upstream sv2v Linux release locally, only if not already present.

Release: https://github.com/zachjs/sv2v/releases/tag/v0.0.13
Asset size from release metadata: 2,197,565 bytes.
"""
from pathlib import Path
from zipfile import ZipFile
import os
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
local_binary = root / '.tools/sv2v/v0.0.13/sv2v'
if local_binary.exists() and os.access(local_binary, os.X_OK):
    print(local_binary)
    sys.exit(0)

command = shutil.which('sv2v')
if command:
    print(command)
    sys.exit(0)

url = 'https://github.com/zachjs/sv2v/releases/download/v0.0.13/sv2v-Linux.zip'
local_binary.parent.mkdir(parents=True, exist_ok=True)
archive = local_binary.parent / 'sv2v-Linux.zip'
print('[INFO] Downloading official sv2v v0.0.13 prebuilt Linux binary (~2.2 MB)', file=sys.stderr)
try:
    subprocess.run(['curl', '-fLSs', '--retry', '3', '--connect-timeout', '15',
                    '--max-time', '180', '-o', str(archive), url], check=True)
    with ZipFile(archive) as z:
        binaries = [e for e in z.infolist()
                    if not e.is_dir() and Path(e.filename).name == 'sv2v']
        if len(binaries) != 1:
            raise RuntimeError(f'Expected one sv2v executable in release ZIP; found {len(binaries)}')
        with z.open(binaries[0]) as src:
            with local_binary.open('wb') as dst:
                shutil.copyfileobj(src, dst)
    if local_binary.open('rb').read(4) != b'\x7fELF':
        raise RuntimeError('Downloaded file is not an ELF Linux executable')
    local_binary.chmod(0o755)
    subprocess.run([str(local_binary), '--version'], check=True, stdout=subprocess.DEVNULL)
except Exception as exc:
    local_binary.unlink(missing_ok=True)
    raise SystemExit('[FAIL] Could not obtain sv2v: ' + str(exc) +
                     '\nInstall sv2v manually from ' + url)
finally:
    archive.unlink(missing_ok=True)
print('[OK] sv2v installed at ' + str(local_binary), file=sys.stderr)
print(local_binary)
