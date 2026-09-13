#!/usr/bin/env python3
"""Check authored pages and their local links in an assembled Pages site."""

import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.ids = set()
        self.links = []
        self.errors = []
        self.feed(path.read_text(encoding="utf-8"))

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            if attrs["id"] in self.ids:
                self.errors.append(f"duplicate ID: {attrs['id']}")
            self.ids.add(attrs["id"])
        for key in ("href", "src"):
            if key in attrs:
                self.links.append(attrs[key])


def check(root):
    errors = []
    pages = sorted(root.glob("*.html"))
    if not (root / "index.html").is_file():
        errors.append("missing index.html")
    parsed = {}
    for path in pages:
        page = parsed.setdefault(path, Page(path))
        errors.extend(f"{path.name}: {error}" for error in page.errors)
        for link in page.links:
            url = urlsplit(link)
            if url.scheme or url.netloc:
                continue
            local = unquote(url.path)
            if local.startswith("/ocaml-aho-corasick/"):
                target = root / local.removeprefix("/ocaml-aho-corasick/")
            elif local.startswith("/"):
                target = root / local.lstrip("/")
            else:
                target = path.parent / local if local else path
            target = target.resolve()
            if target.is_dir():
                target /= "index.html"
            if not target.is_relative_to(root) or not target.is_file():
                errors.append(f"{path.name}: missing local target: {link}")
            elif url.fragment and target.suffix == ".html":
                if target not in parsed:
                    parsed[target] = Page(target)
                if unquote(url.fragment) not in parsed[target].ids:
                    errors.append(f"{path.name}: missing anchor: {link}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Checked {len(pages)} authored pages and their local links.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/check_site.py ASSEMBLED_SITE")
    check(Path(sys.argv[1]).resolve())
