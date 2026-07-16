from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
WEB_DIR = PROJECT_ROOT / "build" / "web"
MANIFEST_PATH = WEB_DIR / "index.chunks.json"
MAX_FILE_BYTES = 25_000_000


class WebExportChunkTest(unittest.TestCase):
	def test_every_web_file_is_below_host_limit(self) -> None:
		oversized = {
			path.name: path.stat().st_size
			for path in WEB_DIR.iterdir()
			if path.is_file() and path.stat().st_size > MAX_FILE_BYTES
		}
		self.assertEqual({}, oversized)

	def test_manifest_parts_reconstruct_original_files(self) -> None:
		manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
		for original_name, metadata in manifest["files"].items():
			digest = hashlib.sha256()
			total_size = 0
			for part in metadata["parts"]:
				part_path = WEB_DIR / part["name"]
				data = part_path.read_bytes()
				self.assertEqual(part["size"], len(data))
				digest.update(data)
				total_size += len(data)
			self.assertEqual(metadata["size"], total_size)
			self.assertEqual(metadata["sha256"], digest.hexdigest())
			self.assertFalse((WEB_DIR / original_name).exists())

	def test_chunk_loader_runs_before_godot_loader(self) -> None:
		html = (WEB_DIR / "index.html").read_text(encoding="utf-8")
		chunk_loader = '<script src="web_chunk_loader.js"></script>'
		godot_loader = '<script src="index.js"></script>'
		self.assertIn(chunk_loader, html)
		self.assertLess(html.index(chunk_loader), html.index(godot_loader))


if __name__ == "__main__":
	unittest.main()
