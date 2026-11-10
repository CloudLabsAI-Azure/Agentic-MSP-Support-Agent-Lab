"""Regression tests for the QA tools in tools/qa.

Each test builds a small fixture repository in a temporary folder, runs one tool the way a lab
author does (as a separate Python process) and checks its findings and exit code. Run them after
changing any QA tool:

    python tools/qa/tests/test_qa_tools.py

Fixture text that the tools must catch (dashes, fake secrets) is assembled at run time, so this
file itself passes qa-scan. Tests that need git are skipped when git is not installed.
Requires Python 3.11+ and the standard library only.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

QA = Path(__file__).resolve().parent.parent
EM, EN = chr(0x2014), chr(0x2013)
SPACED = " " + "-" * 2 + " "
# Spelled out, these fixture words would make the credential checks flag this file in a lab repo.
PW = "pass" + "word"
SECURE = "ConvertTo-" + "SecureString"
RULE = "-" * 4


def run(tool: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, "-B", str(QA / tool), *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=300)


def write(root: Path, files: dict) -> None:
    for rel, content in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            path.write_bytes(content)
        else:
            path.write_text(content, encoding="utf-8", newline="\n")


def office(parts: dict[str, str]) -> bytes:
    """A minimal Office Open XML package: enough for the scanners, which read the XML parts."""
    import io
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("[Content_Types].xml", '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
        for name, xml in parts.items():
            z.writestr(name, xml)
    return buf.getvalue()


def zip_bytes(entries: dict[str, bytes | str]) -> bytes:
    import io
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, data in entries.items():
            z.writestr(name, data)
    return buf.getvalue()


def masterdoc(pages: list[str]) -> str:
    base = "https://docs-api.cloudlabs.ai/repos/raw.githubusercontent.com/Contoso/Lab/refs/heads/main/"
    return json.dumps([{"Name": "Lab", "Language": "English", "Files": [
        {"RawFilePath": base + p, "Order": i + 1} for i, p in enumerate(pages)]}])


class Fixture(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "repo"
        self.root.mkdir()

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def scan(self, *args: str) -> tuple[int, list[dict]]:
        proc = run("qa-scan.py", str(self.root), "--json", *args)
        self.assertIn(proc.returncode, (0, 1), proc.stderr)
        data = json.loads(proc.stdout)
        return proc.returncode, data["findings"]

    def found(self, findings: list[dict], cls: str, path_part: str) -> list[dict]:
        return [f for f in findings if f["cls"] == cls and path_part in f["path"]]


# ==== qa-scan.py ==============================================================================

class QaScanDashes(Fixture):
    def test_dashes_found_and_exempted(self) -> None:
        write(self.root, {
            "Instructions/page.md": "\n".join([
                "# Page",
                f"Prose with an em dash{EM}here.",
                f"Prose with a spaced{SPACED}double hyphen.",
                f"Inline code `git checkout{SPACED}file` is fine.",
                "| A | B |",
                f"|{SPACED}|{SPACED}|",
                "Entity &mdash; renders as a dash.",
                f"Skipped line{SPACED}qa-scan: ignore",
                "```bash",
                f"git checkout{SPACED}file",
                f"echo 'range 1{EN}2'",
                "```",
            ]) + "\n",
            "setup/script.ps1": f"# Comment with an en dash{EN}here\n$guard = @('{EM}', '{SPACED}')\n",
            "tools/check.py": f'for bad in ("{EM}", "{EN}", "{SPACED}"):\n    pass\n',
            "setup/doc.docx": office({"word/document.xml":
                f"<w:document><w:body><w:p><w:r><w:t>Policy{EM}text</w:t></w:r></w:p></w:body></w:document>"}),
            "setup/book.xlsx": office({"xl/sharedStrings.xml": f"<sst><si><t>Q1{EN}Q2</t></si></sst>"}),
        })
        code, findings = self.scan()
        self.assertEqual(code, 1)
        dashes = self.found(findings, "dash", "")
        lines = sorted((f["path"], f["line"]) for f in dashes)
        self.assertIn(("Instructions/page.md", 2), lines)      # em dash in prose
        self.assertIn(("Instructions/page.md", 3), lines)      # spaced double hyphen in prose
        self.assertIn(("Instructions/page.md", 7), lines)      # HTML entity
        self.assertIn(("Instructions/page.md", 11), lines)     # en dash inside a code block
        self.assertNotIn(("Instructions/page.md", 4), lines)   # inline code
        self.assertNotIn(("Instructions/page.md", 6), lines)   # table delimiter row
        self.assertNotIn(("Instructions/page.md", 8), lines)   # qa-scan: ignore
        self.assertNotIn(("Instructions/page.md", 10), lines)  # double hyphen inside a code block
        self.assertIn(("setup/script.ps1", 1), lines)
        self.assertNotIn(("setup/script.ps1", 2), lines)       # dash-only literals are a guard
        self.assertFalse(self.found(findings, "dash", "tools/check.py"))
        self.assertTrue(self.found(findings, "dash", "setup/doc.docx!word/document.xml"))
        self.assertTrue(self.found(findings, "dash", "setup/book.xlsx!xl/sharedStrings.xml"))


class QaScanBannedNames(Fixture):
    # The names are assembled, so a lab that bans one of them does not flag this file.
    FIRST, SECOND = "North" + "wind", "Tra" + "ders"
    OTHER = "Wood" + "grove Bank"

    def test_banned_names_everywhere(self) -> None:
        name = f"{self.FIRST} {self.SECOND}"
        split_runs = (f"<w:document><w:body><w:p><w:r><w:t>Prepared for {self.FIRST[:5]}</w:t></w:r>"
                      f"<w:r><w:t>{self.FIRST[5:]} {self.SECOND}</w:t></w:r></w:p></w:body></w:document>")
        write(self.root, {
            "README.md": f"A lab for {self.FIRST.lower()}-{self.SECOND.lower()}.\n",
            f"{self.FIRST}-notes.txt": "nothing here\n",
            "setup/doc.docx": office({"word/document.xml": split_runs,
                                      "docProps/core.xml": f"<cp:coreProperties><dc:creator>{name}</dc:creator></cp:coreProperties>"}),
            "setup/files.zip": zip_bytes({"notes/readme.txt": f"Contact {name}",
                                          "docs/inner.docx": office({"word/document.xml": split_runs})}),
        })
        code, findings = self.scan("--ban", f"{name},{self.OTHER}")
        self.assertEqual(code, 1)
        hits = self.found(findings, "banned-name", "")
        paths = {f["path"].split(" ")[0] for f in hits}
        self.assertIn("README.md", paths)                                     # hyphen matches a space
        self.assertIn("setup/doc.docx!word/document.xml", paths)              # split across runs
        self.assertIn("setup/doc.docx!docProps/core.xml", paths)              # document author
        self.assertIn("setup/files.zip!notes/readme.txt", paths)              # zip text entry
        self.assertIn("setup/files.zip!docs/inner.docx!word/document.xml", paths)  # document in a zip
        self.assertNotIn(f"{self.FIRST}-notes.txt", paths)                    # one word of the name only
        self.assertFalse(any(self.OTHER in f["message"] for f in hits))

    def test_whole_word(self) -> None:
        write(self.root, {"README.md": "Contosoville is a town.\n"})
        self.assertEqual(self.scan("--ban", "Contoso")[0], 1)
        self.assertEqual(self.scan("--ban", "Contoso", "--whole-word")[0], 0)


class QaScanSecrets(Fixture):
    def test_secrets_found(self) -> None:
        b64 = "A" * 86 + "=="
        token = "gh" + "p_" + "a1B2" * 9
        aws = "AK" + "IA" + "ABCDEFGHIJKLMNOP"
        jwt = "ey" + "JhbGciOiJIUzI1NiJ9." + "ey" + "JzdWIiOiIxMjM0NTYifQ." + "c2lnbmF0dXJlMTIzNDU2"
        pem = "-----BEGIN " + "RSA PRIVATE KEY-----"
        write(self.root, {
            "a/token.txt": f"token={token}\n",
            "a/aws.json": f'{{"id": "{aws}"}}\n',
            "a/jwt.md": f"Header: Bearer {jwt}\n",
            "a/key.txt": pem + "\n",
            "a/conn.json": f'{{"cs": "DefaultEndpointsProtocol=https;AccountName=x;AccountKey={b64};"}}\n',
            "a/sas.md": "https://x.blob.core.windows.net/c/f?sv=2022-11-02&sig=" + "abcDEF123%2B" * 3 + "\n",
            "a/pw.ps1": f"${PW} = 'Contoso123!'\n$s = {SECURE} 'Lab2026!x' -AsPlainText -Force\n",
            "a/sql.json": '{"c": "Server=tcp:x;Database=d;User Id=u;' + PW.title() + '=Hunter2xyz;"}\n',
            "a/guide.md": PW.title() + ": **Pa55word!**\n",
        })
        code, findings = self.scan()
        self.assertEqual(code, 1)
        files = {f["path"] for f in self.found(findings, "secret", "")}
        for rel in ("a/token.txt", "a/aws.json", "a/jwt.md", "a/key.txt", "a/conn.json", "a/sas.md", "a/pw.ps1",
                    "a/sql.json", "a/guide.md"):
            self.assertIn(rel, files)
        self.assertEqual(len(self.found(findings, "secret", "a/pw.ps1")), 2)
        self.assertFalse(any(token in f["message"] for f in findings), "secret values must be masked")

    def test_placeholders_are_not_secrets(self) -> None:
        integrity = "sha512-" + "B" * 86 + "=="
        write(self.root, {
            "setup/vm.ps1": f"${PW} = Read-Host -AsSecureString\n$p = $env:LAB_{PW.upper()}\n",
            "setup/deploy-01.json": "\n".join([
                '{"parameters": {"admin' + PW.title() + '": {"type": "securestring"}},',
                ' "variables": {"a": "[concat(\' -Azure' + PW.title() + ' \', parameters(\'Azure' + PW.title() + '\'))]"}}']) + "\n",
            "setup/deploy-01.parameters.json": '{"parameters": {"admin' + PW.title() + '": {"value": "GEN-PASSWORD"}}}\n',
            "Instructions/page.md": f'- **{PW.title()}:** <inject key="AzureAdUserPassword" enableCopy="true"/>\n'
                                    f"- {PW.title()}: the Temporary Access Pass from the Environment tab\n",
            "app/package-lock.json": f'{{"integrity": "{integrity}"}}\n',
            "app/.env.example": f"AZURE_OPENAI_API_KEY=<your-key>\nDB_{PW.upper()}=\n",
        })
        code, findings = self.scan()
        self.assertEqual(self.found(findings, "secret", ""), [])
        self.assertEqual(code, 0)


class QaScanSpelling(Fixture):
    def test_learner_pages_only_by_default(self) -> None:
        british = "Check the licence, the colour and the organisation; recognised users enrol in the programme."
        write(self.root, {
            "masterdoc.json": masterdoc(["Instructions/exercise-1.md"]),
            "Instructions/exercise-1.md": f"# Exercise\n{british}\nCode `colour` and [link](./grey.md) are skipped.\n",
            "README.md": f"# Readme\n{british}\n",
        })
        code, findings = self.scan()
        self.assertEqual(code, 0)
        words = {f["message"].split("'")[1].lower() for f in self.found(findings, "spelling", "exercise-1.md")}
        self.assertEqual(words, {"licence", "colour", "organisation", "recognised", "enrol", "programme"})
        self.assertFalse(self.found(findings, "spelling", "README.md"))
        _, findings = self.scan("--spelling-all", "--spelling-allow", "programme")
        self.assertTrue(self.found(findings, "spelling", "README.md"))
        self.assertFalse(any("programme" in f["message"] for f in findings))


class QaScanInject(Fixture):
    def test_inject_problems(self) -> None:
        write(self.root, {
            "setup/deploy-01.json": json.dumps({"$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
                                                "outputs": {"Web App URL": {"type": "string", "value": "x"}}}),
            "Instructions/page.md": "\n".join([
                '1. <inject key="DeploymentID" enableCopy="false"/>',
                '2. <inject key="Deployment ID" enableCopy="false"/>',
                '3. <inject key="deploymentid" enableCopy="false"/>',
                '4. <inject key="UniqueID" enableCopy="false"/>',
                '5. <inject key="AzureAdUserEmail"/>',
                '6. <inject key="AzureAdUserEmail" enableCopy="yes"/>',
                '7. <inject key="AzureAdUserEmail" enableCopy="true">',
                '8. <inject key="Web App URL" enableCopy="true"/>',
                '9. <inject key="AzureAdUserEmail" enableCopy="true"',
            ]) + "\n",
        })
        code, findings = self.scan()
        self.assertEqual(code, 0)   # inject problems are warnings
        lines = sorted({f["line"] for f in self.found(findings, "inject", "page.md")})
        self.assertEqual(lines, [2, 3, 4, 5, 6, 7, 9])


class QaScanCommentRules(Fixture):
    """Decorative hyphen rules in comments and docstrings are reported; syntax is not."""

    def test_rules_in_comments_and_docstrings(self) -> None:
        py = "\n".join([
            '"""Module.',
            "",
            "Parameters",
            "-" * 10,                                           # 4: numpy underline: rule
            "| a | b |",
            "|---|---|",                                        # 6: table row in a docstring: fine
            '"""',
            f"# {RULE} helpers {RULE}",                         # 8: comment rule
            "# run az vm list --output table",                   # 9: CLI flag: fine
            "# " + "-----BEGIN " + "CERTIFICATE-----",          # 10: PEM marker: fine
            "# ==== helpers ====",                              # 11: house style: fine
            'HR = "---"',                                       # 12: string, not a comment: fine
            'TEMPLATE = """',
            "---",                                              # 14: generated Markdown in a string: fine
            '"""',
            "def f():",
            '    """Do it.',
            "",
            "    Returns",
            "    " + "-" * 7,                                   # 20: docstring underline: rule
            '    """',
            f"x = 1  # {RULE}",                                 # 22: trailing comment rule
        ]) + "\n"
        ps1 = "\n".join([
            "<#",
            ".SYNOPSIS",
            "-" * 8,                                            # 3: rule inside comment-based help
            "#>",
            f"# {RULE} setup",                                  # 5: comment rule
            "$doc = @\"",
            "---",                                              # 7: here-string content: fine
            "\"@",
            "git log --oneline  # flags are fine",             # 9: fine
            "# ==== done",                                      # 10: fine
        ]) + "\n"
        sh = "\n".join([
            "#!/bin/bash",
            f"# {RULE}",                                        # 2: rule
            "cat <<EOF > notes.md",
            f"# {RULE} heredoc content",                        # 4: generated content: fine
            "EOF",
        ]) + "\n"
        js = "\n".join([
            f"// {RULE} section",                               # 1: rule
            f"/* {RULE} */",                                    # 2: rule
            'const hr = "---";',                                # 3: string: fine
        ]) + "\n"
        cs = f"/// {RULE} summary {RULE}\nvar x = \"---\";\n"
        md = "---\ntitle: front matter\n---\n\n# Page\n\n---\n\n| A |\n|---|\n"
        write(self.root, {"a/rules.py": py, "a/rules.ps1": ps1, "a/rules.sh": sh, "a/rules.js": js,
                          "a/rules.ts": js, "a/Rules.cs": cs, "a/page.md": md})
        code, findings = self.scan()
        self.assertEqual(code, 0)   # comment rules are warnings
        got = {(f["path"], f["line"]) for f in self.found(findings, "comment-rule", "")}
        expected = {("a/rules.py", 4), ("a/rules.py", 8), ("a/rules.py", 20), ("a/rules.py", 22),
                    ("a/rules.ps1", 3), ("a/rules.ps1", 5),
                    ("a/rules.sh", 2),
                    ("a/rules.js", 1), ("a/rules.js", 2), ("a/rules.ts", 1), ("a/rules.ts", 2),
                    ("a/Rules.cs", 1)}
        self.assertEqual(got, expected)
        self.assertEqual(run("qa-scan.py", str(self.root), "--strict").returncode, 1)


class QaScanMarkers(Fixture):
    def test_markers(self) -> None:
        write(self.root, {"Instructions/page.md": "\n".join([
            "> **[SCREENSHOT PENDING: E1T1S1 | The page | source: capture]**",
            "> **[SCREENSHOT PENDING: E1T1S1 | Same ID again | source: capture]**",
            "> **[SCREENSHOT PENDING: Step 3 | Odd ID | source: capture]**",
            "> **[SCREENSHOT PENDING: E1T2S1 missing the source]**",
            "```text",
            "[SCREENSHOT PENDING: E9T9S9 | in a code block | source: capture]",
            "```",
        ]) + "\n"})
        code, findings = self.scan()
        self.assertEqual(code, 0)
        markers = sorted(f["line"] for f in self.found(findings, "marker", "page.md"))
        self.assertEqual(markers, [2, 3, 4])
        info = self.found(findings, "screenshots", "page.md")
        self.assertEqual(info[0]["message"].split()[0], "4")

    def test_lab_prefixed_ids(self) -> None:
        # A course of separate labs prefixes every ID with its lab ID so the IDs stay unique.
        write(self.root, {"Instructions/Labs/Lab-1A.md": "\n".join([
            "> **[SCREENSHOT PENDING: lab1a-t2s3 | Lab 1A, task 2, step 3 | source: capture]**",
            "> **[SCREENSHOT PENDING: lab4f-t3s10 | Lab 4F, task 3, step 10 | source: capture]**",
            "> **[SCREENSHOT PENDING: lab1a-t2-1s4 | Lab 1A, sub-task 2.1, step 4 | source: capture]**",
            "> **[SCREENSHOT PENDING: lab1a-step3 | Not a scheme | source: capture]**",
        ]) + "\n"})
        code, findings = self.scan()
        self.assertEqual(code, 0)
        markers = [(f["line"], f["message"]) for f in self.found(findings, "marker", "Lab-1A.md")]
        self.assertEqual([line for line, _ in markers], [4])
        self.assertIn("unusual screenshot ID 'lab1a-step3'", markers[0][1])


@unittest.skipUnless(shutil.which("git"), "git is not installed")
class QaScanGitIgnore(Fixture):
    def test_ignored_files_skipped_unless_asked(self) -> None:
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        write(self.root, {".gitignore": "build/\n", "build/out.md": f"Dash{EM}here\n", "ok.md": "Fine.\n"})
        self.assertEqual(self.scan()[0], 0)
        self.assertEqual(self.scan("--include-ignored")[0], 1)


# ==== check_links.py ==========================================================================

class CheckLinks(Fixture):
    def test_links_and_anchors(self) -> None:
        write(self.root, {
            "README.md": "\n".join([
                "# Lab",
                "## Delivery Path",
                "## Task 1: Create **Deal Desk** `app_name` <inject key=\"DeploymentID\" enableCopy=\"false\"/>",
                "## Repeat",
                "## Repeat",
                "Setext heading",
                "==============",
                "[ok](#delivery-path) [ok](#task-1-create-deal-desk-app_name) [ok](#repeat-1) [ok](#setext-heading)",
                "[ok](docs/guide.md#next-steps) [ok](docs/) [ok](https://example.com/x) [ok](<docs/guide.md>)",
                "[bad](docs/missing.md) [bad](docs/guide.md#nowhere) [bad](#nope) [bad](../outside.md)",
                "[case](Docs/guide.md)",
                "![img](media/missing.png)",
                "`[not a link](missing.md)`",
                "<!-- [commented](missing.md) -->",
                '<a href="docs/gone.md">x</a> <img src="media/gone.png">',
                "[ref]: docs/also-missing.md",
                '<a name="custom-anchor"></a>[ok](#custom-anchor)',
                "```",
                "[in code](missing.md)",
                "```",
            ]) + "\n",
            "docs/guide.md": "# Guide\n\n## Next steps\n",
        })
        proc = run("check_links.py", str(self.root))
        self.assertEqual(proc.returncode, 1)
        out = proc.stdout
        for needle in ("MISSING  README.md:10  ->  docs/missing.md", "ANCHOR   README.md:10  ->  docs/guide.md#nowhere",
                       "ANCHOR   README.md:10  ->  #nope", "OUTSIDE  README.md:10  ->  ../outside.md",
                       "CASE     README.md:11  ->  Docs/guide.md", "MISSING  README.md:12  ->  media/missing.png",
                       "MISSING  README.md:15  ->  docs/gone.md", "MISSING  README.md:15  ->  media/gone.png",
                       "MISSING  README.md:16  ->  docs/also-missing.md"):
            self.assertIn(needle, out)
        self.assertEqual(out.count("\n") - 1, 9, out)   # nine problems and the summary line
        proc = run("check_links.py", str(self.root), "--no-images")
        self.assertNotIn("media/missing.png", proc.stdout)

    @unittest.skipUnless(shutil.which("git"), "git is not installed")
    def test_link_to_ignored_file(self) -> None:
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        write(self.root, {".gitignore": "*.zip\n", "README.md": "[zip](files.zip)\n", "files.zip": b"PK"})
        proc = run("check_links.py", str(self.root))
        self.assertEqual(proc.returncode, 1)
        self.assertIn("IGNORED  README.md:1", proc.stdout)


# ==== make_screenshot_todo.py =================================================================

class ScreenshotTodo(Fixture):
    def test_inventory(self) -> None:
        learn = "https://learn.microsoft.com/media/x.png"
        write(self.root, {
            "masterdoc.json": masterdoc(["Instructions/getting-started.md", "Instructions/exercise-1.md"]),
            "README.md": "# Lab\n\n## Delivery Path\n",
            "Instructions/getting-started.md": "> **[SCREENSHOT PENDING: GS1 | Lab environment | source: reuse]**\n",
            "Instructions/exercise-1.md": "\n".join([
                "   > **[SCREENSHOT PENDING: E1T1S1 | Portal home | source: capture]**",
                f"   > **[SCREENSHOT PENDING: E1T2-1S4 | Settings / pane | source: learn {learn}]**",
                "   > **[SCREENSHOT PENDING: E1T3S1 missing parts]**",
            ]) + "\n",
        })
        out = self.root / "SCREENSHOT-TODO.md"
        proc = run("make_screenshot_todo.py", str(self.root))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        text = out.read_text(encoding="utf-8")
        self.assertIn("**Delivery path: Phase 5 of 8, run the pilot.**", text)
        self.assertIn("[README.md](README.md#delivery-path)", text)
        self.assertIn("**Total: 3** (1 reuse, 1 with a Microsoft Learn reference, 1 capture only).", text)
        self.assertLess(text.index("## getting-started.md"), text.index("## exercise-1.md"))
        self.assertIn(f"| E1T2-1S4 | Settings / pane | [Learn reference]({learn}) | 2 |", text)
        self.assertIn("## Markers that could not be read", text)
        self.assertIn("**Next:** finish the rest of the pilot checklist, then deliver the session (Phase 6).", text)
        self.assertEqual(run("make_screenshot_todo.py", str(self.root), "--check").returncode, 0)
        write(self.root, {"Instructions/exercise-1.md": "No markers left.\n"})
        self.assertEqual(run("make_screenshot_todo.py", str(self.root), "--check").returncode, 1)

    def test_fallback_without_masterdoc(self) -> None:
        write(self.root, {"Instructions/exercise-2.md": "> **[SCREENSHOT PENDING: E2T1S1 | B | source: capture]**\n",
                          "Instructions/exercise-10.md": "> **[SCREENSHOT PENDING: E10T1S1 | C | source: capture]**\n",
                          "Instructions/getting-started.md": "> **[SCREENSHOT PENDING: GS1 | A | source: reuse]**\n"})
        proc = run("make_screenshot_todo.py", str(self.root), "--out", str(self.root / "todo.md"))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        text = (self.root / "todo.md").read_text(encoding="utf-8")
        order = [text.index(h) for h in ("## getting-started.md", "## exercise-2.md", "## exercise-10.md")]
        self.assertEqual(order, sorted(order))

    def test_course_of_separate_labs(self) -> None:
        # Microsoft Learning repositories: readme.md, Instructions/Labs/Media, lab-prefixed IDs.
        (self.root / "Instructions/Labs/Media").mkdir(parents=True)
        write(self.root, {
            "readme.md": "# Course\n\n## Delivery Path\n",
            "Instructions/Labs/Getting-Started.md": "> **[SCREENSHOT PENDING: GS1 | Lab environment | source: reuse]**\n",
            "Instructions/Labs/Lab-1A-Configure-PIM.md": "\n".join([
                "   > **[SCREENSHOT PENDING: lab1a-t2s3 | Role settings | source: capture]**",
                "   > **[SCREENSHOT PENDING: lab1a-t2s10 | Assignment list | source: capture]**",
            ]) + "\n",
        })
        proc = run("make_screenshot_todo.py", str(self.root))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        text = (self.root / "SCREENSHOT-TODO.md").read_text(encoding="utf-8")
        self.assertIn("[readme.md](readme.md#delivery-path)", text)
        self.assertNotIn("README.md", text)
        self.assertIn("`Instructions/Labs/Media`", text)
        self.assertIn("whose path is `./Media/<ID>.png`.", text)
        self.assertNotIn("./media/", text)
        self.assertIn("| lab1a-t2s3 | Role settings | capture | 1 |", text)
        self.assertIn("| lab1a-t2s10 | Assignment list | capture | 2 |", text)
        self.assertIn("**Total: 3**", text)
        self.assertNotIn("## Markers that could not be read", text)
        self.assertEqual(run("make_screenshot_todo.py", str(self.root), "--check").returncode, 0)


# ==== check-labfiles-zip.py ===================================================================

class LabFilesZip(Fixture):
    def setUp(self) -> None:
        super().setUp()
        write(self.root, {
            "masterdoc.json": masterdoc(["Instructions/exercise-1.md"]),
            "Instructions/exercise-1.md": "\n".join([
                "1. Open `C:\\LabFiles\\agents\\Policy.docx` and the folder C:\\LabFiles\\hunting\\.",
                "1. Open `C:\\LabFiles\\My Docs\\Plan One.xlsx` (the name has spaces).",
                "1. Run C:/LabFiles/tools/Check.ps1, then open C:\\labfiles\\AGENTS\\policy.docx.",
                '1. Upload C:\\LabFiles\\cowork\\Contoso-<inject key="DeploymentID" enableCopy="false"/>.zip',
                "1. Open C:\\LabFiles\\missing\\Gone.txt.",
                "```powershell",
                "Set-Location C:\\LabFiles\\app",
                "Get-Content C:\\LabFiles\\app\\.env",
                "```",
            ]) + "\n",
        })
        self.entries = {"agents/Policy.docx": b"x", "hunting/q.kql": b"x", "My Docs/Plan One.xlsx": b"x",
                        "tools/Check.ps1": b"x", "app/package.json": b"x"}

    def check(self, *args: str) -> subprocess.CompletedProcess:
        return run("check-labfiles-zip.py", str(self.root), *args)

    def test_zip(self) -> None:
        zpath = Path(self.tmp.name) / "labfiles.zip"
        zpath.write_bytes(zip_bytes({"LabFiles/" + k: v for k, v in self.entries.items()}))   # top folder stripped
        proc = self.check(str(zpath))
        self.assertEqual(proc.returncode, 1, proc.stdout)
        out = proc.stdout
        for needle in ("present  C:\\LabFiles\\agents\\Policy.docx", "present  C:\\LabFiles\\hunting",
                       "present  C:\\LabFiles\\My Docs\\Plan One.xlsx", "present  C:\\LabFiles\\tools\\Check.ps1",
                       "present  C:\\LabFiles\\app", "dynamic  C:\\LabFiles\\cowork\\Contoso-{DeploymentID}.zip",
                       "MISSING  C:\\LabFiles\\missing\\Gone.txt", "MISSING  C:\\LabFiles\\app\\.env"):
            self.assertIn(needle, out)
        self.assertIn("(+1 more)", out)   # Policy.docx is referenced twice, in two letter cases
        allow = Path(self.tmp.name) / "allow.txt"
        allow.write_text("# created on the VM\napp/.env\ncowork/*.zip\n", encoding="utf-8")
        proc = self.check(str(zpath), "--allow", "missing/*", "--allow-file", str(allow))
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn("3 allowed, 0 dynamic, 0 missing", proc.stdout)

    def test_folder(self) -> None:
        folder = Path(self.tmp.name) / "labfiles"
        write(folder, self.entries)
        proc = self.check(str(folder), "--allow", "app/.env", "--allow", "missing/*", "--allow", "cowork/*")
        self.assertEqual(proc.returncode, 0, proc.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
