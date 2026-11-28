#!/usr/bin/env python3
"""Build checked Linux release archives from one committed source snapshot."""
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path, PurePosixPath
from tempfile import TemporaryDirectory


SOURCE_PATHS = (
    "package.json", "pnpm-workspace.yaml", "pnpm-lock.yaml", ".dockerignore", ".env.example",
    "apps/api", "apps/worker", "apps/admin_web", "packages/backend-policy", "infra/db", "infra/docker",
)
RELEASE_FILES = ("common.sh", "preflight.sh", "backup.sh", "deploy.sh", "verify.sh", "rollback.sh",
                 "images.override.yml", "release-checks.py")
REQUIRED = set(SOURCE_PATHS[:5]) | {
    "apps/api/package.json", "apps/worker/package.json", "apps/admin_web/package.json",
    "infra/db/migrate.mjs", "infra/docker/docker-compose.prod.yml", "infra/docker/Dockerfile.api",
    "infra/docker/Dockerfile.worker", "infra/docker/Dockerfile.admin", "infra/docker/nginx-admin.conf",
    "infra/docker/coturn.conf", "packages/backend-policy/schema.mjs",
    *{f"infra/docker/release/{name}" for name in RELEASE_FILES},
}
SECRET_STEM = re.compile(r"(?:^|[-_.])(?:fcm|firebase|service[-_]account|secrets?)(?:[-_.]|$)", re.I)
CREDENTIAL = re.compile(rb"-----BEGIN [A-Z ]*PRIVATE KEY-----|\b(?:gh[pousr]_|github_pat_)[A-Za-z0-9_]{20,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}")


def hashes(path):
    with path.open("rb") as stream:
        return {"path": path.name, "size": path.stat().st_size,
                "sha256": hashlib.file_digest(stream, "sha256").hexdigest()}


def allow_file(path):
    name = path.name.lower()
    forbidden = {"node_modules", "dist", "coverage", "build", "cache", ".cache", ".git", "secrets", "uploads",
                 "backup", "backups", "uploads-data", "patient-files"}
    return (not forbidden.intersection(part.lower() for part in path.parts)
            and (not name.startswith(".env") or name in (".env.example", ".env.prod.example"))
            and name not in {"key.properties", "local.properties", "id_rsa", "id_ed25519", "id_ecdsa", "id_dsa",
                             "google-services.json", "googleservice-info.plist"}
            and not name.endswith((".tsbuildinfo", ".log", ".dump", ".bak", ".zip", ".tar", ".tar.gz",
                                   ".jks", ".keystore", ".pem", ".p12", ".key", ".sqlite", ".sqlite3"))
            and not (name.endswith(".json") and SECRET_STEM.search(name)))


def copy_source(snapshot, stage):
    files = {}
    with tarfile.open(snapshot) as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            if member.isdir() or not allow_file(path):
                continue
            if path.is_absolute() or ".." in path.parts or not member.isfile():
                raise ValueError("Unexpected source entry type or path")
            file = stage.joinpath(*path.parts)
            file.parent.mkdir(parents=True, exist_ok=True)
            raw = archive.extractfile(member).read()
            if CREDENTIAL.search(raw):
                raise ValueError(f"Credential pattern in committed source: {path}")
            file.write_bytes(raw)
            member.mode = 0o755 if path.suffix == ".sh" else 0o644
            member.pax_headers = {}
            files[str(path)] = member
    expected_schema = stage / "packages/backend-policy/schema.mjs"
    migrations = {item.name for item in (stage / "infra/db/migrations").glob("*.sql")}
    declared = set(re.findall(r'"([0-9]+_[A-Za-z0-9_]+\.sql)"', expected_schema.read_text(encoding="utf-8")))
    if not migrations or migrations != declared:
        raise ValueError("Committed SQL migrations and shared release manifest differ")
    if not REQUIRED <= files.keys():
        raise ValueError("Missing release source: " + ", ".join(sorted(REQUIRED - files.keys())))
    if not any("commission" in name.lower() for name in migrations):
        raise ValueError("Missing commission policy migration")
    return files, sorted(migrations)


def archives(stage, files, output):
    tar_path, zip_path = (output / name for name in ("tamreedy-server.tar.gz", "tamreedy-server.zip"))
    with tarfile.open(tar_path, "w:gz", compresslevel=6) as archive:
        for name, entry in sorted(files.items()):
            with (stage / name).open("rb") as inp:
                archive.addfile(entry, inp)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name, entry in sorted(files.items()):
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = (0o100000 | entry.mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, (stage / name).read_bytes())
    with tarfile.open(tar_path) as tar, zipfile.ZipFile(zip_path) as zipped:
        if set(tar.getnames()) != set(files) or set(zipped.namelist()) != set(files) or zipped.testzip():
            raise ValueError("Unexpected or damaged release archive contents")
        for name in files:
            actual = (stage / name).read_bytes()
            if tar.extractfile(name).read() != actual or zipped.read(name) != actual:
                raise ValueError("Archive integrity check failed")
    return [tar_path, zip_path]


def main():
    repository, output = map(Path, sys.argv[1:3])
    commit = subprocess.check_output(["git", "rev-parse", "--verify", sys.argv[3] + "^{commit}"],
                                     cwd=repository, text=True).strip()
    arch = sys.argv[4]
    if arch not in ("source-build", "linux/amd64", "linux/arm64"):
        raise ValueError("Explicit Linux image architecture is required")
    output.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="tamreedy-rc3-", dir=output) as temp:
        workspace = Path(temp)
        stage = workspace / "source"
        stage.mkdir()
        snapshot = workspace / "snapshot.tar"
        subprocess.run(["git", "archive", "--format=tar", "--output", str(snapshot), commit, "--", *SOURCE_PATHS],
                       cwd=repository, check=True)
        files, migrations = copy_source(snapshot, stage)
        marker = json.dumps({"sourceCommit": commit}, indent=2).encode() + b"\n"
        name = "release-source.json"
        (stage / name).write_bytes(marker)
        info = tarfile.TarInfo(name)
        info.size = len(marker)
        files[name] = info
        bundles = archives(stage, files, workspace)
        tags = {service: f"tamreedy-{service}:rc3-{commit[:12]}" for service in ("api", "worker", "admin")}
        prebuilt = None
        if arch != "source-build":
            for service, tag in tags.items():
                subprocess.run(["docker", "build", "--platform", arch, "-f", f"infra/docker/Dockerfile.{service}",
                                "-t", tag, "."], cwd=stage, check=True)
                target = subprocess.check_output(["docker", "image", "inspect", "--format", "{{.Os}}/{{.Architecture}}", tag], text=True).strip()
                if target != arch:
                    raise ValueError("Docker image architecture does not match stated release target")
            docker_tar = workspace / "images.tar"
            subprocess.run(["docker", "save", "-o", str(docker_tar), *tags.values()], check=True)
            image = workspace / "tamreedy-images-linux.tar.gz"
            import gzip
            with docker_tar.open("rb") as raw, gzip.open(image, "wb", compresslevel=6) as compressed:
                shutil.copyfileobj(raw, compressed)
            with tarfile.open(image) as saved:
                saved_manifest = json.load(saved.extractfile("manifest.json"))
                actual_tags = {tag for item in saved_manifest for tag in item.get("RepoTags", [])}
                if actual_tags != set(tags.values()):
                    raise ValueError("Docker export has an unexpected image set")
            image_dir = output / "server-images"
            image_dir.mkdir(exist_ok=True)
            prebuilt = hashes(image)
            prebuilt["path"] = "server-images/" + image.name
            shutil.move(image, image_dir / image.name)
        for bundle in bundles:
            shutil.move(bundle, output / bundle.name)
        script_dir = output / "scripts"
        script_dir.mkdir(exist_ok=True)
        release = stage / "infra/docker/release"
        for name in RELEASE_FILES:
            shutil.copyfile(release / name, script_dir / name)
        shutil.copyfile(release / "DEPLOY_AR.txt", output / "DEPLOY_AR.txt")
        result = {"sourceCommit": commit, "serverArchitecture": arch, "requiredMigrations": migrations,
                  **{f"{service}ImageTag": tag for service, tag in tags.items()},
                  "sourceBundle": [hashes(output / bundle.name) for bundle in bundles],
                  "prebuiltImagesAvailable": prebuilt is not None, "prebuiltImagesArchive": prebuilt}
        (output / "SERVER_BUNDLE_EVIDENCE.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8", newline="\n")
        print(json.dumps(result))


if __name__ == "__main__":
    main()
