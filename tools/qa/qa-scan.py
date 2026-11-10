"""One command that scans a lab repository for house-style, privacy and secret problems.

Every finding is reported with its file and line (for Office documents and zip archives, the
part or entry inside the file, for example Policy.docx!word/document.xml paragraph 12).

Error classes (any one makes the exit code 1):
  dash         em dashes (U+2014) and en dashes (U+2013), including their HTML entities, and
               spaced double hyphens used as punctuation. Checked in .md, .ps1, .psm1, .psd1,
               .py, .json, .kql, .txt, .csv, .svg, .yml, .yaml, .sh and .bicep files, and in the
               text of .docx, .xlsx and .pptx files. Em and en dashes count everywhere, even in
               code, because they are never valid syntax and break commands that learners copy.
               The spaced double hyphen counts only outside code: fenced blocks, inline code and
               HTML comments in Markdown are skipped, so command lines such as git checkout with
               its end-of-options marker stay legal there. A quoted string that holds only dash
               characters (a dash check in a script) is not reported.
  banned-name  names passed with --ban, matched case-insensitively (spaces, hyphens and
               underscores between words match each other or nothing), in file and folder
               names, every text file, the text and attributes of Office documents, and the
               entry names, text entries and nested Office documents of .zip archives.
  secret       likely secrets: private keys, storage account keys, shared access keys and SAS
               signatures, GitHub tokens, AWS keys, JSON web tokens, Microsoft Entra client
               secrets, passwords in connection strings and URIs, and literal password
               assignments in code, configuration and Markdown. Values are masked in the output.
Warning classes (reported, exit code 0 unless --strict):
  spelling     British spellings in learner-facing Markdown (the pages listed in masterdoc.json,
               or Instructions/**/*.md when there is none): licence, organisation, colour,
               behaviour, recognise, enrolment, programme, catalogue, grey and similar, with the
               US spelling to use. Code, links and HTML are skipped.
  inject       inject tag form problems in Markdown: not self-closing, unclosed, missing key or
               enableCopy, enableCopy not true or false, key spelling drift (Deployment ID for
               DeploymentID, keys that differ only in case or spacing from a platform key, an ARM
               output or another spelling used in the repository) and legacy keys.
  comment-rule decorative rules of three or more hyphens in a comment or docstring line of
               .ps1, .psm1, .psd1, .py, .sh, .bash, .js, .ts, .cs, .kql, .bicep, .tf and .yml
               files, such as a "# ----" separator or a hyphen underline under a docstring
               heading; house style uses "# ====" rules and "====" underlines. Comments are read
               with a tokenizer, so strings, here-strings and heredocs (generated content) are
               not checked, and CLI flags, Markdown table rows and PEM markers do not count.
  marker       screenshot pending markers that are malformed, use an unusual ID or repeat an ID.
Information:
  screenshots  the number of pending screenshot markers per page.

A line that contains the text qa-scan: ignore is skipped by every check except banned names.

Files: every file under the repository except .git, node_modules, virtual environments, caches
and Office lock files (~$*). In a git work tree, files that git ignores are skipped too, unless
--include-ignored is given (use it to scan a built lab files zip that is git-ignored).

Usage:
    python tools/qa/qa-scan.py [repo] [--ban "Name1,Name2"] [--whole-word] [--include-ignored]
                               [--exclude GLOB] [--spelling-all] [--no-spelling]
                               [--spelling-add "british=us,..."] [--spelling-allow "word,..."]
                               [--json] [--strict]

    repo               the lab repository (default: the current folder)
    --ban              comma-separated names that must never appear (repeatable); typically the
                       real customer, partner or requester behind the lab
    --whole-word       match banned names only as whole words
    --include-ignored  also scan files that git ignores
    --exclude          a glob of repository paths to skip, for example "research/*" (repeatable)
    --spelling-all     check spelling in every Markdown file, not only learner-facing pages
    --no-spelling      skip the spelling check
    --spelling-add     extra british=us pairs, comma-separated
    --spelling-allow   words that the spelling check must accept, comma-separated
    --json             print the findings as JSON
    --strict           exit with code 1 on warnings too

Exit code: 0 when there is no error-class finding, 1 when there is (or any warning with
--strict), 2 on a usage error. Requires Python 3.11+ and the standard library only (git is used
when available).
"""
from __future__ import annotations

import argparse
import fnmatch
import html
import io
import json
import os
import re
import subprocess
import sys
import zipfile
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from urllib.parse import unquote

# ==== Classes and file types ===================================================================

ERROR_CLASSES = ("dash", "banned-name", "secret")
WARN_CLASSES = ("spelling", "inject", "comment-rule", "marker")
INFO_CLASSES = ("screenshots",)

SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", ".vs", ".vscode", ".idea",
             ".pytest_cache", ".mypy_cache", ".tox"}
DASH_EXTS = {".md", ".ps1", ".psm1", ".psd1", ".py", ".json", ".kql", ".txt", ".csv", ".svg",
             ".yml", ".yaml", ".sh", ".bicep"}
SCRIPT_EXTS = {".ps1", ".psm1", ".psd1", ".py", ".sh", ".bash", ".kql", ".bicep", ".yml", ".yaml",
               ".tf", ".js", ".ts", ".cs"}
TEXT_EXTS = DASH_EXTS | SCRIPT_EXTS | {
    ".markdown", ".jsonc", ".tsv", ".xml", ".html", ".htm", ".tfvars", ".bash", ".cmd", ".bat", ".mjs",
    ".cjs", ".csproj", ".env", ".config", ".ini", ".cfg", ".conf", ".properties", ".toml", ".sql",
    ".ipynb", ".http", ".rst", ".adoc", ".gitignore", ".gitattributes", ".editorconfig"}
TEXT_NAMES = {"dockerfile", "makefile", "license", "readme", ".env"}
OFFICE_EXTS = {".docx", ".docm", ".xlsx", ".xlsm", ".pptx", ".pptm"}
TEMPLATE_EXTS = {".example", ".sample", ".template", ".tmpl", ".dist"}
CONFIG_EXTS = {".env", ".ini", ".cfg", ".conf", ".config", ".properties", ".toml", ".txt"}
MAX_TEXT_BYTES = 20 * 1024 * 1024
MAX_ENTRY_BYTES = 50 * 1024 * 1024
PER_FILE_CAP = 25          # findings of one class reported per file before a summary line

EM, EN = "\u2014", "\u2013"
IGNORE_MARK = "qa-scan: ignore"

# ==== Findings =================================================================================


@dataclass
class Finding:
    cls: str
    path: str
    line: int | None
    col: int | None
    message: str

    @property
    def severity(self) -> str:
        if self.cls in ERROR_CLASSES:
            return "ERROR"
        if self.cls in WARN_CLASSES:
            return "WARN"
        return "INFO"

    def location(self) -> str:
        loc = self.path
        if self.line is not None:
            loc += f":{self.line}"
            if self.col is not None:
                loc += f":{self.col}"
        return loc


class Report:
    def __init__(self) -> None:
        self.findings: list[Finding] = []
        self._counts: Counter = Counter()
        self.capped: Counter = Counter()

    def add(self, cls: str, path: str, line: int | None, col: int | None, message: str) -> None:
        top = path.split("!", 1)[0]
        self._counts[(top, cls)] += 1
        if self._counts[(top, cls)] > PER_FILE_CAP and cls != "screenshots":
            self.capped[(top, cls)] += 1
            return
        self.findings.append(Finding(cls, path, line, col, message))


def visible(text: str, limit: int = 90) -> str:
    """Make a context snippet safe to print: dashes shown as code points, length limited."""
    text = text.replace(EM, "<U+2014>").replace(EN, "<U+2013>").replace("\t", " ").strip()
    return text if len(text) <= limit else text[:limit - 3] + "..."


def around(line: str, start: int, end: int, width: int = 36) -> str:
    a = max(0, start - width)
    b = min(len(line), end + width)
    return ("..." if a > 0 else "") + line[a:b] + ("..." if b < len(line) else "")


# ==== Markdown helpers =========================================================================

FENCE = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")
CODE_SPAN = re.compile(r"(`+)(.+?)\1")
TABLE_RULE = re.compile(r"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$")


def blank(text: str, start: int, end: int) -> str:
    return text[:start] + " " * (end - start) + text[end:]


def markdown_lines(text: str):
    """Yield (number, raw line without HTML comments, prose without code spans, in fence)."""
    fence = None
    in_comment = False
    for number, raw in enumerate(text.splitlines(), start=1):
        m = FENCE.match(raw)
        if fence is None and m and not in_comment:
            fence = (m.group(1)[0], len(m.group(1)))
            yield number, raw, "", True
            continue
        if fence is not None:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= fence[1] and not m.group(2).strip():
                fence = None
            yield number, raw, "", True
            continue
        line = raw
        if in_comment:
            end = line.find("-->")
            if end < 0:
                yield number, "", "", False
                continue
            line = " " * (end + 3) + line[end + 3:]
            in_comment = False
        for c in list(re.finditer(r"<!--.*?-->", line)):
            line = blank(line, c.start(), c.end())
        start = line.find("<!--")
        if start >= 0:
            line = line[:start]
            in_comment = True
        prose = line
        for c in list(CODE_SPAN.finditer(prose)):
            prose = blank(prose, c.start(), c.end())
        yield number, line, prose, False


def masterdoc_pages(root: Path) -> list[Path]:
    """The learner-facing pages: every page in the repository's masterdoc files, in order."""
    pages: list[Path] = []
    for md in sorted(root.glob("masterdoc*.json")):
        try:
            data = json.loads(md.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            continue
        entries = data if isinstance(data, list) else [data]
        for entry in entries:
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
    if not pages:
        pages = sorted((root / "Instructions").rglob("*.md")) if (root / "Instructions").is_dir() else []
    return pages


# ==== Dash checks ==============================================================================

SPACED_DOUBLE_HYPHEN = re.compile(r"(?<=\S)\s--\s(?=\S)")
DASH_ENTITY = re.compile(r"&(?:mdash|ndash|#8212|#8211|#x2014|#x2013);", re.IGNORECASE)
QUOTED = re.compile(r"([\"'])((?:(?!\1).)*?)\1")
DASH_ONLY = re.compile(r"[\s\u2014\u2013\-\[\]()|\\]*")


def strip_dash_literals(line: str) -> str:
    """Blank quoted strings that hold only dash characters: dash checks in scripts, not prose."""
    def repl(m: re.Match) -> str:
        body = m.group(2)
        if DASH_ONLY.fullmatch(body) and (EM in body or EN in body or "--" in body):
            return " " * len(m.group(0))
        return m.group(0)
    return QUOTED.sub(repl, line)


def check_dashes(report: Report, where: str, number: int | None, line: str, prose: str | None,
                 entities: bool) -> None:
    """Em and en dashes in `line`; the spaced double hyphen only in `prose` (code removed)."""
    for m in re.finditer(f"[{EM}{EN}]", line):
        name = "em dash (U+2014)" if m.group(0) == EM else "en dash (U+2013)"
        report.add("dash", where, number, m.start() + 1, f"{name}: \"{visible(around(line, m.start(), m.end()))}\"")
    if entities:
        for m in DASH_ENTITY.finditer(line):
            report.add("dash", where, number, m.start() + 1,
                       f"dash entity {m.group(0)}: \"{visible(around(line, m.start(), m.end()))}\"")
    if prose is not None:
        for m in SPACED_DOUBLE_HYPHEN.finditer(prose):
            report.add("dash", where, number, m.start() + 2,
                       f"spaced double hyphen used as punctuation: \"{visible(around(prose, m.start(), m.end()))}\"")


# ==== Spelling =================================================================================

ISE_STEMS = (
    "organ", "recogn", "real", "custom", "author", "minim", "maxim", "summar", "util", "visual", "initial",
    "normal", "synchron", "categor", "emphas", "standard", "final", "apolog", "familiar", "personal",
    "special", "capital", "character", "critic", "digit", "local", "modern", "monet", "serial", "sanit",
    "token", "virtual", "container", "parameter", "random", "anonym", "operational", "central", "optim",
    "priorit", "general", "harmon", "item", "memor", "mobil", "neutral", "penal", "popular", "rational",
    "stabil", "symbol", "trivial", "jeopard", "legitim", "material", "revolution", "scrutin", "sympath",
    "global", "industrial", "internal", "commercial", "ideal", "immun", "institutional", "legal",
    "modular", "orchestr", "prior", "proxim", "simul", "summon", "theor", "vapor", "agon")
ISE_STEMS = tuple(s for s in ISE_STEMS if s not in ("orchestr", "prior", "proxim", "simul", "summon", "vapor"))
OUR_STEMS = ("col", "behavi", "fav", "hon", "lab", "neighb", "flav", "hum", "rum", "harb", "vap", "arm",
             "endeav", "sav", "od", "parl", "rig", "tum", "val", "vig")
RE_STEMS = ("cent", "met", "lit", "theat", "fib", "calib", "sab", "spect", "lust", "somb")
ENCE_STEMS = ("licen", "defen", "offen", "preten")
LL_STEMS = ("travel", "cancel", "label", "model", "signal", "fuel", "level", "total", "counsel", "channel",
            "dial", "tunnel", "marshal", "equal")
SINGLE_WORDS = {
    "enrolment": "enrollment", "enrolments": "enrollments", "enrol": "enroll", "enrols": "enrolls",
    "programme": "program", "programmes": "programs", "catalogue": "catalog", "catalogues": "catalogs",
    "catalogued": "cataloged", "analogue": "analog", "dialogue": "dialog", "dialogues": "dialogs",
    "fulfil": "fulfill", "fulfils": "fulfills", "fulfilment": "fulfillment", "instalment": "installment",
    "instalments": "installments", "skilful": "skillful", "wilful": "willful", "judgement": "judgment",
    "judgements": "judgments", "acknowledgement": "acknowledgment", "acknowledgements": "acknowledgments",
    "ageing": "aging", "grey": "gray", "greyed": "grayed", "greys": "grays", "cheque": "check",
    "cheques": "checks", "tyre": "tire", "tyres": "tires", "aluminium": "aluminum", "whilst": "while",
    "amongst": "among", "learnt": "learned", "spelt": "spelled", "artefact": "artifact",
    "artefacts": "artifacts", "enquiry": "inquiry", "enquiries": "inquiries", "enquire": "inquire",
    "focussed": "focused", "focussing": "focusing", "practise": "practice", "practised": "practiced",
    "practising": "practicing", "sceptical": "skeptical", "manoeuvre": "maneuver", "cosy": "cozy",
    "jewellery": "jewelry", "mould": "mold", "storey": "story", "kerb": "curb", "plough": "plow",
    "benefitted": "benefited", "benefitting": "benefiting", "colour": "color"}


class Speller:
    def __init__(self, add: dict[str, str], allow: set[str]) -> None:
        self.allow = {w.lower() for w in allow}
        self.single = dict(SINGLE_WORDS)
        self.single.update({k.lower(): v for k, v in add.items()})
        alt = lambda stems: "|".join(sorted(stems, key=len, reverse=True))
        self.rules = [
            (re.compile(rf"\b(?P<pre>[A-Za-z]*?(?:{alt(ISE_STEMS)}))is(?P<suf>e|es|ed|ing|ation|ations|er|ers|able)\b", re.I), "iz"),
            (re.compile(r"\b(?P<pre>[A-Za-z]*?(?:anal|paral|catal))ys(?P<suf>e|ed|ing)\b", re.I), "yz"),
            (re.compile(rf"\b(?P<pre>{alt(OUR_STEMS)})our(?P<suf>s|ed|ing|ful|less|able|ably|ite|ites|ism|ist|hood|hoods|al|ally|er|ers|y)?\b", re.I), "or"),
            (re.compile(rf"\b(?P<pre>{alt(RE_STEMS)})re(?P<suf>s|d)?\b", re.I), "er"),
            (re.compile(rf"\b(?P<pre>{alt(ENCE_STEMS)})ce(?P<suf>s|d|less)?\b", re.I), "se"),
            (re.compile(rf"\b(?P<pre>{alt(LL_STEMS)})l(?P<suf>ed|ing|er|ers|or|ors)\b", re.I), ""),
        ]
        self.word = re.compile(r"\b[A-Za-z]+\b")

    @staticmethod
    def _case(original: str, us: str) -> str:
        if original.isupper() and len(original) > 1:
            return us.upper()
        if original[:1].isupper():
            return us[:1].upper() + us[1:]
        return us

    def check(self, prose: str):
        """Yield (column, british word, US suggestion)."""
        seen: set[int] = set()
        for rx, middle in self.rules:
            for m in rx.finditer(prose):
                word = m.group(0)
                if word.lower() in self.allow or m.start() in seen:
                    continue
                if middle == "se":   # licence -> license, defenceless -> defenseless
                    us = m.group("pre") + "se" + (m.group("suf") or "")
                else:
                    us = m.group("pre") + middle + (m.group("suf") or "")
                seen.add(m.start())
                yield m.start() + 1, word, self._case(word, us.lower())
        for m in self.word.finditer(prose):
            w = m.group(0)
            if m.start() in seen or w.lower() in self.allow:
                continue
            us = self.single.get(w.lower())
            if us:
                yield m.start() + 1, w, self._case(w, us)


def spelling_prose(prose: str) -> str:
    """Remove the parts of a Markdown line that are not English prose: URLs, link targets, HTML."""
    out = prose
    for rx in (re.compile(r"\]\([^)]*\)"), re.compile(r"<[^>]+>"), re.compile(r"\bhttps?://\S+"),
               re.compile(r"\b[\w.\-]+@[\w.\-]+\.\w+"), re.compile(r"(?<![\w])[\w\-./\\]+\.[A-Za-z0-9]{1,5}(?![\w])")):
        for m in list(rx.finditer(out)):
            out = blank(out, m.start(), m.end())
    return out


# ==== Inject tags ==============================================================================

PLATFORM_KEYS = [
    "AzureAdUserEmail", "AzureAdUserPassword", "DeploymentID", "ApplicationID", "DisplayName", "SecretKey",
    "SubscriptionID", "TenantID", "TenantDomainName", "Region",
    "LabVM Admin Username", "LabVM Admin Password", "LabVM DNS Name", "ClientVM DNS Name",
    "ClientVM Admin Username", "ClientVM Admin Password", "VM Name", "VM Admin Username", "VM Admin Password",
    "VM DNS Name", "Trainer Username", "Trainer Password", "TrainerUserName", "TrainerUserPassword"]
LEGACY_KEYS = {"uniqueid": "DeploymentID (UniqueID is a legacy key the platform no longer fills)"}
INJECT_TAG = re.compile(r"<inject\b[^>]*>", re.IGNORECASE)
INJECT_OPEN = re.compile(r"<inject\b[^>]*$", re.IGNORECASE)
ATTR = re.compile(r"([\w:-]+)\s*=\s*(?:\"([^\"]*)\"|'([^']*)')")


def norm_key(key: str) -> str:
    return re.sub(r"[\s_\-]", "", key).lower()


def arm_outputs(root: Path, files: list[tuple[Path, str]]) -> set[str]:
    names: set[str] = set()
    for path, _ in files:
        if path.suffix.lower() != ".json":
            continue
        try:
            text = path.read_text(encoding="utf-8-sig", errors="replace")
            if "deploymentTemplate" not in text or "outputs" not in text:
                continue
            data = json.loads(text)
        except (OSError, ValueError):
            continue
        if isinstance(data, dict) and isinstance(data.get("outputs"), dict):
            names.update(data["outputs"].keys())
    return names


# ==== Secrets ==================================================================================

PW_KEY = r"[\w.\-]*?(?:password|passwd|pwd)"
SECRET_RULES = [
    ("private key block", re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY(?: BLOCK)?-----")),
    ("storage account key in a connection string", re.compile(r"(?i)AccountKey=(?P<v>[A-Za-z0-9+/]{40,}={0,2})")),
    ("shared access key in a connection string", re.compile(r"(?i)SharedAccessKey=(?P<v>[A-Za-z0-9+/]{30,}={0,2})")),
    # A storage key is 88 base64 characters; so is a sha512 integrity hash, so a key-like label must precede it.
    ("storage account key", re.compile(r"(?i)\b\w*key\w*[\"']?\s*[:=]\s*[\"']?(?P<v>[A-Za-z0-9+/]{86}==)(?![A-Za-z0-9+/=])")),
    ("SAS signature", re.compile(r"(?i)[?&;]sig=(?P<v>[A-Za-z0-9%+/=]{20,})")),
    ("GitHub token", re.compile(r"\b(?P<v>(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,})\b")),
    ("GitHub fine-grained token", re.compile(r"\b(?P<v>github_pat_[A-Za-z0-9_]{50,})\b")),
    ("AWS access key ID", re.compile(r"\b(?P<v>(?:AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16})\b")),
    ("AWS secret access key", re.compile(r"(?i)aws_?secret_?access_?key\W{0,4}\s*[:=]\s*[\"']?(?P<v>[A-Za-z0-9/+=]{40})(?![A-Za-z0-9/+=])")),
    ("JSON web token", re.compile(r"\b(?P<v>eyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,})")),
    ("Microsoft Entra client secret", re.compile(r"(?<![\w~.\-])(?P<v>[A-Za-z0-9_~.\-]{3,8}Q~[A-Za-z0-9_~.\-]{25,45})(?![\w~.\-])")),
]
PW_RULES_ANY = [
    ("password in a connection URI", re.compile(r"(?i)\b[a-z][a-z0-9+.\-]*://[^/\s:@'\"<>]+:(?P<v>[^@\s/'\"<>]{3,})@")),
    ("password literal", re.compile(rf"(?i)(?<![\w\-])({PW_KEY})[\"']?\s*(?::=|=>|:|=)\s*(?P<q>[\"'])(?P<v>[^\"'\r\n]{{4,}})(?P=q)")),
    ("password in an ARM parameter value", re.compile(rf"(?i)\"{PW_KEY}\"\s*:\s*\{{\s*\"value\"\s*:\s*\"(?P<v>[^\"]{{4,}})\"")),
    ("plain-text password for ConvertTo-SecureString", re.compile(r"(?i)ConvertTo-SecureString\s+(?:-String\s+)?(?P<q>[\"'])(?P<v>[^\"'\r\n]{4,})(?P=q)[^\r\n]*-AsPlainText")),
    # The value may not start with a separator or hold a call: in ARM concat(' -Password ', parameters(...))
    # the quote after the parameter name closes a string instead of opening a value.
    ("password passed as a literal parameter", re.compile(r"(?i)(?<![\w])-\w*(?:password|passwd|pwd)\w*\s+(?P<q>[\"'])(?P<v>[^\s,\"'$()][^\"'$()\r\n]{3,})(?P=q)")),
]
PW_CONNECTION = re.compile(r"(?i)(?:^|[;\"'\s])(?:password|pwd)\s*=\s*(?P<v>[^;'\"\s]{4,})")
CONNECTION_HINT = re.compile(r"(?i)\b(?:server|data source|host|user id|uid|username|initial catalog|database)\s*=")
PW_CONFIG = re.compile(rf"(?i)^\s*(?:export\s+)?{PW_KEY}\w*\s*[=:]\s*(?P<v>[^\s#\"']{{4,}})")
PW_PROSE = re.compile(r"(?i)\b(?:password|passwd|pwd)\b\s*[:=]\s*(?:\*\*|`|\")?(?P<v>[^\s*`\"<]{6,})")
API_KEY = re.compile(r"(?i)\b\w*(?:api[_\-]?key|subscription[_\-]?key|account[_\-]?key|access[_\-]?key|client[_\-]?secret)\w*[\"']?\s*[:=]\s*[\"']?(?P<v>[A-Za-z0-9+/=_\-.~]{20,})")
PLACEHOLDER_WORDS = {"password", "passwd", "pwd", "secret", "string", "securestring", "none", "null", "nil",
                     "true", "false", "required", "optional", "test", "sample", "dummy", "fake", "hidden",
                     "masked", "empty", "undefined", "notset", "unset", "value", "pass", "redacted", "example"}


def is_placeholder(value: str) -> bool:
    v = value.strip().strip("\"'`")
    low = v.lower()
    if not v or v[0] in "$<[{(%*@" or re.fullmatch(r"[_\-.*#]+", v):
        return True
    if low.startswith(("gen-", "get-")) or "inject" in low or "{{" in v or "${" in v or "$(" in v or "%(" in v:
        return True
    if re.match(r"(?i)^(your|enter|replace|insert|example|placeholder|changeme|change[_\-]?me|todo|tbd|x{3,}|\.{3,}|\*{3,}|0{6,})", v):
        return True
    return re.sub(r"[^a-z]", "", low) in PLACEHOLDER_WORDS


def looks_like_password(value: str) -> bool:
    return bool(re.search(r"[A-Za-z]", value)) and bool(re.search(r"[\d\W_]", value))


def mask(value: str) -> str:
    return f"{value[:3]}... ({len(value)} characters)" if len(value) > 3 else "***"


def check_secrets(report: Report, where: str, number: int | None, line: str, ext: str) -> None:
    if "<inject" in line.lower():
        line = re.sub(r"(?i)<inject\b[^>]*>", "", line)
    for label, rx in SECRET_RULES:
        for m in rx.finditer(line):
            value = m.groupdict().get("v") or m.group(0)
            report.add("secret", where, number, m.start() + 1, f"{label}: {mask(value)}")
    for label, rx in PW_RULES_ANY:
        for m in rx.finditer(line):
            if not is_placeholder(m.group("v")):
                report.add("secret", where, number, m.start() + 1, f"{label}: {mask(m.group('v'))}")
    if CONNECTION_HINT.search(line):
        for m in PW_CONNECTION.finditer(line):
            if not is_placeholder(m.group("v")):
                report.add("secret", where, number, m.start() + 1, f"password in a connection string: {mask(m.group('v'))}")
    if ext in CONFIG_EXTS or ext in (".yml", ".yaml"):
        m = PW_CONFIG.match(line)
        # Plain text files are often notes or templates, so there the value must look like a password.
        if m and not is_placeholder(m.group("v")) and (ext != ".txt" or looks_like_password(m.group("v"))):
            report.add("secret", where, number, m.start() + 1, f"password in a configuration file: {mask(m.group('v'))}")
    if ext in (".md", ".txt", ".markdown", ""):
        for m in PW_PROSE.finditer(line):
            v = m.group("v")
            if looks_like_password(v) and not is_placeholder(v):
                report.add("secret", where, number, m.start() + 1, f"password written in the text: {mask(v)}")
    for m in API_KEY.finditer(line):
        v = m.group("v")
        if not is_placeholder(v) and re.search(r"\d", v) and re.search(r"[A-Za-z]", v):
            report.add("secret", where, number, m.start() + 1, f"key or client secret assigned a literal value: {mask(v)}")


# ==== Office documents and archives ============================================================

def xml_segments(part: str, xml: str) -> list[str]:
    """The user-visible text of one Office XML part, one segment per paragraph, cell or field."""
    content = re.match(r"(word|ppt|xl)/", part) is not None
    s = xml
    s = re.sub(r"<(?:w:tab|a:tab)\b[^>]*/>", " ", s)
    s = re.sub(r"<(?:w:br|w:cr|a:br)\b[^>]*/>", "\n", s)
    if content:
        # Runs inside a paragraph, shared string or cell join up (Word splits words across runs);
        # paragraphs, shared strings, cells, formulas and comments end a segment.
        s = re.sub(r"</(?:w:p|a:p|si|c|f|is|comment)>", "\n", s)
    else:
        s = re.sub(r"</[^>]+>", "\n", s)
    s = re.sub(r"<[^>]+>", "", s)
    return [html.unescape(seg) for seg in s.split("\n")]


ATTR_VALUE = re.compile(r"\s([\w:]+)=\"([^\"]*)\"")
VISIBLE_ATTRS = {"name", "descr", "title", "display", "tooltip", "alt", "caption"}


def scan_office(report: Report, where: str, data: bytes, checks: dict) -> None:
    try:
        z = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        return
    with z:
        for info in z.infolist():
            if not info.filename.lower().endswith((".xml", ".rels")) or info.file_size > MAX_ENTRY_BYTES:
                continue
            part = info.filename
            xml = z.read(info).decode("utf-8", "replace")
            loc = f"{where}!{part}"
            if part.lower().endswith(".rels"):
                if checks["ban"]:
                    for target in re.findall(r"Target=\"([^\"]*)\"", xml):
                        check_banned(report, loc, None, html.unescape(target), checks)
                continue
            for i, seg in enumerate(xml_segments(part, xml), start=1):
                if not seg.strip():
                    continue
                label_line = i
                if checks["dash"]:
                    check_dashes(report, f"{loc} segment", label_line, seg, seg, entities=False)
                if checks["ban"]:
                    check_banned(report, f"{loc} segment", label_line, seg, checks)
                if checks["secret"]:
                    check_secrets(report, f"{loc} segment", label_line, seg, ".txt")
            seen: set[str] = set()
            for m in ATTR_VALUE.finditer(xml):
                attr, value = m.group(1), html.unescape(m.group(2))
                if not value or value in seen:
                    continue
                seen.add(value)
                local = attr.split(":")[-1].lower()
                if checks["ban"]:
                    check_banned(report, f"{loc} attribute {attr}", None, value, checks)
                if checks["dash"] and local in VISIBLE_ATTRS:
                    check_dashes(report, f"{loc} attribute {attr}", None, value, value, entities=False)


def scan_zip(report: Report, where: str, data: bytes, checks: dict, depth: int = 0) -> None:
    """Banned names and secrets in a zip archive's entry names, text entries and documents."""
    try:
        z = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        return
    sub = dict(checks, dash=False)   # archives also hold third-party content; dashes are checked at the source
    with z:
        for info in z.infolist():
            name = info.filename
            loc = f"{where}!{name}"
            if checks["ban"]:
                check_banned(report, loc, None, name, checks)
            if info.is_dir() or info.file_size > MAX_ENTRY_BYTES:
                continue
            ext = file_kind(name)
            if ext in OFFICE_EXTS:
                scan_office(report, loc, z.read(info), sub)
            elif ext == ".zip" and depth < 2:
                scan_zip(report, loc, z.read(info), sub, depth + 1)
            elif ext in TEXT_EXTS or Path(name).name.lower() in TEXT_NAMES:
                text = decode(z.read(info))
                if text is None:
                    continue
                for number, line in enumerate(text.splitlines(), start=1):
                    if checks["ban"]:
                        check_banned(report, loc, number, line, checks)
                    if checks["secret"] and IGNORE_MARK not in line:
                        check_secrets(report, loc, number, line, ext)


def file_kind(name: str) -> str:
    """The extension that decides how a file is read: .env, .env.local and .env.example are
    configuration text, and settings.json.example reads as .json."""
    base = Path(name.replace("\\", "/")).name.lower()
    ext = Path(base).suffix
    if base.startswith(".env"):
        return ".env"
    if ext in TEMPLATE_EXTS and Path(base[: -len(ext)]).suffix:
        return Path(base[: -len(ext)]).suffix
    return ext


def decode(data: bytes) -> str | None:
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return data.decode("utf-16", errors="replace")
    if b"\0" in data[:8192]:
        return None
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("cp1252", errors="replace")


# ==== Banned names =============================================================================

def ban_patterns(names: list[str], whole_word: bool) -> list[tuple[str, re.Pattern]]:
    out = []
    for name in names:
        words = [w for w in re.split(r"[\s_\-.]+", name.strip()) if w]
        if not words:
            continue
        body = r"[\s_\-.]*".join(re.escape(w) for w in words)
        if whole_word:
            body = rf"(?<![A-Za-z0-9]){body}(?![A-Za-z0-9])"
        out.append((name.strip(), re.compile(body, re.IGNORECASE)))
    return out


def check_banned(report: Report, where: str, number: int | None, text: str, checks: dict) -> None:
    hide = None
    for name, rx in checks["ban"]:
        for m in rx.finditer(text):
            if hide is None:
                # Never echo a line that also holds a likely secret: the secret finding masks it.
                probe = Report()
                check_secrets(probe, where, number, text, ".txt")
                hide = bool(probe.findings)
            context = "context hidden because the line also holds a likely secret" if hide else \
                f"\"{visible(around(text, m.start(), m.end()))}\""
            report.add("banned-name", where, number, m.start() + 1 if number is not None else None,
                       f"banned name '{name}': {context}")


# ==== Repository walk ==========================================================================

def git_visible(root: Path) -> set[str] | None:
    try:
        top = subprocess.run(["git", "-C", str(root), "rev-parse", "--is-inside-work-tree"],
                             capture_output=True, text=True, timeout=60)
        if top.returncode != 0 or top.stdout.strip() != "true":
            return None
        out = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                             capture_output=True, timeout=300)
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    return {p for p in out.stdout.decode("utf-8", "replace").split("\0") if p}


def walk(root: Path, include_ignored: bool, excludes: list[str], stats: Counter):
    visible_set = None if include_ignored else git_visible(root)
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for fn in sorted(filenames):
            path = Path(dirpath) / fn
            rel = path.relative_to(root).as_posix()
            if fn.startswith("~$"):
                stats["skipped (Office lock file)"] += 1
                continue
            if visible_set is not None and rel not in visible_set:
                stats["skipped (git-ignored)"] += 1
                continue
            if any(fnmatch.fnmatch(rel, g) for g in excludes):
                stats["skipped (--exclude)"] += 1
                continue
            yield path, rel


# ==== Main =====================================================================================

MARKER = re.compile(r"\[SCREENSHOT PENDING:\s*(?P<id>[^|\]]*?)\s*\|\s*(?P<what>[^|\]]+?)\s*\|\s*source:\s*(?P<src>[^\]]+?)\s*\]")
MARKER_START = re.compile(r"\[SCREENSHOT PENDING:", re.IGNORECASE)
# E1T2S3, E1T2-1S4, GS4, and lab1a-t2s3 in a course of separate labs (IDs unique across the course).
MARKER_ID = re.compile(r"^(?:E\d+T\d+(?:[.\-]\d+)?S\d+|GS\d+|lab\d+[a-z]?-t\d+(?:[.\-]\d+)?s\d+)$")


# ==== Decorative hyphen rules in comments and docstrings =======================================

PS_EXTS = {".ps1", ".psm1", ".psd1"}
HASH_EXTS = PS_EXTS | {".py", ".sh", ".bash", ".yml", ".yaml", ".tf"}
SLASH_EXTS = {".js", ".mjs", ".cjs", ".ts", ".cs", ".kql", ".bicep", ".tf"}
RULE_EXTS = HASH_EXTS | SLASH_EXTS
# Three or more hyphens with a space, a comment marker or the line edge on both sides. That is a
# rule ("# ---- helpers", a docstring underline); "--output", "-----BEGIN" and "|---|" are not.
HYPHEN_RULE = re.compile(r"(?:^|(?<=[\s#/*]))-{3,}(?=[\s#/*]|$)")


def python_comments(text: str) -> list[tuple[int, str]]:
    """Comment text (from the tokenizer) and docstring lines (from the syntax tree) of a Python file."""
    import ast
    import tokenize
    out: list[tuple[int, str]] = []
    lines = text.splitlines()
    parsed = False
    try:
        for tok in tokenize.generate_tokens(io.StringIO(text).readline):
            if tok.type == tokenize.COMMENT:
                out.append((tok.start[0], tok.string[1:]))
        parsed = True
    except (tokenize.TokenError, SyntaxError):
        pass
    try:
        tree = ast.parse(text)
        parsed = True
    except (SyntaxError, ValueError):
        tree = None
    for node in ast.walk(tree) if tree is not None else []:
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)) and node.body:
            first = node.body[0]
            if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
                for n in range(first.lineno, (first.end_lineno or first.lineno) + 1):
                    out.append((n, lines[n - 1]))
    if not parsed:
        out = [(n, line.lstrip()[1:]) for n, line in enumerate(lines, start=1) if line.lstrip().startswith("#")]
    return out


def script_comments(text: str, ext: str) -> list[tuple[int, str]]:
    """Comment text of a PowerShell, shell or C-family file: line and block comments outside
    strings, skipping PowerShell here-strings and shell heredocs (generated content, not comments)."""
    ps = ext in PS_EXTS
    hashes = ext in HASH_EXTS
    slashes = ext in SLASH_EXTS
    block_end = "#>" if ps else "*/"
    out: list[tuple[int, str]] = []
    in_block = False
    heredoc = None
    for number, line in enumerate(text.splitlines(), start=1):
        if heredoc is not None:
            if (ps and line.startswith(heredoc)) or (not ps and line.strip() == heredoc):
                heredoc = None
            continue
        i, quote = 0, None
        while i < len(line):
            if in_block:
                end = line.find(block_end, i)
                out.append((number, line[i:] if end < 0 else line[i:end]))
                if end < 0:
                    break
                in_block, i = False, end + 2
                continue
            ch = line[i]
            if quote:
                if ch == ("`" if ps else "\\"):
                    i += 2
                    continue
                if ch == quote:
                    quote = None
                i += 1
                continue
            if ch in "\"'":
                if ps and i > 0 and line[i - 1] == "@" and not line[i + 1:].strip():
                    heredoc = ch + "@"
                    break
                quote = ch
                i += 1
                continue
            if (ps and line.startswith("<#", i)) or (slashes and not ps and line.startswith("/*", i)):
                in_block, i = True, i + 2
                continue
            if hashes and ch == "#" and (i == 0 or line[i - 1].isspace() or line[i - 1] in ";{}("):
                out.append((number, line[i + 1:]))
                break
            if slashes and line.startswith("//", i):
                out.append((number, line[i + 2:]))
                break
            i += 1
        if ext in (".sh", ".bash") and heredoc is None:
            m = re.search(r"<<-?\s*['\"]?(\w+)['\"]?", line)
            if m and "<<<" not in line:
                heredoc = m.group(1)
    return out


def check_comment_rules(report: Report, rel: str, text: str, ext: str) -> None:
    lines = text.splitlines()
    comments = python_comments(text) if ext == ".py" else script_comments(text, ext)
    flagged: set[int] = set()
    for number, comment in comments:
        if number in flagged or "|" in comment or IGNORE_MARK in lines[number - 1]:
            continue
        m = HYPHEN_RULE.search(comment)
        if m:
            flagged.add(number)
            report.add("comment-rule", rel, number, None,
                       "decorative hyphen rule in a comment or docstring; use '# ====' rules and '====' underlines")


def split_list(values: list[str]) -> list[str]:
    return [v.strip() for value in values for v in value.split(",") if v.strip()]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Scan a lab repository for dashes, banned names, British spellings, "
                                                 "secrets, inject tag problems and pending screenshots.")
    parser.add_argument("repo", nargs="?", default=".", help="the lab repository (default: current folder)")
    parser.add_argument("--ban", action="append", default=[], metavar="NAMES", help="comma-separated names that must never appear")
    parser.add_argument("--whole-word", action="store_true", help="match banned names as whole words only")
    parser.add_argument("--include-ignored", action="store_true", help="also scan files that git ignores")
    parser.add_argument("--exclude", action="append", default=[], metavar="GLOB", help="repository paths to skip")
    parser.add_argument("--spelling-all", action="store_true", help="check spelling in every Markdown file")
    parser.add_argument("--no-spelling", action="store_true", help="skip the spelling check")
    parser.add_argument("--spelling-add", action="append", default=[], metavar="PAIRS", help="extra british=us pairs")
    parser.add_argument("--spelling-allow", action="append", default=[], metavar="WORDS", help="words to accept")
    parser.add_argument("--json", action="store_true", help="print JSON")
    parser.add_argument("--strict", action="store_true", help="exit 1 on warnings too")
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    root = Path(args.repo).resolve()
    if not root.is_dir():
        parser.error(f"{root} is not a folder")
    add_pairs = {}
    for pair in split_list(args.spelling_add):
        if "=" not in pair:
            parser.error(f"--spelling-add expects british=us pairs, not '{pair}'")
        brit, us = pair.split("=", 1)
        add_pairs[brit.strip()] = us.strip()
    speller = Speller(add_pairs, set(split_list(args.spelling_allow)))
    checks = {"ban": ban_patterns(split_list(args.ban), args.whole_word), "dash": True, "secret": True}

    stats: Counter = Counter()
    files = list(walk(root, args.include_ignored, args.exclude, stats))
    learner = set() if args.no_spelling else {p.resolve() for p in masterdoc_pages(root)}
    known_keys = {norm_key(k): k for k in PLATFORM_KEYS}
    for out in sorted(arm_outputs(root, files)):
        known_keys.setdefault(norm_key(out), out)
    report = Report()
    inject_uses: dict[str, list[tuple[str, int, int]]] = defaultdict(list)
    marker_ids: dict[str, list[str]] = defaultdict(list)
    pending: Counter = Counter()

    for path, rel in files:
        ext = file_kind(path.name)
        stats["files scanned"] += 1
        if checks["ban"]:
            for name, rx in checks["ban"]:
                for m in rx.finditer(rel):
                    report.add("banned-name", rel, None, None, f"banned name '{name}' in the file or folder name")
        if ext in OFFICE_EXTS or ext == ".zip":
            try:
                data = path.read_bytes()
            except OSError:
                continue
            if ext == ".zip":
                stats["zip archives"] += 1
                scan_zip(report, rel, data, checks)
            else:
                stats["Office documents"] += 1
                scan_office(report, rel, data, checks)
            continue
        if not (ext in TEXT_EXTS or path.name.lower() in TEXT_NAMES):
            continue
        try:
            if path.stat().st_size > MAX_TEXT_BYTES:
                stats["skipped (larger than 20 MB)"] += 1
                continue
            text = decode(path.read_bytes())
        except OSError:
            continue
        if text is None:
            continue
        is_md = ext in (".md", ".markdown")
        spell = is_md and not args.no_spelling and (args.spelling_all or path.resolve() in learner)
        if is_md:
            raw_lines = text.splitlines()
            for number, line, prose, in_fence in markdown_lines(text):
                raw = raw_lines[number - 1]
                # Banned names and secrets count everywhere: in code, comments and prose.
                if checks["ban"]:
                    check_banned(report, rel, number, raw, checks)
                if IGNORE_MARK in raw:
                    continue
                check_secrets(report, rel, number, raw, ext)
                if in_fence:
                    check_dashes(report, rel, number, strip_dash_literals(line), None, entities=False)
                else:
                    check_dashes(report, rel, number, line, None if TABLE_RULE.match(prose) else prose, entities=True)
                    if spell:
                        for col, word, us in speller.check(spelling_prose(prose)):
                            report.add("spelling", rel, number, col, f"British spelling '{word}': use '{us}'")
                    for m in MARKER_START.finditer(prose):
                        pending[rel] += 1
                        mm = MARKER.match(prose, m.start())
                        if not mm:
                            report.add("marker", rel, number, m.start() + 1,
                                       "malformed screenshot marker: use [SCREENSHOT PENDING: E1T2S3 | what it must show | source: capture]")
                            continue
                        marker_ids[mm.group("id")].append(f"{rel}:{number}")
                        if not MARKER_ID.match(mm.group("id")):
                            report.add("marker", rel, number, m.start() + 1,
                                       f"unusual screenshot ID '{mm.group('id')}': use E<exercise>T<task>S<step> (E1T2S3, E1T2-1S4), GS<n> "
                                       "or <labid>-t<task>s<step> (lab1a-t2s3)")
                # Inject tags count in code blocks too: the platform substitutes them there.
                for m in INJECT_TAG.finditer(line):
                    tag = m.group(0)
                    attrs = {a.group(1).lower(): (a.group(2) if a.group(2) is not None else a.group(3)) for a in ATTR.finditer(tag)}
                    col = m.start() + 1
                    if not tag.rstrip(">").rstrip().endswith("/"):
                        closing = "</inject>" in line[m.end():].lower()
                        report.add("inject", rel, number, col, "paired <inject>...</inject> form; use the self-closing form"
                                   if closing else "inject tag is not self-closing; end it with />")
                    key = attrs.get("key")
                    if key is None:
                        report.add("inject", rel, number, col, "inject tag has no key attribute")
                    else:
                        inject_uses[key].append((rel, number, col))
                    if "enablecopy" not in attrs:
                        report.add("inject", rel, number, col, "inject tag has no enableCopy attribute; add enableCopy=\"true\" or \"false\"")
                    elif attrs["enablecopy"].lower() not in ("true", "false"):
                        report.add("inject", rel, number, col, f"enableCopy=\"{attrs['enablecopy']}\" must be true or false")
                unclosed = INJECT_OPEN.search(line)
                if unclosed:
                    report.add("inject", rel, number, unclosed.start() + 1,
                               "inject tag is not closed on its line, so the platform will not substitute it")
            continue
        for number, line in enumerate(text.splitlines(), start=1):
            if checks["ban"]:
                check_banned(report, rel, number, line, checks)
            if IGNORE_MARK in line:
                continue
            if ext in DASH_EXTS:
                cleaned = strip_dash_literals(line)
                check_dashes(report, rel, number, cleaned, cleaned, entities=ext in (".svg", ".html", ".htm"))
            check_secrets(report, rel, number, line, ext)
        if ext in RULE_EXTS:
            check_comment_rules(report, rel, text, ext)

    # Inject key spelling drift: compare every key with the platform keys, the ARM outputs and the
    # other spellings used in this repository.
    by_norm: dict[str, Counter] = defaultdict(Counter)
    for key, uses in inject_uses.items():
        by_norm[norm_key(key)][key] += len(uses)
    for key, uses in inject_uses.items():
        n = norm_key(key)
        message = None
        if n in LEGACY_KEYS:
            message = f"legacy inject key '{key}': use {LEGACY_KEYS[n]}"
        elif n in known_keys and known_keys[n] != key:
            message = f"inject key spelling drift: '{key}' should be '{known_keys[n]}'"
        elif n not in known_keys and len(by_norm[n]) > 1:
            preferred = by_norm[n].most_common(1)[0][0]
            if key != preferred:
                message = f"inject key spelling drift: '{key}' is also written '{preferred}' in this repository"
        if message:
            for rel, number, col in uses:
                report.add("inject", rel, number, col, message)
    for marker_id, places in marker_ids.items():
        if len(places) > 1:
            for place in places[1:]:
                rel, number = place.rsplit(":", 1)
                report.add("marker", rel, int(number), None, f"screenshot ID '{marker_id}' is also used at {places[0]}")
    for rel, n in sorted(pending.items()):
        report.add("screenshots", rel, None, None, f"{n} pending screenshot marker(s)")

    order = {"ERROR": 0, "WARN": 1, "INFO": 2}
    findings = sorted(report.findings, key=lambda f: (order[f.severity], f.cls, f.path, f.line or 0, f.col or 0))
    count = Counter(f.cls for f in findings)
    for (path, cls), extra in report.capped.items():
        count[cls] += extra
    errors = sum(count[c] for c in ERROR_CLASSES)
    warnings = sum(count[c] for c in WARN_CLASSES)
    total_pending = sum(pending.values())
    failed = errors > 0 or (args.strict and warnings > 0)

    if args.json:
        print(json.dumps({
            "repo": str(root),
            "stats": dict(stats),
            "learnerPages": sorted(p.relative_to(root).as_posix() for p in learner if p.is_relative_to(root)),
            "findings": [dict(asdict(f), severity=f.severity) for f in findings],
            "truncated": {f"{p}|{c}": n for (p, c), n in report.capped.items()},
            "summary": {"errors": errors, "warnings": warnings, "pendingScreenshots": total_pending,
                        "byClass": {c: count[c] for c in ERROR_CLASSES + WARN_CLASSES}},
            "result": "FAIL" if failed else "PASS",
        }, indent=2))
        return 1 if failed else 0

    print(f"qa-scan  {root}")
    print("  " + ", ".join(f"{k}: {v}" for k, v in sorted(stats.items())))
    if not args.no_spelling:
        scope = "every Markdown file" if args.spelling_all else f"{len(learner)} learner-facing page(s)"
        print(f"  spelling checked in {scope}; banned names: {', '.join(n for n, _ in checks['ban']) or 'none given'}")
    for f in findings:
        print(f"{f.severity:<5}  {f.cls:<12}  {f.location()}  {f.message}")
    for (path, cls), extra in sorted(report.capped.items()):
        print(f"{'ERROR' if cls in ERROR_CLASSES else 'WARN':<5}  {cls:<12}  {path}  ... and {extra} more of this kind in this file")
    print("Summary: " + f"{errors} error(s) (" + ", ".join(f"{c} {count[c]}" for c in ERROR_CLASSES) + "); "
          + f"{warnings} warning(s) (" + ", ".join(f"{c} {count[c]}" for c in WARN_CLASSES) + "); "
          + f"{total_pending} pending screenshot(s) on {len(pending)} page(s)")
    print(f"Result: {'FAIL (exit 1)' if failed else 'PASS (exit 0)'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
