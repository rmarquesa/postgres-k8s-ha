#!/usr/bin/env python3
"""Validate local Markdown links without external dependencies."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"(?<!!)\[[^]]+\]\(([^)]+)\)")


def main() -> int:
    errors: list[str] = []
    files = sorted(ROOT.rglob("*.md"))

    for source in files:
        text = source.read_text(encoding="utf-8")
        if not text.endswith("\n"):
            errors.append(f"{source.relative_to(ROOT)}: missing final newline")

        for target in LINK.findall(text):
            target = target.strip().split("#", 1)[0]
            if not target or "://" in target or target.startswith(("mailto:", "/")):
                continue
            resolved = (source.parent / target).resolve()
            if not resolved.exists():
                errors.append(
                    f"{source.relative_to(ROOT)}: broken link {target!r}"
                )

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"OK: {len(files)} Markdown files; local links valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
