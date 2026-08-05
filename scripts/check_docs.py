#!/usr/bin/env python3
"""Validate local Markdown links without external dependencies."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"(?<!!)\[[^]]+\]\(([^)]+)\)")
PORTUGUESE = re.compile(
    r"[áàâãéêíóôõúçÁÀÂÃÉÊÍÓÔÕÚÇ]"
    r"|\b(?:não|decisão|decisões|porquê|laboratório|produção|validação|"
    r"configuração|instalação|utilizador|ficheiro|armazenamento|recuperação|"
    r"aplicação|credenciais|segredos|réplica|réplicas|instância|instâncias|"
    r"nó|nós|três|ainda|apenas|este|esta|uma|quando)\b",
    re.IGNORECASE,
)


def main() -> int:
    errors: list[str] = []
    files = sorted(ROOT.rglob("*.md"))

    for source in files:
        text = source.read_text(encoding="utf-8")
        if not text.endswith("\n"):
            errors.append(f"{source.relative_to(ROOT)}: missing final newline")

        if match := PORTUGUESE.search(text):
            line = text.count("\n", 0, match.start()) + 1
            errors.append(
                f"{source.relative_to(ROOT)}:{line}: Portuguese text detected"
            )

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
