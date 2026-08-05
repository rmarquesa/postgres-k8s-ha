#!/usr/bin/env python3
"""Validate the dependency-free GitHub Pages site."""

from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"


class SiteParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: set[str] = set()
        self.links: list[str] = []
        self.assets: list[str] = []
        self.h1_count = 0
        self.lang: str | None = None
        self.canonical: str | None = None
        self.errors: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "html":
            self.lang = values.get("lang")
        if tag == "h1":
            self.h1_count += 1
        if identifier := values.get("id"):
            if identifier in self.ids:
                self.errors.append(f"duplicate id: {identifier}")
            self.ids.add(identifier)
        if tag == "a":
            href = values.get("href")
            if not href:
                self.errors.append("anchor without href")
            else:
                self.links.append(href)
        if tag == "link":
            href = values.get("href")
            if values.get("rel") == "canonical":
                self.canonical = href
            elif href:
                self.assets.append(href)
        if tag in {"img", "source", "script"}:
            source = values.get("src")
            if source:
                self.assets.append(source)
        if tag == "img" and "alt" not in values:
            self.errors.append(f"image without alt: {values.get('src', '<unknown>')}")


def is_external(value: str) -> bool:
    return urlparse(value).scheme in {"http", "https", "mailto"}


def main() -> int:
    html_path = SITE / "index.html"
    css_path = SITE / "styles.css"
    if not html_path.is_file() or not css_path.is_file():
        print("ERROR: site/index.html and site/styles.css are required", file=sys.stderr)
        return 1

    html = html_path.read_text(encoding="utf-8")
    css = css_path.read_text(encoding="utf-8")
    parser = SiteParser()
    parser.feed(html)
    parser.close()

    errors = parser.errors
    if parser.lang != "en":
        errors.append("html lang must be en")
    if parser.h1_count != 1:
        errors.append(f"expected one h1, found {parser.h1_count}")
    if parser.canonical != "https://rmarquesa.github.io/postgres-k8s-ha/":
        errors.append("canonical URL is missing or incorrect")

    for href in parser.links:
        if href.startswith("#") and href[1:] not in parser.ids:
            errors.append(f"missing local anchor target: {href}")
        elif not href.startswith("#") and not is_external(href):
            target = (SITE / href.split("#", 1)[0]).resolve()
            if not target.is_file():
                errors.append(f"missing local link target: {href}")

    for asset in parser.assets:
        if asset.startswith("data:") or is_external(asset):
            continue
        target = (SITE / asset.split("?", 1)[0]).resolve()
        if not target.is_file():
            errors.append(f"missing local asset: {asset}")

    if css.count("{") != css.count("}"):
        errors.append("unbalanced CSS braces")

    public_text = "\n".join(
        path.read_text(encoding="utf-8")
        for path in SITE.rglob("*")
        if path.is_file()
    )
    forbidden = {
        "personal path": r"/Users/|/home/[A-Za-z0-9._-]+/",
        "private IPv4": r"\b(?:10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)\d{1,3}(?:\.\d{1,3}){2}\b",
        "private key": r"BEGIN [A-Z ]*PRIVATE KEY",
        "credential assignment": r"(?i)(?:password|secret[_-]?key|access[_-]?key)\s*[:=]\s*[^<\s]+",
        "kubeconfig content": r"(?m)^\s*(?:client-certificate-data|client-key-data):",
    }
    for label, pattern in forbidden.items():
        if re.search(pattern, public_text):
            errors.append(f"forbidden {label} detected")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"OK: site validated ({len(parser.ids)} ids, {len(parser.links)} links)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
