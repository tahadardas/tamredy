#!/usr/bin/env python3
"""Validate release metadata without printing credentials or production responses."""
import hashlib
import json
import os
import re
import sys
import tarfile
import zipfile
from pathlib import Path, PurePosixPath


def sha256(stream):
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(chunk)
    return digest.hexdigest()


def check(condition, message):
    if not condition:
        raise ValueError(message)


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def member_path(name):
    path = PurePosixPath(name)
    check(path.parts and not path.is_absolute() and ".." not in path.parts and "\\" not in name,
          "Unsafe archive or checksum path")
    return path


def migrations(manifest, names):
    required = manifest["requiredMigrations"]
    check(isinstance(required, list) and required and len(set(required)) == len(required),
          "Invalid release migration manifest")
    check(all(isinstance(name, str) and re.fullmatch(r"[0-9]+_[A-Za-z0-9_]+\.sql", name) for name in required),
          "Invalid migration filename")
    check(set(required) <= set(names), "Required migrations missing")


def verify_bundle(manifest_path, release, transfer):
    manifest = load(manifest_path)
    check(re.fullmatch(r"[a-f0-9]{40}", manifest["sourceCommit"]), "Invalid release source commit")
    sums = {}
    for entry in (transfer / "SHA256SUMS.txt").read_text(encoding="utf-8-sig").splitlines():
        if not entry.strip():
            continue
        match = re.fullmatch(r"([a-f0-9A-F]{64}) [ *](.+)", entry)
        check(match, "Invalid checksum row")
        name = str(member_path(match[2]))
        check(name not in sums, "Duplicate checksum row")
        sums[name] = match[1].lower()
    archive_name = next((name for name in ("tamreedy-server.tar.gz", "tamreedy-server.zip")
                         if (transfer / name).is_file()), None)
    check(archive_name, "Source archive missing")
    required_uploads = {archive_name, "RELEASE_MANIFEST.json"}
    if manifest["prebuiltImagesAvailable"] and (transfer / "server-images/tamreedy-images-linux.tar.gz").exists():
        required_uploads.add("server-images/tamreedy-images-linux.tar.gz")
    check(required_uploads <= sums.keys(), "Required release checksums missing")
    source_bundles = {item["path"]: item["sha256"] for item in manifest["sourceBundle"]}
    check(source_bundles.get(archive_name) == sums[archive_name],
          "Manifest and checksum disagree on the source archive")
    for name, digest in sums.items():
        path = transfer / name
        if path.exists() or name in required_uploads:
            check(path.is_file() and not path.is_symlink(), "Release file missing or invalid")
            with path.open("rb") as stream:
                check(sha256(stream) == digest, "Release checksum mismatch")
    expected_files = set()

    def compare_file(name, expected):
        relative = member_path(name)
        file = release / relative
        check(relative not in expected_files and file.is_file() and not file.is_symlink()
              and file.resolve().is_relative_to(release.resolve()), "Extracted release file missing or invalid")
        with file.open("rb") as actual:
            check(sha256(actual) == sha256(expected), "Extracted release differs from checked archive")
        expected_files.add(relative)

    if archive_name.endswith(".zip"):
        with zipfile.ZipFile(transfer / archive_name) as archive:
            for item in archive.infolist():
                if not item.is_dir():
                    with archive.open(item) as expected:
                        compare_file(item.filename, expected)
    else:
        with tarfile.open(transfer / archive_name, "r:gz") as archive:
            for item in archive:
                if not item.isdir():
                    check(item.isfile(), "Unexpected source archive entry type")
                    with archive.extractfile(item) as expected:
                        compare_file(item.name, expected)
    for folder, dirs, files in os.walk(release):
        current = Path(folder)
        check(not any((current / name).is_symlink() for name in dirs), "Extracted release has an unapproved directory link")
        for name in files:
            relative = PurePosixPath((current / name).relative_to(release).as_posix())
            check(relative in expected_files, "Extracted release contains a file outside its archive")
    check(load(release / "release-source.json")["sourceCommit"] == manifest["sourceCommit"],
          "Extracted release commit differs from manifest")
    names = [p.name for p in (release / "infra/db/migrations").glob("*.sql")]
    migrations(manifest, names)
    check(set(manifest["requiredMigrations"]) == set(names), "Archive contains migrations outside its manifest")


def mounted(service, target):
    return next((Path(v["source"]) for v in service.get("volumes", []) if v.get("target") == target), None)


def validate_compose(data, expected_uploads):
    check(data.get("name") == "tamreedy", "Unexpected Compose project name")
    services = data["services"]
    upload_mount = mounted(services["api"], "/data/uploads")
    volume_name = data.get("volumes", {}).get(str(upload_mount), {}).get("name")
    check(volume_name == expected_uploads, "Release would use a different encrypted uploads volume")
    api, worker = (services[key]["environment"] for key in ("api", "worker"))
    check(api.get("TAMREEDY_RELEASE") == worker.get("TAMREEDY_RELEASE") == "3.1.0-rc.3",
          "API/Worker release version differs from RC3")
    flags = ("LIVE_LOCATION_REDIS_ENABLED", "LOCATION_POSTGRES_FALLBACK_ENABLED", "SCHEDULED_VISITS_ENABLED",
             "OPEN_MARKETPLACE_ENABLED", "OPEN_DISPATCH_ENABLED", "GUARDIAN_NIGHT_POLICY_ENABLED",
             "GUARDIAN_ROUTING_ENABLED", "PUSH_ENABLED", "REALTIME_ENABLED", "VOICE_ENABLED")
    for key in flags:
        check(api.get(key) in ("true", "false") and api.get(key) == worker.get(key),
              f"Missing, invalid or inconsistent API/Worker setting: {key}")
    check(not (api["OPEN_DISPATCH_ENABLED"] == "true" and api["OPEN_MARKETPLACE_ENABLED"] == "false"),
          "Open Dispatch requires Open Marketplace")
    check(not any(worker.get(key) for key in ("JWT_SECRET", "DOCS_ENC_KEY")), "Worker receives unrelated API secrets")
    if worker["PUSH_ENABLED"] == "true":
        raw = worker.get("FCM_SERVICE_ACCOUNT_JSON")
        if not raw:
            fcm = mounted(services["worker"], worker.get("FCM_SERVICE_ACCOUNT_FILE"))
            check(fcm and fcm.is_file(), "Enabled Push is missing its Worker credential file")
            raw = fcm.read_text(encoding="utf-8-sig")
        try:
            account = json.loads(raw)
        except ValueError:
            raise ValueError("Invalid Worker Firebase credential JSON") from None
        check(isinstance(account, dict) and all(isinstance(account.get(key), str) and account[key].strip()
              for key in ("project_id", "client_email", "private_key")), "Incomplete Worker Firebase credentials")
    if api["VOICE_ENABLED"] == "true":
        tls = mounted(services.get("coturn", {}), "/run/secrets/tls")
        check(tls and all((tls / name).is_file() and (tls / name).stat().st_size
                          for name in ("fullchain.pem", "privkey.pem")), "TURN certificate or key unavailable")


def verify_response(path, response):
    check(isinstance(response, dict), f"Unexpected response from {path}")
    if path == "/health/ready":
        checks = response.get("checks", {})
        check(response.get("status") == "ready", "Readiness report is not ready")
        check(all(key in checks for key in ("worker", "push", "outbox", "migrations")), "Readiness evidence incomplete")
        check(checks["worker"].get("ok") is True and checks["worker"].get("version") == "3.1.0-rc.3",
              "Worker readiness or release does not match")
    elif path == "/v1/capabilities":
        check(isinstance(response.get("ordersAccepting"), bool), "Capabilities response missing order state")
    else:
        check(response.get("status") == "ok" and response.get("version") == "3.1.0-rc.3",
              "API liveness or release does not match")


def main(argv):
    command = argv[1]
    if command == "bundle":
        verify_bundle(*map(Path, argv[2:]))
    elif command == "compose":
        validate_compose(json.load(sys.stdin), argv[2])
    elif command == "migrations":
        migrations(load(Path(argv[2])), (line.strip() for line in sys.stdin))
    elif command == "response":
        verify_response(argv[2], json.load(sys.stdin))
    else:
        raise ValueError("Unknown release-check command")


if __name__ == "__main__":
    try:
        main(sys.argv)
    except (ValueError, OSError, KeyError, TypeError, AttributeError, tarfile.TarError, zipfile.BadZipFile) as error:
        # Exceptions from decoders and OS paths can include credential-bearing input.
        message = str(error) if type(error) is ValueError else "Release verification failed: invalid or unavailable input"
        print(message, file=sys.stderr)
        sys.exit(1)
