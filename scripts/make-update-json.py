#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from scripts.release_assets import atomic_write_json, validate_release_assets
except ModuleNotFoundError:
    from release_assets import atomic_write_json, validate_release_assets


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate and validate Magisk update metadata for one exact release variant."
    )
    parser.add_argument("--module-dir", type=Path, default=Path("module"))
    parser.add_argument("--repository", required=True, help="owner/repo")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--zip-name", required=True)
    parser.add_argument("--variant", choices=("final", "debug"), default="final")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)

    zip_path = args.out.parent / args.zip_name
    checksum_path = zip_path.with_suffix(zip_path.suffix + ".sha256")
    try:
        payload, digest = validate_release_assets(
            module_dir=args.module_dir,
            repository=args.repository,
            tag=args.tag,
            zip_path=zip_path,
            checksum_path=checksum_path,
            variant=args.variant,
        )
        atomic_write_json(args.out, payload)
        print(f"OK {args.variant} update metadata: {args.out}")
        print(f"zip={zip_path}")
        print(f"sha256={digest}")
        return 0
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
