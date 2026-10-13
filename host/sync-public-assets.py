import filecmp
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

if len(sys.argv) != 4:
    raise SystemExit("usage: sync-public-assets.py <source> <target> <state>")

source, target, state = (Path(p) for p in sys.argv[1:])

if not source.is_dir() or source.is_symlink():
    raise SystemExit("invalid asset source")

if target.is_symlink() or state.is_symlink():
    raise SystemExit("unsafe asset destination")


def checked_name(name):
    parts = name.split("/")
    if (
        not name
        or any(p in ("", ".", "..") for p in parts)
        or "\\" in name
        or parts[0] == "students"
    ):
        raise SystemExit("invalid managed asset path")
    return Path(*parts)


files = {}

for base, dirs, names in os.walk(source, followlinks=False):
    for name in dirs + names:
        path = Path(base) / name
        if path.is_symlink():
            raise SystemExit("symlink in asset source")
        if path.relative_to(source).parts[0] == "students":
            raise SystemExit("student data in versioned assets")

    for name in names:
        path = Path(base) / name
        if not path.is_file():
            raise SystemExit("non-file in asset payload")
        rel = path.relative_to(source).as_posix()
        checked_name(rel)
        files[rel] = path

previous = set()

if state.exists():
    data = json.loads(state.read_text())

    if not isinstance(data, list) or any(not isinstance(n, str) for n in data):
        raise SystemExit("invalid asset manifest")

    for name in data:
        checked_name(name)
        previous.add(name)

target.mkdir(parents=True, exist_ok=True)

student_dir = target / "students"

if student_dir.is_symlink() or (
    student_dir.exists() and not student_dir.is_dir()
):
    raise SystemExit("invalid student storage")

student_dir.mkdir(exist_ok=True)


def safe_destination(name):
    rel = checked_name(name)
    current = target

    for part in rel.parts[:-1]:
        current = current / part
        if current.is_symlink():
            raise SystemExit("symlink in persistent storage")
        current.mkdir(exist_ok=True)

    path = target / rel

    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise SystemExit("unsafe asset destination")

    return path


updated = 0

for name, src in sorted(files.items()):
    dst = safe_destination(name)

    if dst.is_file() and filecmp.cmp(src, dst, shallow=False):
        continue

    fd, temp = tempfile.mkstemp(prefix=".sws-asset-", dir=dst.parent)

    try:
        with os.fdopen(fd, "wb") as output, src.open("rb") as content:
            shutil.copyfileobj(content, output)

        os.chmod(temp, 0o644)
        os.replace(temp, dst)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)

    updated += 1

removed = 0

for name in sorted(previous - files.keys()):
    dst = safe_destination(name)

    if dst.is_file():
        dst.unlink()
        removed += 1

        folder = dst.parent

        while folder != target:
            try:
                folder.rmdir()
            except OSError:
                break

            folder = folder.parent

state.parent.mkdir(parents=True, exist_ok=True)

fd, temp = tempfile.mkstemp(prefix=".managed-assets-", dir=state.parent)

try:
    with os.fdopen(fd, "w") as output:
        json.dump(sorted(files), output)

    os.chmod(temp, 0o600)
    os.replace(temp, state)
finally:
    if os.path.exists(temp):
        os.unlink(temp)

print(f"PUBLIC_ASSET_FILES={len(files)}")
print(f"PUBLIC_ASSETS_UPDATED={updated}")
print(f"PUBLIC_ASSETS_REMOVED={removed}")
print("STUDENT_UPLOADS_PRESERVED=YES")
