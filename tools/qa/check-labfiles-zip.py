"""Check that every C:\\LabFiles path the lab guide uses is in the lab files archive.

The lab files zip is built once per lab version and unpacked to C:\\LabFiles on every lab VM. A
step that opens a file the zip does not contain fails for every learner, and nothing else catches
it before the pilot. This tool lists every path under the lab files root that the guide pages
mention, and reports which are missing from the zip (or from a folder with the same content).

Paths are found in prose, inline code and fenced code blocks, for example
`C:\\LabFiles\\agents\\Policy.docx` or Set-Location C:\\LabFiles\\a365. Quoted and backticked paths
may contain spaces. A path that names a folder passes when the archive has anything inside it.
Matching ignores letter case, like Windows.

Statuses:
  present  the file or folder is in the archive
  allowed  matches an allow-list pattern: something created on the VM at provisioning time or by
           the learner, such as a generated package, a .env file written by the setup script, or
           an output the lab produces
  dynamic  the path holds an inject tag or a variable, so it differs per deployment and cannot be
           in a static archive (for example Contoso-<inject key="DeploymentID" .../>.zip); make sure
           the provisioning script creates it, then add a pattern to the allow-list to confirm it
  MISSING  none of the above: add the file to the lab files, fix the path in the guide, or allow it

Usage:
    python tools/qa/check-labfiles-zip.py <repo> <zip or folder> [--root "C:\\LabFiles"]
                                          [--allow PATTERN] [--allow-file FILE]
                                          [--all-markdown] [--zip-prefix PREFIX]

    repo           the lab repository
    zip or folder  the built lab files zip, or the folder it is built from
    --root         the lab files root on the VM (default: C:\\LabFiles)
    --allow        a glob of paths below the root that may be missing because the VM creates them,
                   written with forward slashes, for example "cowork/plugin/*.zip" or
                   "a365/sample-agent/.env" (repeatable; * also matches across folders)
    --allow-file   a file with one allow pattern per line (# starts a comment)
    --all-markdown scan every Markdown file in the repository, not only the guide pages listed in
                   masterdoc.json (or Instructions/**/*.md when there is no masterdoc)
    --zip-prefix   a folder prefix to strip from archive entries; by default a single top folder
                   named like the root (LabFiles/) is stripped automatically

Exit code: 0 when nothing is missing, 1 when a path is missing, 2 on a usage error.
Requires Python 3.11+ and the standard library only.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
import zipfile
from pathlib import Path, PureWindowsPath
from urllib.parse import unquote

SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", ".vs", ".vscode", ".idea"}
INJECT = re.compile(r"<inject\b[^>]*?\bkey\s*=\s*[\"']([^\"']*)[\"'][^>]*>", re.IGNORECASE)
UNQUOTED_END = set(" \t`\"'<>|*?)],;")


def guide_pages(root: Path) -> list[Path]:
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
    if not pages and (root / "Instructions").is_dir():
        pages = sorted((root / "Instructions").rglob("*.md"))
    return pages


def root_pattern(root_text: str) -> re.Pattern:
    """The root as written in a guide: either slash, doubled backslashes, any letter case."""
    parts = [re.escape(p) for p in re.split(r"[\\/]+", root_text) if p]
    return re.compile(r"[\\/]+".join(parts) + r"(?![A-Za-z0-9_\-])", re.IGNORECASE)


def find_paths(line: str, rx: re.Pattern):
    """Yield (column, path parts below the root) for every mention of the lab files root."""
    line = INJECT.sub(lambda m: "{" + m.group(1) + "}", line)
    for m in rx.finditer(line):
        start = m.start()
        before = line[start - 1] if start > 0 else ""
        if before in ("\"", "'", "`"):
            end = line.find(before, m.end())
            end = len(line) if end < 0 else end
        else:
            end = m.end()
            while end < len(line) and line[end] not in UNQUOTED_END:
                end += 1
        rest = line[m.end():end].rstrip(".:")
        yield start + 1, [p for p in re.split(r"[\\/]+", rest) if p and p != "."]


def archive_index(source: Path, prefix: str | None, root_name: str) -> tuple[set[str], set[str], str]:
    """Lowercase file paths and folder paths in the archive or folder, and a description."""
    if source.is_dir():
        names = [p.relative_to(source).as_posix() for p in source.rglob("*") if p.is_file()]
        what = f"folder {source}"
    else:
        with zipfile.ZipFile(source) as z:
            names = [n.replace("\\", "/") for n in z.namelist() if not n.endswith("/")]
        what = f"zip {source.name} ({len(names)} files)"
    if prefix is None:
        tops = {n.split("/", 1)[0] for n in names if "/" in n}
        if len(tops) == 1 and all("/" in n for n in names) and next(iter(tops)).lower() == root_name.lower():
            prefix = next(iter(tops))
    if prefix:
        p = prefix.strip("/") + "/"
        names = [n[len(p):] for n in names if n.lower().startswith(p.lower())]
    files = {n.lower() for n in names}
    folders = set()
    for n in files:
        parts = n.split("/")
        for i in range(1, len(parts)):
            folders.add("/".join(parts[:i]))
    return files, folders, what


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Check that every lab files path the guide uses is in the lab files zip.")
    parser.add_argument("repo", help="the lab repository")
    parser.add_argument("labfiles", help="the lab files zip, or the folder it is built from")
    parser.add_argument("--root", default="C:\\LabFiles", help="lab files root on the VM (default C:\\LabFiles)")
    parser.add_argument("--allow", action="append", default=[], metavar="PATTERN", help="path glob that may be missing")
    parser.add_argument("--allow-file", type=Path, help="file with one allow pattern per line")
    parser.add_argument("--all-markdown", action="store_true", help="scan every Markdown file, not only guide pages")
    parser.add_argument("--zip-prefix", help="folder prefix to strip from archive entries")
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    repo = Path(args.repo).resolve()
    source = Path(args.labfiles).resolve()
    if not repo.is_dir():
        parser.error(f"{repo} is not a folder")
    if not source.exists():
        parser.error(f"{source} does not exist; build the lab files zip first")
    if source.is_file() and not zipfile.is_zipfile(source):
        parser.error(f"{source} is not a zip archive")
    root_text = args.root.rstrip("\\/")
    root_name = PureWindowsPath(root_text).name or root_text
    patterns = [p.strip().replace("\\", "/").lower() for p in args.allow if p.strip()]
    if args.allow_file:
        for line in args.allow_file.read_text(encoding="utf-8").splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                patterns.append(line.replace("\\", "/").lower())

    if args.all_markdown:
        pages = sorted(p for p in repo.rglob("*.md") if not (set(p.relative_to(repo).parts[:-1]) & SKIP_DIRS))
    else:
        pages = guide_pages(repo)
    if not pages:
        parser.error("no guide pages found (no masterdoc.json and no Instructions folder); use --all-markdown")

    files, folders, what = archive_index(source, args.zip_prefix, root_name)
    rx = root_pattern(root_text)
    refs: dict[str, dict] = {}
    for page in pages:
        rel_page = page.relative_to(repo).as_posix()
        for number, line in enumerate(page.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
            for col, parts in find_paths(line, rx):
                if not parts:
                    continue
                key = "/".join(parts)
                entry = refs.setdefault(key.lower(), {"path": key, "places": []})
                entry["places"].append(f"{rel_page}:{number}")

    results = {"present": [], "allowed": [], "dynamic": [], "MISSING": []}
    for low, entry in sorted(refs.items()):
        if low in files or low in folders:
            status = "present"
        elif any(fnmatch.fnmatchcase(low, p) for p in patterns):
            status = "allowed"
        elif re.search(r"[{}$%]", low):
            status = "dynamic"
        else:
            status = "MISSING"
        results[status].append(entry)

    print(f"check-labfiles-zip  {repo}")
    print(f"  {len(pages)} page(s) scanned against the {what}; root {root_text}")
    for status in ("MISSING", "dynamic", "allowed", "present"):
        for entry in results[status]:
            places = entry["places"]
            more = f" (+{len(places) - 1} more)" if len(places) > 1 else ""
            print(f"{status:<8} {root_text}\\{entry['path'].replace('/', chr(92))}  <- {places[0]}{more}")
    print(f"Summary: {len(refs)} path(s): {len(results['present'])} present, {len(results['allowed'])} allowed, "
          f"{len(results['dynamic'])} dynamic, {len(results['MISSING'])} missing")
    if results["dynamic"]:
        print("Dynamic paths differ per deployment: confirm the provisioning script creates them, then allow them.")
    return 1 if results["MISSING"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
