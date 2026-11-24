"""Validate release branches and build the installable Tile Markers ZIP."""

import argparse
import json
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[2]
TAG_VERSION = re.compile(r"v?([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)")


def version_from_tag(tag):
    match = TAG_VERSION.fullmatch(tag)
    if not match:
        raise ValueError(f"expected a version such as 1.2.3 or v1.2.3, got {tag!r}")
    return match.group(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check").add_argument("branch")
    package = commands.add_parser("package")
    package.add_argument("tag")
    package.add_argument("output", type=Path)
    args = parser.parse_args()

    if args.command == "check" and not args.branch.startswith("release/"):
        return
    try:
        tag = args.branch.removeprefix("release/") if args.command == "check" else args.tag
        version = version_from_tag(tag)
        manifest = json.loads((ROOT / "plugin.json").read_text(encoding="utf-8"))
        if args.command == "check":
            if manifest["version"] != version:
                raise ValueError(f"plugin.json version must be {version!r}, found {manifest['version']!r}")
            print(version)
            return

        manifest["version"] = version
        # Published plugins resolve dependencies by mod.io ID, not local folder name.
        manifest["requiredDependencies"]["prettyui"] = 6398181
        with ZipFile(args.output, "w", ZIP_DEFLATED) as archive:
            archive.writestr("plugin.json", json.dumps(manifest, indent=2) + "\n")
            archive.write(ROOT / "main.lua", "main.lua")
            for path in sorted((ROOT / "src").rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(ROOT))
    except (ValueError, KeyError, OSError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
