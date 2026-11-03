#!/usr/bin/env python3
"""Check distributable text sources without reading local credentials or build caches."""
from pathlib import Path
import os
import re
import sys

PROJECT_DIRECTORY = Path(__file__).resolve().parent.parent
IGNORED_DIRECTORIES = {".git", ".tools", "dist", "build", ".build", ".gradle", ".swiftpm", ".idea", ".codex", ".agents"}
IGNORED_FILES = {"local.properties", ".DS_Store"}
TEXT_SUFFIXES = {".swift", ".kt", ".kts", ".md", ".py", ".sh", ".xml", ".plist", ".properties", ".csv", ".json", ".yml", ".yaml", ".svg"}
RULES = {
    "personal home path": re.compile(r"/(?:Users|home)/[A-Za-z0-9_.-]+/"),
    "embedded private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "cloud access key": re.compile(r"\bAKIA[A-Z0-9]{16}\b"),
    "access token": re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
}


def source_paths():
    for directory, subdirectories, filenames in os.walk(PROJECT_DIRECTORY):
        subdirectories[:] = [name for name in subdirectories if name not in IGNORED_DIRECTORIES]
        for filename in filenames:
            path = Path(directory) / filename
            if filename not in IGNORED_FILES and path.suffix in TEXT_SUFFIXES:
                yield path


def main():
    findings = []
    for path in source_paths():
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for category, pattern in RULES.items():
                if pattern.search(line):
                    findings.append(f"{path.relative_to(PROJECT_DIRECTORY)}:{line_number}: {category}")
    if findings:
        print("\n".join(findings))
        return 1
    print("Source privacy checks passed (generated/local-only files excluded).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
