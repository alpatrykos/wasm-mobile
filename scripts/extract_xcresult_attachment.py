#!/usr/bin/env python3

import shutil
import subprocess
import sys
import tempfile
import json
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: extract_xcresult_attachment.py <result_bundle> <attachment_name> <output_path>",
            file=sys.stderr,
        )
        return 1

    result_bundle = Path(sys.argv[1]).resolve()
    attachment_name = sys.argv[2]
    output_path = Path(sys.argv[3]).resolve()

    with tempfile.TemporaryDirectory() as temp_dir:
        export_dir = Path(temp_dir) / "attachments"
        subprocess.run(
            [
                "xcrun",
                "xcresulttool",
                "export",
                "attachments",
                "--path",
                str(result_bundle),
                "--output-path",
                str(export_dir),
            ],
            check=True,
        )

        manifest_path = export_dir / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        stem = Path(attachment_name).stem
        matches = []
        for test_entry in manifest:
            for attachment in test_entry.get("attachments", []):
                exported_name = attachment.get("exportedFileName", "")
                suggested_name = attachment.get("suggestedHumanReadableName", "")
                if suggested_name == attachment_name or Path(suggested_name).stem.startswith(stem):
                    matches.append(export_dir / exported_name)

        if len(matches) != 1:
            print(
                f"expected exactly one attachment named {attachment_name!r}, found {len(matches)}",
                file=sys.stderr,
            )
            return 1

        output_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(matches[0], output_path)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
