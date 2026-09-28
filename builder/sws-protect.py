import hashlib
import hmac
import os
import pathlib
import subprocess
import sys
import tempfile

MAGIC = b"SWS1PHP\x00"
NAMESPACE = "secure-app-sws"

if len(sys.argv) != 6:
    raise SystemExit(
        "usage: sws-protect.py <stage> <private-key> <slug> <version> <runtime-profile>"
    )

stage = pathlib.Path(sys.argv[1]).resolve()
private_key = pathlib.Path(sys.argv[2]).resolve()
slug = sys.argv[3]
version = sys.argv[4]
runtime_profile = sys.argv[5]

if not stage.is_dir():
    raise SystemExit(f"stage not found: {stage}")

if not private_key.is_file():
    raise SystemExit(f"private key not found: {private_key}")

challenge_text = (
    f"secure-app-appliance:sws:v1:{slug}:{version}:{runtime_profile}\n"
)
challenge_bytes = challenge_text.encode()

with tempfile.TemporaryDirectory() as td:
    challenge = pathlib.Path(td) / "challenge"
    challenge.write_bytes(challenge_bytes)

    subprocess.run(
        [
            "ssh-keygen",
            "-Y",
            "sign",
            "-q",
            "-f",
            str(private_key),
            "-n",
            NAMESPACE,
            str(challenge),
        ],
        check=True,
    )

    signature = pathlib.Path(str(challenge) + ".sig").read_bytes()

master = hashlib.sha512(signature).digest()
enc_key = hmac.new(
    master,
    b"sws-v1-encryption",
    hashlib.sha256,
).digest()
mac_key = hmac.new(
    master,
    b"sws-v1-authentication",
    hashlib.sha256,
).digest()

targets = []
removed_source_artifacts = []

for path in stage.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue

    rel = path.relative_to(stage)
    rel_text = rel.as_posix()
    name_lower = path.name.lower()

    if rel_text == "artisan":
        targets.append(path)
        continue

    try:
        data = path.read_bytes()
    except OSError:
        continue

    if b"<?php" not in data:
        continue

    removable = (
        ".php-" in name_lower
        or ".php~" in name_lower
        or ".php_old" in name_lower
        or ".phpold" in name_lower
        or ".phpbackup" in name_lower
        or ".php-backup" in name_lower
        or " - copy.php" in name_lower
    )

    if removable:
        path.unlink()
        removed_source_artifacts.append(rel_text)
        continue

    targets.append(path)

targets.sort()

if not targets:
    raise SystemExit("no PHP source files found to protect")

plain_bytes = 0
cipher_bytes = 0

for path in targets:
    rel = path.relative_to(stage).as_posix()
    plain = path.read_bytes()

    if plain.startswith(MAGIC):
        raise SystemExit(f"file already protected: {rel}")

    iv = os.urandom(16)

    proc = subprocess.run(
        [
            "openssl",
            "enc",
            "-aes-256-ctr",
            "-K",
            enc_key.hex(),
            "-iv",
            iv.hex(),
        ],
        input=plain,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )

    ciphertext = proc.stdout

    auth_data = (
        MAGIC
        + rel.encode()
        + b"\x00"
        + iv
        + ciphertext
    )

    tag = hmac.new(
        mac_key,
        auth_data,
        hashlib.sha256,
    ).digest()

    protected = MAGIC + iv + tag + ciphertext

    mode = path.stat().st_mode
    temp = path.with_name(path.name + ".sws-new")
    temp.write_bytes(protected)
    os.chmod(temp, mode)
    os.replace(temp, path)

    plain_bytes += len(plain)
    cipher_bytes += len(protected)

for path in targets:
    rel = path.relative_to(stage).as_posix()

    if path.read_bytes()[: len(MAGIC)] != MAGIC:
        raise SystemExit(f"protection verification failed: {rel}")

remaining_plaintext = []

for path in stage.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue

    if path in targets:
        continue

    try:
        data = path.read_bytes()
    except OSError:
        continue

    if b"<?php" in data:
        remaining_plaintext.append(
            path.relative_to(stage).as_posix()
        )

if remaining_plaintext:
    print("POST_PROTECTION_PLAINTEXT=YES", file=sys.stderr)

    for rel in remaining_plaintext[:50]:
        print(rel, file=sys.stderr)

    raise SystemExit(
        "plaintext PHP source remains after protection"
    )

print(f"SWS_NAMESPACE={NAMESPACE}")
print(f"SWS_CHALLENGE={challenge_text.strip()}")
print(f"SWS_REMOVED_SOURCE_ARTIFACTS={len(removed_source_artifacts)}")
print(f"SWS_PROTECTED_FILES={len(targets)}")
print(f"SWS_PLAINTEXT_BYTES={plain_bytes}")
print(f"SWS_PROTECTED_BYTES={cipher_bytes}")
print("SWS_PROTECTION=PASS")
