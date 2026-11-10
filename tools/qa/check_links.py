"""Check every relative link and #anchor in the Markdown files of a lab repository.

Delivery documents chain to each other with relative links ("Start of the path:
[README.md](README.md#delivery-path)", "**Next:** ..."), so one renamed heading or file breaks
the chain. This tool finds those breaks before a push.

What it checks, in every .md file outside the skipped folders:
  * Inline links and images: [text](path), ![alt](path), with optional titles and <...> targets.
  * Reference definitions: [label]: path
  * HTML links and images: <a href="...">, <img src="...">
  * Anchors (#heading) in the same file or in another Markdown file, using GitHub's heading slug
    rules: the rendered heading text in lowercase, punctuation removed, each space turned into a
    hyphen, and -1, -2 appended to repeated headings. Explicit <a name="..."> and id="..."
    anchors count too.
Links with a scheme (https:, mailto:, data:) are not checked. Links inside fenced code blocks,
inline code spans and HTML comments are ignored, as GitHub does not render them as links.

Problems reported (one line each, with file and line number):
  MISSING  the target file or folder does not exist
  ANCHOR   the target exists but has no heading or anchor with that slug
  CASE     the target exists only with different letter case: it works on Windows and macOS
           but is broken on GitHub, which is case-sensitive
  OUTSIDE  the target is outside the repository
  IGNORED  the target exists locally but git ignores it, so it is missing on GitHub

Usage:
    python tools/qa/check_links.py [repo] [--skip-dir NAME ...] [--no-images]

    repo          the lab repository (default: the current folder)
    --skip-dir    a folder name to skip, in addition to .git, node_modules, .venv, venv,
                  __pycache__, .vs, .vscode and .idea (repeatable)
    --no-images   do not check image targets (lint-lab.ps1 also checks them)

Exit code: 0 when every link resolves, 1 when there is a problem, 2 on a usage error.
Requires Python 3.11+ and the standard library only (git is used when available).
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

DEFAULT_SKIP = {".git", "node_modules", ".venv", "venv", "__pycache__", ".vs", ".vscode", ".idea"}

FENCE = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")
ATX = re.compile(r"^ {0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*$")
SETEXT = re.compile(r"^ {0,3}(=+|-+)[ \t]*$")
CODE_SPAN = re.compile(r"(`+)(?:.+?)\1")
COMMENT = re.compile(r"<!--.*?-->")
# [text](target "title") and ![alt](target), with one level of nested brackets in the text.
INLINE = re.compile(r"(!?)\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*(<[^>\n]*>|(?:[^()\s]|\([^()\s]*\))+)(?:\s+(?:\"[^\"]*\"|'[^']*'|\([^)]*\)))?\s*\)")
REFDEF = re.compile(r"^ {0,3}\[[^\]]+\]:\s*(<[^>\n]*>|\S+)")
HTML_LINK = re.compile(r"<(a|img)\b[^>]*?\b(href|src)\s*=\s*([\"'])(.*?)\3", re.IGNORECASE)
HTML_ANCHOR = re.compile(r"<[a-z][^>]*?\b(?:id|name)\s*=\s*([\"'])(.*?)\1", re.IGNORECASE)
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.\-]*:")


# ==== GitHub heading slugs =====================================================================

def heading_text(markdown: str) -> str:
    """The text GitHub renders for a heading's Markdown source."""
    text = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", markdown)          # images render no text
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)          # links keep their text
    text = re.sub(r"\[([^\]]*)\]\[[^\]]*\]", r"\1", text)         # reference links too
    text = re.sub(r"<[^>]+>", "", text)                           # inline HTML, inject tags
    text = re.sub(r"(`+)(.+?)\1", r"\2", text)                    # code spans keep content
    text = re.sub(r"(\*\*|__)(.+?)\1", r"\2", text)               # strong emphasis
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?!\w)", r"\1", text)
    text = re.sub(r"(?<![\w_])_(?!\s)(.+?)(?<!\s)_(?![\w_])", r"\1", text)
    text = text.replace("\\", "")
    return text.strip()


def slug(markdown: str) -> str:
    """GitHub's anchor for a heading: lowercase, punctuation removed, spaces to hyphens."""
    text = heading_text(markdown).lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def fenced_lines(text: str):
    """Yield (line number, line, inside a fenced code block)."""
    fence = None
    for number, line in enumerate(text.splitlines(), start=1):
        m = FENCE.match(line)
        if fence is None and m:
            fence = (m.group(1)[0], len(m.group(1)))
            yield number, line, True
            continue
        if fence is not None:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= fence[1] and not m.group(2).strip():
                fence = None
            yield number, line, True
            continue
        yield number, line, False


_anchor_cache: dict[Path, set[str]] = {}


def anchors(path: Path) -> set[str]:
    """Every anchor GitHub generates or the page defines explicitly."""
    if path in _anchor_cache:
        return _anchor_cache[path]
    found: set[str] = set()
    counts: dict[str, int] = {}

    def add(heading: str) -> None:
        base = slug(heading)
        n = counts.get(base, 0)
        found.add(base if n == 0 else f"{base}-{n}")
        counts[base] = n + 1

    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        text = ""
    previous = ""
    for _, line, in_code in fenced_lines(text):
        if in_code:
            previous = ""
            continue
        m = ATX.match(line)
        if m:
            add(re.sub(r"[ \t]+#+[ \t]*$", "", m.group(2) or ""))
            previous = ""
            continue
        s = SETEXT.match(line)
        if s and previous.strip() and not re.match(r"^\s*([-*+>|]|\d+[.)])", previous):
            add(previous.strip())
            previous = ""
            continue
        for a in HTML_ANCHOR.finditer(line):
            found.add(a.group(2))
        previous = line
    _anchor_cache[path] = found
    return found


# ==== Link extraction ==========================================================================

def links(text: str, images: bool):
    """Yield (line number, target) for every relative link outside code and comments."""
    in_comment = False
    for number, line, in_code in fenced_lines(text):
        if in_code:
            continue
        if in_comment:
            end = line.find("-->")
            if end < 0:
                continue
            line = line[end + 3:]
            in_comment = False
        line = COMMENT.sub("", line)
        start = line.find("<!--")
        if start >= 0:
            line = line[:start]
            in_comment = True
        line = CODE_SPAN.sub("", line)
        for m in INLINE.finditer(line):
            if m.group(1) and not images:
                continue
            yield number, m.group(2)
        m = REFDEF.match(line)
        if m:
            yield number, m.group(1)
        for m in HTML_LINK.finditer(line):
            if m.group(1).lower() == "img" and not images:
                continue
            yield number, m.group(4)


def exact_case(root: Path, rel_parts: list[str]) -> str | None:
    """The on-disk spelling when the path exists only with different letter case, else None."""
    current = root
    actual = []
    mismatch = False
    for part in rel_parts:
        if part in ("", "."):
            continue
        if part == "..":
            current = current.parent
            actual.append(part)
            continue
        try:
            entries = os.listdir(current)
        except OSError:
            return None
        if part in entries:
            actual.append(part)
            current = current / part
            continue
        match = next((e for e in entries if e.lower() == part.lower()), None)
        if match is None:
            return None
        mismatch = True
        actual.append(match)
        current = current / match
    return "/".join(actual) if mismatch else None


def git_ignored(root: Path, rel_paths: list[str]) -> set[str]:
    """The subset of repo-relative paths that git ignores and does not track (empty without git)."""
    if not rel_paths:
        return set()
    try:
        proc = subprocess.run(["git", "-C", str(root), "check-ignore", "--stdin", "-z"],
                              input="\0".join(rel_paths) + "\0", capture_output=True, text=True, encoding="utf-8",
                              timeout=60)
    except (OSError, subprocess.SubprocessError):
        return set()
    if proc.returncode not in (0, 1):
        return set()
    return {p for p in proc.stdout.split("\0") if p}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Check relative Markdown links and anchors in a lab repository.")
    parser.add_argument("repo", nargs="?", default=".", help="the lab repository (default: current folder)")
    parser.add_argument("--skip-dir", action="append", default=[], metavar="NAME", help="folder name to skip (repeatable)")
    parser.add_argument("--no-images", action="store_true", help="do not check image targets")
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    root = Path(args.repo).resolve()
    if not root.is_dir():
        parser.error(f"{root} is not a folder")
    skip = DEFAULT_SKIP | set(args.skip_dir)
    md_files = sorted(p for p in root.rglob("*.md")
                      if p.is_file() and not (set(p.relative_to(root).parts[:-1]) & skip))

    problems: list[str] = []
    checked = 0
    existing: dict[str, list[str]] = {}   # repo-relative target -> places that link to it
    for md in md_files:
        rel_md = md.relative_to(root).as_posix()
        text = md.read_text(encoding="utf-8", errors="replace")
        for number, raw in links(text, images=not args.no_images):
            target = raw[1:-1].strip() if raw.startswith("<") and raw.endswith(">") else raw.strip()
            if not target or SCHEME.match(target) or target.startswith("//"):
                continue
            checked += 1
            where = f"{rel_md}:{number}"
            path_part, _, anchor = target.partition("#")
            path_part = unquote(path_part.split("?", 1)[0])
            anchor = unquote(anchor)
            if not path_part:
                dest = md
            elif path_part.startswith("/"):
                dest = (root / path_part.lstrip("/"))
            else:
                dest = md.parent / path_part
            dest = Path(os.path.normpath(dest))
            try:
                rel_dest = dest.relative_to(root)
            except ValueError:
                problems.append(f"OUTSIDE  {where}  ->  {target}")
                continue
            on_disk = exact_case(root, list(rel_dest.parts))
            if not dest.exists() and not on_disk:
                problems.append(f"MISSING  {where}  ->  {target}")
                continue
            if on_disk:
                problems.append(f"CASE     {where}  ->  {target}  (on disk: {on_disk})")
                continue
            if dest != md:
                existing.setdefault(rel_dest.as_posix(), []).append(f"{where}  ->  {target}")
            if anchor and dest.is_file() and dest.suffix.lower() == ".md" and anchor not in anchors(dest):
                problems.append(f"ANCHOR   {where}  ->  {target}")
    for rel in sorted(git_ignored(root, sorted(existing))):
        for place in existing.get(rel, []):
            problems.append(f"IGNORED  {place}  (git ignores {rel}, so it is not on GitHub)")

    for line in problems:
        print(line)
    print(f"checked {len(md_files)} Markdown files and {checked} relative links: {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
