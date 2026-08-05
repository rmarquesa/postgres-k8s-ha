#!/usr/bin/env python3
"""Extract PrometheusRule.spec.groups into a promtool rules file."""

from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} PROMETHEUS_RULE OUTPUT", file=sys.stderr)
        return 2

    lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
    try:
        start = lines.index("  groups:")
    except ValueError:
        print("ERROR: PrometheusRule spec.groups not found", file=sys.stderr)
        return 1

    output = [line[2:] if line.startswith("  ") else line for line in lines[start:]]
    if not any(line.startswith("  - name:") for line in output):
        print("ERROR: no Prometheus rule groups found", file=sys.stderr)
        return 1

    Path(sys.argv[2]).write_text("\n".join(output) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
