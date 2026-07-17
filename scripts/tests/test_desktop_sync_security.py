#!/usr/bin/env python3
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
IMPORT_SCRIPT = ROOT / "scripts" / "import-desktop-sync.py"
EXPORT_SCRIPT = ROOT / "scripts" / "export-desktop-sync.sh"


def load_import_module():
    spec = importlib.util.spec_from_file_location("import_desktop_sync", IMPORT_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DesktopSyncSecurityTests(unittest.TestCase):
    def test_import_rejects_links_even_when_their_names_are_in_bounds(self):
        importer = load_import_module()
        for member_type in (tarfile.SYMTYPE, tarfile.LNKTYPE):
            with self.subTest(member_type=member_type), tempfile.TemporaryDirectory() as temporary:
                temporary_path = Path(temporary)
                bundle = temporary_path / "bundle.tgz"
                with tarfile.open(bundle, "w:gz") as archive:
                    member = tarfile.TarInfo("nested/link")
                    member.type = member_type
                    member.linkname = "../../outside"
                    archive.addfile(member)

                with self.assertRaisesRegex(RuntimeError, "non-file archive member"):
                    importer.safe_extract(bundle, temporary_path / "extract")

    def test_import_accepts_regular_manifest(self):
        importer = load_import_module()
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            bundle = temporary_path / "bundle.tgz"
            content = json.dumps({"kind": "codex-desktop-project-sync"}).encode()
            with tarfile.open(bundle, "w:gz") as archive:
                member = tarfile.TarInfo("manifest.json")
                member.size = len(content)
                archive.addfile(member, io.BytesIO(content))

            destination = temporary_path / "extract"
            destination.mkdir()
            importer.safe_extract(bundle, destination)
            self.assertEqual((destination / "manifest.json").read_bytes(), content)

    def test_export_bundle_is_owner_only(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            codex_home = temporary_path / "codex"
            output = temporary_path / "output"
            codex_home.mkdir()
            (codex_home / ".codex-global-state.json").write_text(
                json.dumps({"active-workspace-roots": ["/workspace/example"]}),
                encoding="utf-8",
            )
            environment = os.environ.copy()
            environment["CODEX_HOME"] = str(codex_home)

            result = subprocess.run(
                [str(EXPORT_SCRIPT), "--out-dir", str(output)],
                check=True,
                capture_output=True,
                text=True,
                env=environment,
            )

            bundle = Path(result.stdout.strip())
            self.assertEqual(stat.S_IMODE(bundle.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
