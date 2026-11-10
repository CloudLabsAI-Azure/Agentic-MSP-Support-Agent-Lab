# Lab QA Tools

Deterministic checks that every v2 lab passes before it is pushed. They are copied into each lab repository with the rest of the toolkit, so they live in `tools/qa/` and the commands below run from the lab repository root. All four tools need only Python 3.11 or later and its standard library (git is used when it is installed).

## The QA gate

Run the gate in this order and fix each step before the next one:

1. **Lint:** `pwsh <plugin>/skills/cloudlabs-knowledge/scripts/lint-lab.ps1 -Path . -Profile auto` from the CloudLabs Lab Builder plugin. Zero BLOCKERs; WARNs only for pending screenshots and validation GUID placeholders.
2. **Scan:** `python tools/qa/qa-scan.py . --ban "<names>"`, where the names are the real customer, partner or requester behind the lab. Zero errors.
3. **Links:** `python tools/qa/check_links.py .` Zero problems.
4. **Lab files:** build the lab files zip (`setup/Build-LabFilesZip.ps1`), then `python tools/qa/check-labfiles-zip.py . <zip>`. Nothing missing.
5. **Parse checks:** every PowerShell script parses and every JSON file loads (commands below). Parse the scripts that run on the lab VM with Windows PowerShell 5.1 as well when the VM image has no PowerShell 7.
6. **Screenshot borders:** `python tools/screenshots/Add-Border.py Instructions --check`. Every screenshot has the 2 px gray border (run it without `--check` to add the border to older images). Needs Pillow (`tools/screenshots/README.md`).

Keep `SCREENSHOT-TODO.md` current with `python tools/qa/make_screenshot_todo.py` after every guide edit; `--check` makes that a gate step too.

```powershell
# Every .ps1 file parses (run with pwsh, and with powershell.exe for VM scripts).
Get-ChildItem -Recurse -File -Filter *.ps1 | Where-Object FullName -NotMatch '[\\/](\.git|node_modules)[\\/]' | ForEach-Object {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors)
    foreach ($e in $errors) { '{0}:{1}: {2}' -f $_.FullName, $e.Extent.StartLineNumber, $e.Message }
}

# Every .json file loads with a strict parser (the platform's parsers are strict).
Get-ChildItem -Recurse -File -Filter *.json | Where-Object FullName -NotMatch '[\\/](\.git|node_modules)[\\/]' | ForEach-Object {
    $file = $_
    try { $null = [System.Text.Json.JsonDocument]::Parse((Get-Content -LiteralPath $file.FullName -Raw)) }
    catch { '{0}: {1}' -f $file.FullName, $_.Exception.Message }
}
```

Both commands print nothing when everything parses.

## qa-scan.py

One pass over the whole repository that reports problems with their file and line. Inside Office documents and zip archives the location names the part or entry, for example `Policy.docx!word/document.xml segment:12` (the twelfth paragraph, cell or field of that part).

```text
python tools/qa/qa-scan.py [repo] [--ban "Name1,Name2"] [--whole-word] [--include-ignored]
                           [--exclude GLOB] [--spelling-all] [--no-spelling]
                           [--spelling-add "british=us,..."] [--spelling-allow "word,..."]
                           [--json] [--strict]
```

| Class | Severity | What it finds |
|---|---|---|
| `dash` | error | Em dashes, en dashes and their HTML entities anywhere, even in code, because they break commands that learners copy; spaced double hyphens used as punctuation outside code (fenced blocks, inline code and HTML comments are skipped, so command lines with an end-of-options marker stay legal). Checked in `.md`, `.ps1`, `.psm1`, `.psd1`, `.py`, `.json`, `.kql`, `.txt`, `.csv`, `.svg`, `.yml`, `.sh` and `.bicep` files and in the text of `.docx`, `.xlsx` and `.pptx` files. A quoted string that holds only dash characters (a dash check in a script) is not reported. |
| `banned-name` | error | The names given with `--ban`, case-insensitive, with spaces, hyphens and underscores between words matching each other or nothing. Checked in file and folder names, every text file, the text and attributes of Office documents (including their author properties), and the entry names, text entries and nested documents of zip archives. `--whole-word` stops matches inside longer words. |
| `secret` | error | Private keys, storage account keys and shared access keys, SAS signatures, GitHub tokens, AWS keys, JSON web tokens, Microsoft Entra client secrets, passwords in connection strings and URIs, and literal password assignments in code, configuration files and Markdown. Placeholders such as GEN-PASSWORD tokens, variables and inject tags are ignored. Values are masked in the output. |
| `spelling` | warning | British spellings in learner-facing Markdown, with the US spelling to use: the `-ise`, `-our`, `-re` and `-ence` families and words such as `licence`, `organisation`, `colour`, `behaviour`, `enrolment`, `programme`, `catalogue` and `grey`. Learner-facing pages are the ones `masterdoc.json` lists (or `Instructions/**/*.md` without a masterdoc); `--spelling-all` checks every Markdown file. Code, links, file names and HTML are skipped. |
| `inject` | warning | Inject tags that are not self-closing, are not closed on their line, have no key or no `enableCopy`, or have an `enableCopy` other than true or false; key spelling drift (a key that differs only in case or spacing from a platform key, an ARM output in a `deploy-*.json` template or another spelling in the repository); legacy keys. Code blocks count, because the platform substitutes tags there too. |
| `comment-rule` | warning | Decorative rules of three or more hyphens in comments and docstrings of PowerShell, Python, shell, JavaScript, TypeScript, C#, KQL, Bicep, Terraform and YAML files. House style uses `# ====` rules and `====` docstring underlines. Comments are read with a tokenizer, so strings, here-strings and heredocs are not checked, and CLI flags, Markdown table rows and PEM markers do not count. |
| `marker` | warning | Pending screenshot markers that are malformed, use an unusual ID, or repeat an ID used elsewhere. |
| `screenshots` | information | The number of pending screenshot markers on each page. |

Notes:

- Files that git ignores are skipped, as are `.git`, `node_modules`, virtual environments, caches and Office lock files. Use `--include-ignored` to scan a built lab files zip or other build output that is git-ignored, and `--exclude "research/*"` to skip a folder.
- A line that contains the text `qa-scan: ignore` is skipped by every check except banned names.
- The exit code is 1 when there is any error, or any warning with `--strict`; `--json` prints the findings as JSON.

## check_links.py

Checks every relative link and anchor in every Markdown file, so the delivery path stays connected: "Start of the path" links, Next links and links between guide pages.

```text
python tools/qa/check_links.py [repo] [--skip-dir NAME] [--no-images]
```

- Checks inline links and images, reference definitions and HTML `a` and `img` tags, outside fenced code, inline code and HTML comments. Links with a scheme (https, mailto) are not checked.
- Anchors follow GitHub's heading rules: the rendered heading text in lowercase, punctuation removed, each space turned into a hyphen, and `-1`, `-2` added to repeated headings. Explicit `<a name>` and `id` anchors count too.
- Reports `MISSING` (no such file or folder), `ANCHOR` (no such heading), `CASE` (the target exists only with different letter case, which works on Windows but breaks on GitHub), `OUTSIDE` (the target is outside the repository) and `IGNORED` (git ignores the target, so it is missing on GitHub).
- Exit code 1 when there is any problem.

## check-labfiles-zip.py

Lists every path under the lab files root that the guide pages mention, in prose, inline code and code blocks, and reports which are missing from the lab files zip. Matching ignores letter case, like Windows; a folder passes when the archive has anything inside it.

```text
python tools/qa/check-labfiles-zip.py <repo> <zip or folder> [--root "C:\LabFiles"] [--allow PATTERN]
                                      [--allow-file FILE] [--all-markdown] [--zip-prefix PREFIX]
```

- Statuses: `present`; `allowed` (matches an allow pattern: something the VM creates at provisioning time or the learner creates, such as a generated package or a settings file written by the setup script); `dynamic` (the path holds an inject tag or a variable, so it differs per deployment and cannot be in a static archive; confirm the provisioning script creates it, then allow it); `MISSING`.
- Allow patterns are globs below the root, written with forward slashes, for example `cowork/plugin/*.zip`; `*` also matches across folders. An allow file holds one pattern per line, and `#` starts a comment.
- Check the built zip rather than the source folder when the build adds files (a pinned sample, a lockfile).
- Write paths that contain spaces in backticks or quotes, so the tool reads the whole path.
- Exit code 1 when anything is missing.

## make_screenshot_todo.py

Builds `SCREENSHOT-TODO.md` from the pending screenshot markers in the guide pages, in the order `masterdoc.json` lists them. The marker format and the ID convention:

```text
> **[SCREENSHOT PENDING: E1T2S3 | what the screenshot must show | source: capture]**

E1T2S3   exercise 1, task 2, step 3     E1T2-1S4   sub-task 2.1, step 4     GS4   getting-started, step 4
lab1a-t2s3   lab 1A, task 2, step 3, in a course of separate labs (the lab id keeps IDs unique)
source:  capture | reuse | learn <Microsoft Learn image URL>
```

```text
python tools/qa/make_screenshot_todo.py [repo] [--out FILE] [--check] [--minutes-per-shot N]
                                        [--never-capture TEXT]
```

The file opens with the delivery path header (Phase 5 of 8, run the pilot), who captures the screenshots and how long it takes, and the capture rules: a participant account, the lab's fictional company, never a real person, secret or credential (add lab-specific items with `--never-capture`), numbered balloons, and where to save each image. Then comes one table per page with links to the Microsoft Learn reference images, a list of markers that could not be read, and the Next line to the facilitator guide's phase checklist. Links to README and the facilitator guide are added only when their targets exist; the README link and the media folder keep their real case (`readme.md`, `Media`, as in Microsoft Learning repositories), because GitHub paths are case-sensitive. `--check` writes nothing and exits with code 1 when the file is missing or out of date.

## Tests

`python tools/qa/tests/test_qa_tools.py` runs the regression tests: each test builds a small fixture repository in a temporary folder, runs one tool and checks its findings. Run them after changing any of these tools.

The diagram toolkit, which has its own checks for diagram text, layout and timing, is described in [the diagram toolkit README](../diagrams/README.md).
