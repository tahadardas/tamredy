#!/usr/bin/env python3
"""Focused, isolated release checks. Docker and the production host are never contacted."""
import hashlib
import importlib.util
import io
import json
import tarfile
import tempfile
import unittest
from pathlib import Path


def import_script(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ROOT = Path(__file__).resolve().parent.parent
checks = import_script("release_checks", ROOT / "infra/docker/release/release-checks.py")
packaging = import_script("package_source", ROOT / "scripts/package-rc3-source.py")


class ReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.flags = {name: "false" for name in (
            "LIVE_LOCATION_REDIS_ENABLED", "LOCATION_POSTGRES_FALLBACK_ENABLED", "SCHEDULED_VISITS_ENABLED",
            "OPEN_MARKETPLACE_ENABLED", "OPEN_DISPATCH_ENABLED", "GUARDIAN_NIGHT_POLICY_ENABLED",
            "GUARDIAN_ROUTING_ENABLED", "PUSH_ENABLED", "REALTIME_ENABLED", "VOICE_ENABLED")}
        self.flags["TAMREEDY_RELEASE"] = "3.1.0-rc.3"
        self.data = {"name": "tamreedy", "services": {
            "api": {"environment": dict(self.flags), "volumes": [{"source": "uploads", "target": "/data/uploads"}]},
            "worker": {"environment": dict(self.flags)},
        }, "volumes": {"uploads": {"name": "tamreedy_uploads"}}}

    def test_compose_refuses_flag_divergence_and_wrong_volume(self):
        checks.validate_compose(self.data, "tamreedy_uploads")
        with self.assertRaisesRegex(ValueError, "uploads volume"):
            checks.validate_compose(self.data, "wrong-volume")
        self.data["services"]["worker"]["environment"]["LIVE_LOCATION_REDIS_ENABLED"] = "true"
        with self.assertRaisesRegex(ValueError, "LIVE_LOCATION_REDIS_ENABLED"):
            checks.validate_compose(self.data, "tamreedy_uploads")

    def test_worker_credential_required_only_when_push_enabled(self):
        for service in ("api", "worker"):
            self.data["services"][service]["environment"]["PUSH_ENABLED"] = "true"
        with self.assertRaisesRegex(ValueError, "Worker credential file"):
            checks.validate_compose(self.data, "tamreedy_uploads")
        self.data["services"]["worker"]["environment"]["FCM_SERVICE_ACCOUNT_JSON"] = json.dumps(
            {"project_id": "synthetic", "client_email": "example.invalid", "private_key": "synthetic"})
        checks.validate_compose(self.data, "tamreedy_uploads")

    def test_archive_files_and_migration_manifest_must_match(self):
        release = self.root / "release"
        release.mkdir()
        migrations = release / "infra/db/migrations"
        migrations.mkdir(parents=True)
        transfer = self.root / "transfer"
        transfer.mkdir()
        source = "1" * 40
        files = {"release-source.json": json.dumps({"sourceCommit": source}).encode(),
                 "infra/db/migrations/080_schema.sql": b"SELECT 1;"}
        bundle = transfer / "tamreedy-server.tar.gz"
        with tarfile.open(bundle, "w:gz") as archive:
            for name, data in files.items():
                item = tarfile.TarInfo(name)
                item.size = len(data)
                archive.addfile(item, io.BytesIO(data))
                (release / name).write_bytes(data)
        bundle_hash = hashlib.sha256(bundle.read_bytes()).hexdigest()
        manifest = transfer / "RELEASE_MANIFEST.json"
        body = {"sourceCommit": source, "requiredMigrations": ["080_schema.sql"],
                "sourceBundle": [{"path": bundle.name, "sha256": bundle_hash}], "prebuiltImagesAvailable": False}
        manifest.write_text(json.dumps(body), encoding="utf-8")
        (transfer / "SHA256SUMS.txt").write_text(
            f"{bundle_hash}  {bundle.name}\n{hashlib.sha256(manifest.read_bytes()).hexdigest()}  {manifest.name}\n",
            encoding="utf-8")
        checks.verify_bundle(manifest, release, transfer)
        (migrations / "081_unapproved.sql").write_bytes(b"SELECT 1;")
        with self.assertRaisesRegex(ValueError, "outside its archive"):
            checks.verify_bundle(manifest, release, transfer)
        (migrations / "080_schema.sql").write_bytes(b"SELECT 2;")
        with self.assertRaisesRegex(ValueError, "Extracted release differs"):
            checks.verify_bundle(manifest, release, transfer)

    def test_archive_allowlist_excludes_sensitive_paths(self):
        from pathlib import PurePosixPath
        for name in ("infra/docker/.env", "apps/api/production.dump", "infra/docker/secrets/fcm.json",
                     "apps/api/firebase-service-account.json", "apps/api/node_modules/native.bin",
                     "apps/api/key.pem", "apps/api/id_ed25519"):
            self.assertFalse(packaging.allow_file(PurePosixPath(name)), name)
        self.assertTrue(packaging.allow_file(PurePosixPath("infra/docker/.env.prod.example")))


if __name__ == "__main__":
    unittest.main()
