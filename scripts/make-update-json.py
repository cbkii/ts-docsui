#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_prop(path: Path) -> dict[str, str]:
    props: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            props[key.strip()] = value.strip()
    return props


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Magisk update.json for a release asset.")
    parser.add_argument("--module-dir", type=Path, default=Path("module"))
    parser.add_argument("--repository", required=True, help="owner/repo")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--zip-name", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    props = parse_prop(args.module_dir / "module.prop")
    version_code = props["versionCode"]
    payload = {
        "version": props["version"],
        "versionCode": int(version_code, 10),
        "zipUrl": f"https://github.com/{args.repository}/releases/download/{args.tag}/{args.zip_name}",
        "changelog": f"https://github.com/{args.repository}/releases/tag/{args.tag}",
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
