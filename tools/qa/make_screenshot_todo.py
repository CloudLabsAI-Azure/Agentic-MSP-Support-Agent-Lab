"""Build SCREENSHOT-TODO.md from the pending screenshot markers in a lab's guide pages.

While a lab is written, every screenshot that does not exist yet is a marker line in the guide:

    > **[SCREENSHOT PENDING: E1T2S3 | what the screenshot must show | source: capture]**

The ID names the place: E<exercise>T<task>S<step> (E1T2S3; E1T2-1S4 for sub-task 2.1) or
GS<n> on the getting-started page. A course of separate labs, where every lab is its own CloudLabs
lab and the IDs must stay unique across the course, may use <labid>-t<task>s<step> instead
(lab1a-t2s3, lab4f-t3s10). The source is "capture" (take it in the pilot), "reuse" (the
standard CloudLabs getting-started image) or "learn <url>" (a Microsoft Learn image to use as the
reference for framing).

This script reads the pages in the order masterdoc.json lists them (every Instructions/**/*.md
page when there is no masterdoc), collects the markers and writes SCREENSHOT-TODO.md: the
delivery path header (Phase 5 of 8, run the pilot), who captures and how long it takes, the
capture rules, one table per page with Microsoft Learn reference links, markers that could not
be read, and the Next line. Regenerate it after every guide edit; never edit it by hand.

Usage:
    python tools/qa/make_screenshot_todo.py [repo] [--out FILE] [--check]
                                             [--minutes-per-shot N] [--never-capture TEXT]

    repo                the lab repository (default: the current folder when it holds
                        masterdoc.json or Instructions, else the repository this script is in)
    --out               the file to write (default: SCREENSHOT-TODO.md in the repository)
    --check             write nothing; exit with code 1 when the file is missing or out of date
    --minutes-per-shot  capture time per screenshot for the time estimate (default: 3)
    --never-capture     a lab-specific item that must never appear in a screenshot, added to the
                        capture rules, for example "the AZURE_OPENAI_API_KEY line of .env"
                        (repeatable)

Exit code: 0 on success, 1 when --check finds the file out of date, 2 on a usage error.
Requires Python 3.11+ and the standard library only.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import unquote

MARKER = re.compile(r"\[SCREENSHOT PENDING:\s*(?P<id>[A-Za-z]+[\w.\-]*)\s*\|\s*(?P<what>[^|\]]+?)\s*\|\s*source:\s*(?P<src>[^\]]+?)\s*\]")
MARKER_START = re.compile(r"\[SCREENSHOT PENDING:", re.IGNORECASE)
FENCE = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")


def looks_like_lab(path: Path) -> bool:
    return (path / "masterdoc.json").is_file() or (path / "Instructions").is_dir()


def guide_pages(root: Path) -> tuple[list[Path], str]:
    """The guide pages in delivery order, and where the list came from."""
    pages: list[Path] = []
    for md in sorted(root.glob("masterdoc*.json")):
        try:
            data = json.loads(md.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            continue
        for entry in data if isinstance(data, list) else [data]:
            files = entry.get("Files", []) if isinstance(entry, dict) else []
            for f in sorted(files, key=lambda x: x.get("Order", 0) if isinstance(x, dict) else 0):
                url = f.get("RawFilePath", "") if isinstance(f, dict) else ""
                m = re.search(r"raw\.githubusercontent\.com/[^/]+/[^/]+/(.+)$", url.strip())
                if not m:
                    continue
                parts = unquote(m.group(1)).split("/")
                if parts and parts[0] == "refs" and len(parts) > 2 and parts[1] == "heads":
                    parts = parts[2:]
                for i in range(1, len(parts)):
                    candidate = root.joinpath(*parts[i:])
                    if candidate.is_file():
                        if candidate not in pages:
                            pages.append(candidate)
                        break
    if pages:
        return pages, "masterdoc.json"

    def order(p: Path):
        name = p.stem.lower()
        first = 0 if "getting" in name else 1
        nums = [int(n) for n in re.findall(r"\d+", name)] or [0]
        return (first, nums, name)

    folder = root / "Instructions"
    found = sorted(folder.rglob("*.md"), key=order) if folder.is_dir() else []
    return found, "Instructions/**/*.md"


def slugs(path: Path) -> set[str]:
    """GitHub heading anchors of a Markdown file (enough to decide whether a link resolves)."""
    out: set[str] = set()
    if not path.is_file():
        return out
    fence = False
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if FENCE.match(line):
            fence = not fence
            continue
        m = None if fence else re.match(r"^ {0,3}#{1,6}\s+(.*?)\s*#*\s*$", line)
        if m:
            text = re.sub(r"<[^>]+>|[*`]", "", m.group(1)).strip().lower()
            out.add(re.sub(r"[^\w\- ]", "", text).replace(" ", "-"))
    return out


def relative(target: Path, start: Path, root: Path) -> str:
    """target relative to start, or to the repository root when they are on different drives."""
    try:
        return Path(os.path.relpath(target, start)).as_posix()
    except ValueError:
        return Path(os.path.relpath(target, root)).as_posix()


def link(out_dir: Path, root: Path, target: Path, anchor: str | None, label: str) -> str | None:
    """A relative link from the output file to target#anchor, degrading to no anchor or None."""
    if not target.is_file():
        return None
    rel = relative(target, out_dir, root)
    if anchor and anchor in slugs(target):
        return f"[{label}]({rel}#{anchor})"
    return f"[{label}]({rel})"


def duration(minutes: int) -> str:
    if minutes < 60:
        return f"about {minutes} minutes"
    hours = round(minutes / 30) / 2
    text = f"{hours:g}"
    return f"about {text} hour{'s' if hours != 1 else ''}"


def build(root: Path, out: Path, minutes_per_shot: int, never: list[str], generator: str) -> tuple[str, dict]:
    pages, source = guide_pages(root)
    rows: dict[Path, list[tuple[str, str, str, int]]] = {}
    bad: list[tuple[Path, int, str]] = []
    for page in pages:
        fence = False
        for number, line in enumerate(page.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
            if FENCE.match(line):
                fence = not fence
                continue
            if fence:
                continue
            good_spans = []
            for m in MARKER.finditer(line):
                rows.setdefault(page, []).append((m["id"], m["what"].strip(), m["src"].strip(), number))
                good_spans.append(m.start())
            for m in MARKER_START.finditer(line):
                if m.start() not in good_spans:
                    bad.append((page, number, line.strip()))

    items = [r for v in rows.values() for r in v]
    total = len(items)
    learn = sum(1 for r in items if r[2].lower().startswith("learn"))
    reuse = sum(1 for r in items if r[2].lower().startswith("reuse"))
    out_dir = out.parent
    names = [p.name for p in rows]
    use_paths = len(set(names)) != len(names)

    # The README may be README.md or readme.md (Microsoft Learning repositories); link the real name.
    readme_name = next((p.name for p in sorted(root.iterdir()) if p.name.lower() == "readme.md"), "README.md")
    readme = link(out_dir, root, root / readme_name, "delivery-path", readme_name)
    facilitator = link(out_dir, root, root / "FACILITATOR-GUIDE.md", "phase-checklist", "FACILITATOR-GUIDE.md")
    secrets = ("passwords, Temporary Access Passes, keys, connection strings, tokens, consent URLs "
               "or any file or setting that holds one")
    if never:
        secrets += ", and in this lab " + ", ".join(never)

    def media_dir(page: Path) -> Path:
        # Keep the existing folder's case (media or Media); GitHub paths are case-sensitive.
        found = sorted(d for d in page.parent.iterdir() if d.is_dir() and d.name.lower() == "media")
        return found[0] if found else page.parent / "media"

    media = sorted({Path(os.path.relpath(media_dir(p), root)).as_posix() for p in rows}) or ["Instructions/media"]
    embed = " or ".join(f"`./{name}/<ID>.png`" for name in sorted({Path(m).name for m in media}))

    lines = [
        "# Screenshot To-Do",
        "",
        "> **Delivery path: Phase 5 of 8, run the pilot.** Capture these screenshots during the pilot walk-through,",
        "> after the template is published and the environment is prepared."
        + (f" Start of the path: {readme}." if readme else ""),
        "",
        f"**Who:** the lab author and the CloudLabs engineer, during the pilot. **Time:** {duration(total * minutes_per_shot)} "
        f"for {total} screenshot{'s' if total != 1 else ''} at about {minutes_per_shot} minutes each.",
        "",
        "Every screenshot the lab guide still needs, generated from the screenshot placeholder markers in the guide",
        f"pages ({source}) by `{generator}`. Regenerate it after editing the guide, and do not edit it by hand.",
        "",
        "How to produce them:",
        "",
        "- Capture with a **participant** account (the role set learners get), so the screenshots show exactly what",
        "  learners see. Capture admin-only screens (marked Read Only in the guide) with the instructor account.",
        "- Use the lab's fictional company and seeded data. Never show a real customer, a real person's name or",
        f"  email address, or a secret or credential: {secrets}. Crop to the relevant pane.",
        "- Add numbered balloons where the step text uses **(1)**, **(2)** markers.",
        f"- Save each image as `<ID>.png` in the media folder next to its page ({', '.join(f'`{m}`' for m in media)}), then replace",
        "  the marker line, at the same indentation, with a Markdown image embed whose alt text is the description",
        f"  and whose path is {embed}.",
        "- `source: learn <url>` gives a Microsoft Learn image to use as the reference for framing: capture the real",
        "  environment rather than copying the Learn image. `source: reuse` means the standard CloudLabs",
        "  getting-started image, and `source: capture` means a new capture in the pilot.",
        "",
        f"**Total: {total}** ({reuse} reuse, {learn} with a Microsoft Learn reference, {total - reuse - learn} capture only)."
        if total else "**Total: 0.** Every screenshot the guide needs is in place.",
        "",
    ]
    for page, items_on_page in rows.items():
        title = Path(os.path.relpath(page, root)).as_posix() if use_paths else page.name
        page_link = relative(page, out_dir, root)
        lines += [f"## {title}", "",
                  f"[{Path(os.path.relpath(page, root)).as_posix()}]({page_link}): {len(items_on_page)} screenshot"
                  f"{'s' if len(items_on_page) != 1 else ''}.", "",
                  "| ID | What it must show | Source | Line |", "|---|---|---|---|"]
        for sid, what, src, number in items_on_page:
            if src.lower().startswith("learn "):
                src_cell = f"[Learn reference]({src[6:].strip()})"
            else:
                src_cell = src.replace("|", "/")
            lines.append(f"| {sid} | {what.replace('|', '/')} | {src_cell} | {number} |")
        lines.append("")
    if bad:
        lines += ["## Markers that could not be read", "",
                  "Fix these in the guide: a marker needs an ID, a description and a source, separated by `|`.", "",
                  "| Page | Line | Text |", "|---|---|---|"]
        for page, number, text in bad:
            # Drop the opening bracket so this file does not count as a page with pending markers.
            text = re.sub(r"(?i)\[SCREENSHOT PENDING:", "SCREENSHOT PENDING:", text).replace("|", "/")
            lines.append(f"| {Path(os.path.relpath(page, root)).as_posix()} | {number} | `{text.replace('`', '')}` |")
        lines.append("")
    if facilitator:
        nxt = f"**Next:** finish the rest of the pilot checklist in {facilitator}, then deliver the session (Phase 6)."
    else:
        nxt = "**Next:** finish the rest of the pilot checklist, then deliver the session (Phase 6)."
    lines += ["---", "", nxt, ""]
    stats = {"total": total, "learn": learn, "reuse": reuse, "pages": len(rows), "unreadable": len(bad),
             "source": source}
    return "\n".join(lines), stats


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Build SCREENSHOT-TODO.md from the guide's pending screenshot markers.")
    parser.add_argument("repo", nargs="?", help="the lab repository")
    parser.add_argument("--out", type=Path, help="file to write (default: SCREENSHOT-TODO.md in the repository)")
    parser.add_argument("--check", action="store_true", help="exit 1 when the file is missing or out of date")
    parser.add_argument("--minutes-per-shot", type=int, default=3, help="capture minutes per screenshot (default 3)")
    parser.add_argument("--never-capture", action="append", default=[], metavar="TEXT",
                        help="a lab-specific item that must never be captured (repeatable)")
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    here = Path(__file__).resolve()
    if args.repo:
        root = Path(args.repo).resolve()
    elif looks_like_lab(Path.cwd()):
        root = Path.cwd().resolve()
    else:
        root = next((p for p in here.parents if looks_like_lab(p)), None)
        if root is None:
            parser.error("no lab repository here; pass the repository folder")
    if not root.is_dir():
        parser.error(f"{root} is not a folder")
    out = (args.out or root / "SCREENSHOT-TODO.md").resolve()
    try:
        generator = here.relative_to(root).as_posix()
    except ValueError:
        generator = "tools/qa/make_screenshot_todo.py"

    text, stats = build(root, out, max(1, args.minutes_per_shot), args.never_capture, generator)
    if stats["source"] != "masterdoc.json":
        print(f"note: no usable masterdoc.json, read {stats['source']}")
    if args.check:
        current = out.read_text(encoding="utf-8") if out.is_file() else None
        if current != text:
            print(f"{out.name} is {'missing' if current is None else 'out of date'}: run make_screenshot_todo.py")
            return 1
        print(f"{out.name} is up to date: {stats['total']} screenshots")
        return 0
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {out}: {stats['total']} screenshots across {stats['pages']} pages "
          f"({stats['reuse']} reuse, {stats['learn']} Learn reference, {stats['total'] - stats['reuse'] - stats['learn']} capture)"
          + (f"; {stats['unreadable']} unreadable marker(s) listed" if stats["unreadable"] else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
