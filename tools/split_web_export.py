from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path


MAX_FILE_BYTES = 25_000_000
CHUNK_BYTES = 24_000_000
TARGETS = {
	"index.pck": "application/octet-stream",
	"index.wasm": "application/wasm",
}
LOADER_TAG = '<script src="web_chunk_loader.js"></script>'
GODOT_LOADER_TAG = '<script src="index.js"></script>'


def split_file(source: Path) -> dict[str, object]:
	for stale_part in source.parent.glob(f"{source.name}.part*"):
		stale_part.unlink()

	parts: list[dict[str, object]] = []
	full_digest = hashlib.sha256()
	with source.open("rb") as input_file:
		part_index = 0
		while True:
			data = input_file.read(CHUNK_BYTES)
			if not data:
				break
			part_name = f"{source.name}.part{part_index:02d}"
			part_path = source.parent / part_name
			part_path.write_bytes(data)
			full_digest.update(data)
			parts.append(
				{
					"name": part_name,
					"sha256": hashlib.sha256(data).hexdigest(),
					"size": len(data),
				}
			)
			part_index += 1

	return {
		"parts": parts,
		"sha256": full_digest.hexdigest(),
		"size": source.stat().st_size,
	}


def patch_html(html_path: Path) -> None:
	html = html_path.read_text(encoding="utf-8")
	if LOADER_TAG in html:
		return
	if GODOT_LOADER_TAG not in html:
		raise RuntimeError(f"Godot loader tag not found in {html_path}")
	html = html.replace(GODOT_LOADER_TAG, f"{LOADER_TAG}\n\t\t{GODOT_LOADER_TAG}", 1)
	html_path.write_text(html, encoding="utf-8")


def verify_size_limit(web_dir: Path) -> None:
	oversized = [
		path
		for path in web_dir.iterdir()
		if path.is_file() and path.stat().st_size > MAX_FILE_BYTES
	]
	if oversized:
		details = ", ".join(f"{path.name}={path.stat().st_size}" for path in oversized)
		raise RuntimeError(f"Web files exceed {MAX_FILE_BYTES} bytes: {details}")


def split_web_export(project_root: Path) -> None:
	web_dir = project_root / "build" / "web"
	manifest: dict[str, object] = {"files": {}, "version": 1}

	for file_name, content_type in TARGETS.items():
		source = web_dir / file_name
		if not source.is_file():
			raise FileNotFoundError(f"Run the Godot Web export first; missing {source}")
		metadata = split_file(source)
		metadata["content_type"] = content_type
		manifest["files"][file_name] = metadata

	manifest_path = web_dir / "index.chunks.json"
	manifest_path.write_text(
		json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
		encoding="utf-8",
	)
	shutil.copyfile(project_root / "tools" / "web_chunk_loader.js", web_dir / "web_chunk_loader.js")
	patch_html(web_dir / "index.html")

	for file_name in TARGETS:
		(web_dir / file_name).unlink()

	verify_size_limit(web_dir)


def main() -> None:
	parser = argparse.ArgumentParser(
		description="Split large Godot Web export files below the hosting file-size limit."
	)
	parser.add_argument(
		"--project-root",
		type=Path,
		default=Path(__file__).resolve().parents[1],
		help="Godot project root containing build/web (defaults to this repository).",
	)
	args = parser.parse_args()
	split_web_export(args.project_root.resolve())


if __name__ == "__main__":
	main()
