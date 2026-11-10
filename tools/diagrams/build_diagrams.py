"""Animated diagrams for the Agentic MSP Support Agent Guided Lab.

One function per diagram, registered in DIAGRAMS. Each writes Instructions/media/<name>.svg; render
the animated PNG the guide embeds with tools/diagrams/Render-Diagrams.ps1.

    architecture                      Figure B1: your lab environment and the six numbered steps of one request
                                      (getting-started, README)
    exercise-1-grounding              Task 1.2: export, index, load and count, knowledge source, cited answer
    exercise-2-ticket-intelligence    TCK-10561 matches and decoys, Woodgrove Bank's open tickets, the cited
                                      triage and the SLA risk ranking (facts from the seed manifest)
    exercise-3-mcp-read-path          a read tool call, its structured failures and the redeploy loop
    exercise-4-approval-flow          approval on every write, reject, duplicate, public reply or internal note
    exercise-5-identity-token-flow    the token chain, played for the Tier 1 and then the Senior Technician
    exercise-6-protection-and-trail   what the agent cannot return, and one correlation ID across every hop
    exercise-7-end-to-end             TCK-10562 from the new incident to approved writes and the business case
    session-journey                   the 4-hour lab window, the seven exercises and the review window
                                      (getting-started, README, AGENDA)

Record numbers and names in exercises 2, 4, 5, 6 and 7 come from the seed manifest's scenarios
(agentic-msp-mcp-server/fixtures/seed/manifest.json); change them here when the seed changes.

Usage (from the lab repository root, after staging the icons once):
    pwsh tools/diagrams/Get-ProductIcons.ps1 -IconsPath tools/diagrams/icons
    python tools/diagrams/build_diagrams.py [name ...] [--out FOLDER] [--icons FOLDER]
    pwsh tools/diagrams/Render-Diagrams.ps1 -Name <name>

The script prints every warning from svgkit (text that may overflow, elements outside the canvas,
timings that do not divide the loop) and exits with code 1 when there is one, so fix them all.
Requires Python 3.11+. Example names use the Deployment ID 123456.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from svgkit import Diagram, FONT, INK, INK2, MONO, TONES, esc, fmt, mono_width

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
DEFAULT_OUT = REPO / "Instructions" / "media"
DEFAULT_ICONS = HERE / "icons"

# One correlation ID follows a request through every diagram (the GUID in Get-ActionTrail.ps1's example).
CID = "0b6f3c9e"
LINE_SOFT = "#D8DEE4"


# =============================================================================
# Shared helpers
# =============================================================================
def _vis(d: Diagram, appear) -> str:
    """Opening tag of a group that is visible only during `appear` (always visible when None)."""
    return f'<g opacity="0">{d.tl.anim("opacity", appear, 1, 0, fade=0.25)}' if appear else "<g>"


def tcard(d: Diagram, key: str, x: float, y: float, w: float, h: float, icon: str, title: str, lines=(),
          tone: str = "blue", glow=(), icon_size: float = 28, title_size: float = 14, mono_lines=(),
          style: str = "card", appear=None, glow_tone=None, alt_glow=None) -> None:
    """A card with its icon at the top and the text below it, so a narrow card keeps its whole width for text.

    mono_lines : indexes of lines drawn in the monospace font (object names).
    """
    d.card(key, x, y, w, h, "", (), tone=tone, style=style, glow=glow, glow_tone=glow_tone, alt_glow=alt_glow,
           appear=appear)
    avail = w - 32
    ty = y + 16 + icon_size + 22
    out = [_vis(d, appear),
           f'<use href="#{d.symbol(icon)}" x="{fmt(x + 18)}" y="{fmt(y + 16)}" width="{fmt(icon_size)}" height="{fmt(icon_size)}"/>']
    d.check(title, title_size, True, avail, f"card {key}")
    out.append(f'<text x="{fmt(x + 18)}" y="{fmt(ty)}" font-family="{FONT}" font-size="{fmt(title_size)}" font-weight="600" '
               f'fill="{INK}">{esc(title)}</text>')
    for i, line in enumerate(lines):
        ly = ty + 18 + i * 16
        if i in mono_lines:
            if mono_width(line, 11.5) > avail:
                d.warnings.append(f"{d.name}: '{line}' may overflow card {key}")
            out.append(f'<text x="{fmt(x + 18)}" y="{fmt(ly)}" font-family="{MONO}" font-size="11.5" fill="{TONES[tone][3]}">'
                       f'{esc(line)}</text>')
        else:
            d.check(line, 12, False, avail, f"card {key}")
            out.append(f'<text x="{fmt(x + 18)}" y="{fmt(ly)}" font-family="{FONT}" font-size="12" fill="{INK2}">{esc(line)}</text>')
    if ty + 18 + (len(lines) - 1) * 16 + 6 > y + h:
        d.warnings.append(f"{d.name}: card {key} is too short for its text")
    out.append("</g>")
    d.raw("".join(out), layer="cards")


def lcard(d: Diagram, key: str, x: float, y: float, w: float, h: float, icon, title: str, lines=(),
          tone: str = "blue", glow=(), icon_size: float = 28, title_size: float = 14, title_mono: bool = False,
          mono_lines=(), style: str = "card", appear=None, glow_tone=None, alt_glow=None) -> None:
    """A card with its icon at the left, like Diagram.card, but any line can use the monospace font (commands).

    icon : an icon key, or None for a text-only card.
    """
    d.card(key, x, y, w, h, "", (), tone=tone, style=style, glow=glow, glow_tone=glow_tone, alt_glow=alt_glow,
           appear=appear)
    out = [_vis(d, appear)]
    tx = x + 18
    if icon:
        out.append(f'<use href="#{d.symbol(icon)}" x="{fmt(x + 18)}" y="{fmt(y + (h - icon_size) / 2)}" '
                   f'width="{fmt(icon_size)}" height="{fmt(icon_size)}"/>')
        tx = x + 18 + icon_size + 14
    avail = x + w - 14 - tx
    block = title_size + len(lines) * 16
    ty = y + h / 2 - block / 2 + title_size * 0.8
    if block + 12 > h:
        d.warnings.append(f"{d.name}: card {key} is too short for its text")
    tink = TONES["red"][3] if style == "danger" else TONES[tone][3]
    if title_mono:
        if mono_width(title, title_size) > avail:
            d.warnings.append(f"{d.name}: '{title}' may overflow card {key}")
        out.append(f'<text x="{fmt(tx)}" y="{fmt(ty)}" font-family="{MONO}" font-size="{fmt(title_size)}" font-weight="700" '
                   f'fill="{tink}">{esc(title)}</text>')
    else:
        d.check(title, title_size, True, avail, f"card {key}")
        out.append(f'<text x="{fmt(tx)}" y="{fmt(ty)}" font-family="{FONT}" font-size="{fmt(title_size)}" font-weight="600" '
                   f'fill="{INK}">{esc(title)}</text>')
    for i, line in enumerate(lines):
        ly = ty + 17 + i * 16
        if i in mono_lines:
            if mono_width(line, 11.5) > avail:
                d.warnings.append(f"{d.name}: '{line}' may overflow card {key}")
            out.append(f'<text x="{fmt(tx)}" y="{fmt(ly)}" font-family="{MONO}" font-size="11.5" fill="{tink}" '
                       f'xml:space="preserve">{esc(line)}</text>')
        else:
            d.check(line, 12, False, avail, f"card {key}")
            out.append(f'<text x="{fmt(tx)}" y="{fmt(ly)}" font-family="{FONT}" font-size="12" fill="{INK2}">{esc(line)}</text>')
    out.append("</g>")
    d.raw("".join(out), layer="cards")


def code_lines(d: Diagram, x: float, y: float, lines, wins=None, size: float = 11, lh: float = 16, avail=None,
               color: str = INK) -> None:
    """Monospace lines (JSON or a policy), shown during `wins` (always when None). Spaces are kept."""
    head = f'<g opacity="0">{d.tl.anim("opacity", wins, 1, 0, fade=0.2)}' if wins else "<g>"
    out = [head]
    for i, line in enumerate(lines):
        if avail is not None and mono_width(line, size) > avail:
            d.warnings.append(f"{d.name}: code line '{line}' may overflow ({mono_width(line, size):.0f} > {avail:.0f})")
        out.append(f'<text x="{fmt(x)}" y="{fmt(y + i * lh)}" font-family="{MONO}" font-size="{fmt(size)}" fill="{color}" '
                   f'xml:space="preserve">{esc(line)}</text>')
    out.append("</g>")
    d.raw("".join(out), layer="top")


def chip(d: Diagram, x: float, y: float, text: str, wins=None, tone: str = "purple", mono: bool = True,
         anchor: str = "start", layer: str = "top") -> float:
    """A small pill label, shown during `wins` (always when None). Returns its width.

    anchor "end" puts the right edge of the pill at x.
    """
    strong, t1, t2, tink = TONES[tone]
    tw = mono_width(text, 10.5) if mono else len(text) * 5.9
    w = tw + 16
    if anchor == "end":
        x -= w
    fam = MONO if mono else FONT
    head = f'<g opacity="0">{d.tl.anim("opacity", wins, 1, 0, fade=0.2)}' if wins else "<g>"
    d.raw(f'{head}<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="18" rx="9" fill="{t1}" stroke="{t2}"/>'
          f'<text x="{fmt(x + w / 2)}" y="{fmt(y + 12.6)}" font-family="{fam}" font-size="10.5" font-weight="700" '
          f'fill="{tink}" text-anchor="middle">{esc(text)}</text></g>', layer=layer)
    return w


def done_mark(d: Diagram, cx: float, cy: float, wins, tone: str = "green", mark: str = "check", r: float = 9) -> None:
    """A filled circle with a check mark (or a cross) shown during `wins`."""
    col = TONES[tone][0]
    if mark == "check":
        glyph = (f'<path d="M{fmt(cx - r * 0.42)} {fmt(cy)} l{fmt(r * 0.3)} {fmt(r * 0.32)} l{fmt(r * 0.55)} {fmt(-r * 0.62)}" '
                 f'fill="none" stroke="#FFFFFF" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>')
    else:
        k = r * 0.36
        glyph = (f'<path d="M{fmt(cx - k)} {fmt(cy - k)} L{fmt(cx + k)} {fmt(cy + k)} M{fmt(cx + k)} {fmt(cy - k)} '
                 f'L{fmt(cx - k)} {fmt(cy + k)}" stroke="#FFFFFF" stroke-width="1.9" stroke-linecap="round"/>')
    d.raw(f'<g opacity="0">{d.tl.anim("opacity", wins, 1, 0, fade=0.12)}<circle cx="{fmt(cx)}" cy="{fmt(cy)}" '
          f'r="{fmt(r)}" fill="{col}" stroke="#FFFFFF" stroke-width="1.6"/>{glyph}</g>', layer="top")


def label(d: Diagram, x: float, y: float, text: str, size: float = 10.5, color: str = INK2, anchor: str = "start",
          weight: int = 600, mono: bool = False, wins=None, layer: str = "top") -> None:
    """Small free text for a connector or a panel, optionally shown only during `wins`."""
    fam = MONO if mono else FONT
    extra = ""
    body = esc(text)
    if wins:
        d.raw(f'<g opacity="0">{d.tl.anim("opacity", wins, 1, 0, fade=0.2)}<text x="{fmt(x)}" y="{fmt(y)}" font-family="{fam}" '
              f'font-size="{fmt(size)}" font-weight="{weight}" fill="{color}" text-anchor="{anchor}">{body}</text></g>', layer=layer)
    else:
        d.raw(f'<text x="{fmt(x)}" y="{fmt(y)}" font-family="{fam}" font-size="{fmt(size)}" font-weight="{weight}" '
              f'fill="{color}" text-anchor="{anchor}"{extra}>{body}</text>', layer=layer)


# =============================================================================
# Getting started: Figure B1, your lab environment and the path of one request
# =============================================================================
def architecture(icons: Path) -> Diagram:
    d = Diagram(
        "architecture",
        title="Your lab environment and the path of every request",
        subtitle=("Everything runs in your own Microsoft Entra tenant and Azure subscription. The numbers follow one "
                  "request from your prompt to the audited change."),
        tag="GETTING STARTED",
        aria=("Figure B1. One lab environment inside your own Microsoft Entra tenant and Azure subscription. You, the "
              "Senior Technician or the Tier 1 Technician, work on the lab VM in Microsoft Edge. Step 1: your prompt goes "
              "from the lab VM to the agent msp-support-agent in Microsoft Foundry, which runs gpt-5.1 and has its own "
              "Microsoft Entra Agent ID. Step 2: the agent grounds its answer on the Azure AI Search index "
              "servicedesk-knowledge, built from the Blob export servicedesk-export. Step 3: the agent calls a tool through "
              "Azure API Management, Developer tier, which validates your token and adds a correlation ID. Step 4: the MCP "
              "server on Azure Container Apps validates the call, write tools run only after you approve them, and its "
              "backend secret mcp-backend-key comes from Azure Key Vault, read at startup. Step 5: the MCP server calls "
              "Microsoft Dataverse on behalf of the signed-in user; Dataverse applies that user's role and audits the "
              "change, which shows in the Service Desk app. Microsoft Purview checks what the tools return. Step 6: "
              "Application Insights, Log Analytics and the Dataverse audit all record the same correlation ID."),
        icons_dir=icons, loop=10, fps=12)

    S = [(0.0, 1.6), (1.6, 3.2), (3.2, 4.8), (4.8, 6.4), (6.4, 8.0), (8.0, 9.6)]
    d.lane(36, 118, 1128, 494, "YOUR LAB ENVIRONMENT: YOUR OWN MICROSOFT ENTRA TENANT AND AZURE SUBSCRIPTION")

    # Row 1: the request path, left to right.
    xs = [52 + 230 * i for i in range(5)]
    Y1, H1, W = 140, 132, 176
    tcard(d, "vm", xs[0], Y1, W, H1, "vm", "You on the lab VM", ["Senior or Tier 1 Technician", "Foundry portal in Edge"],
          tone="blue", glow=[S[0]])
    tcard(d, "fdy", xs[1], Y1, W, H1, "foundry", "Microsoft Foundry", ["msp-support-agent", "gpt-5.1", "Own Entra Agent ID"],
          mono_lines=(0,), tone="blue", glow=[(0.9, 3.2)])
    tcard(d, "apim", xs[2], Y1, W, H1, "api-management", "API Management", ["Developer tier", "Validates your token"],
          tone="blue", glow=[S[2]])
    tcard(d, "mcp", xs[3], Y1, W, H1, "container-app", "MCP server", ["Azure Container Apps", "Validates every call",
          "Writes need approval"], tone="blue", glow=[S[3]])
    tcard(d, "dv", xs[4], Y1, W, H1, "dataverse", "Microsoft Dataverse", ["Service Desk data", "Applies the user's role",
          "Audits every change"], tone="blue", glow=[S[4]])

    # Row 2: what the path relies on.
    Y2, H2, W2 = 312, 88, 200
    rx = [52 + 224 * i for i in range(5)]
    d.card("blob", rx[0], Y2, W2, H2, "Blob Storage", ["servicedesk-export", "One JSON per record"], icon="storage-account",
           tone="teal", icon_size=26, title_size=13.5)
    d.card("srch", rx[1], Y2, W2, H2, "Azure AI Search", ["servicedesk-knowledge"], icon="ai-search", tone="teal",
           icon_size=26, title_size=13.5, glow=[S[1]])
    d.card("pur", rx[2], Y2, W2, H2, "Microsoft Purview", ["DLP and labels on", "what tools return"], icon="c-lock-shield",
           tone="purple", icon_size=26, title_size=13)
    d.card("kv", rx[3], Y2, W2, H2, "Azure Key Vault", ["mcp-backend-key", "Read at startup"], icon="key-vault",
           tone="purple", icon_size=26, title_size=13.5, glow=[S[3]])
    d.card("app", rx[4], Y2, W2, H2, "Service Desk app", ["Power Apps over", "Dataverse"], icon="power-apps",
           tone="teal", icon_size=26, title_size=13.5)

    # Static structure: the export feeds the index, Key Vault feeds the MCP server, Purview checks its output.
    bot = Y1 + H1
    d.wire(f"M{rx[0] + W2} {Y2 + 44} H{rx[1] - 1}", color="#7FB3B8", width=1.8, arrow=True)
    d.wire(f"M{xs[3] + 88} {Y2} V{bot + 1}", color="#9EA1DD", width=1.8, arrow=True)
    px = rx[2] + W2 / 2
    d.wire(f"M{xs[3] + 22} {bot} V{bot + 14} Q{xs[3] + 22} {bot + 20} {xs[3] + 16} {bot + 20} "
           f"H{fmt(px + 6)} Q{fmt(px)} {bot + 20} {fmt(px)} {bot + 26} V{Y2 - 1}", color="#9EA1DD", width=1.8, arrow=True)
    d.wire(f"M{xs[4] + 88} {bot} V{Y2}", color="#7FB3B8", width=1.8)

    # Active-step connectors: each flows, with its packet, only while its step plays.
    cy = Y1 + 66
    hops = [(0, S[0], 0.3), (1, S[2], 3.5), (2, S[3], 5.1), (3, S[4], 6.7)]
    for i, win, start in hops:
        pid = d.flow(f"h{i}", f"M{xs[i] + W} {cy} H{xs[i + 1]}", tone="blue", active=[win])
        d.packet_once(pid, start=start, travel=0.55, tone="blue")
    gx = xs[1] + 78
    pdown = d.flow("g1", f"M{gx} {bot} V{Y2}", tone="teal", active=[S[1]])
    d.packet_once(pdown, start=1.85, travel=0.45, tone="teal")
    pup = d.flow("g2", f"M{gx + 22} {Y2} V{bot}", tone="teal", active=[S[1]])
    d.packet_once(pup, start=2.55, travel=0.45, tone="teal")

    # Step badges at the top right of the card that performs each step.
    d.badge(xs[0] + W - 12, Y1 + 6, 1, tone="blue", active=[S[0]])
    d.badge(rx[1] + W2 - 12, Y2 + 6, 2, tone="teal", active=[S[1]])
    d.badge(xs[2] + W - 12, Y1 + 6, 3, tone="blue", active=[S[2]])
    d.badge(xs[3] + W - 12, Y1 + 6, 4, tone="blue", active=[S[3]])
    d.badge(xs[4] + W - 12, Y1 + 6, 5, tone="blue", active=[S[4]])

    # The correlation ID appears at each hop as the request reaches it, then in every log.
    for i, t in ((2, 4.1), (3, 5.7), (4, 7.3)):
        chip(d, xs[i] + W - 30, Y1 + 21, f"ID {CID}", [(t, 9.6)], anchor="end")

    # Row 3: the logs that keep the trail.
    d.lane(52, 476, 1096, 128, "STEP 6: EVERY HOP LOGGED WITH THE SAME CORRELATION ID", tone="purple", fill=False)
    logs = [("ai", 68, "app-insights", "Application Insights", ["msp-support-agent traces: request,", "tool call and result"]),
            ("la", 430, "log-analytics", "Log Analytics", ["API Management gateway log, MCP", "server log and Key Vault audit"]),
            ("da", 792, "dataverse", "Dataverse audit", ["Each change, made on behalf", "of the signed-in technician"])]
    for key, x, icon, title, lines in logs:
        d.card(key, x, 492, 340, 100, title, lines, icon=icon, tone="purple", icon_size=34, title_size=14, glow=[S[5]])
        chip(d, x + 340 - 12, 492 + 100 - 26, f"ID {CID}", [(8.3, 9.6)], anchor="end")
    d.badge(1130, 476, 6, tone="purple", active=[S[5]])

    toasts = ["Step 1: you send a prompt from the lab VM to msp-support-agent",
              "Step 2: the agent grounds its answer on servicedesk-knowledge",
              "Step 3: the tool call passes API Management, which adds a correlation ID",
              "Step 4: MCP server validation, your approval for writes, secret from Key Vault",
              "Step 5: the Dataverse call runs on behalf of the signed-in user, audited",
              "Step 6: every hop logs the same correlation ID"]
    for i, text in enumerate(toasts):
        d.toast(290, 418, 620, text, [S[i]], tone="purple" if i == 5 else ("teal" if i == 1 else "blue"), mark="info")

    d.caption = ("The agent never reaches Dataverse directly: every tool call passes the gateway and the MCP server, "
                 "acts on your behalf and carries one correlation ID.")
    return d


def step_strip(d: Diagram, steps, y: float = 110, h: float = 104, w: float = 208, gap: float = 22) -> list[float]:
    """Five step cards across the top, numbered, with a check mark when each step is done.

    steps : (key, icon, title, lines, tone, window) per step. Returns the x of each card.
    """
    xs = [36 + i * (w + gap) for i in range(len(steps))]
    for i, ((key, icon, title, lines, tone, win), x) in enumerate(zip(steps, xs)):
        tcard(d, key, x, y, w, h, icon, title, lines, tone=tone, glow=[win], icon_size=26)
        d.badge(x + w - 12, y + 6, i + 1, tone=tone, active=[win])
        done_mark(d, x + w - 20, y + h - 18, [(win[1], 9.9)])
    for i in range(len(steps) - 1):
        x0 = xs[i] + w
        tone, win = steps[i + 1][4], steps[i + 1][5]
        pid = d.flow(f"step{i}", f"M{fmt(x0)} {fmt(y + 52)} H{fmt(x0 + gap)}", tone=tone,
                     active=[(win[0] - 0.3, win[0] + 0.5)])
        d.packet_once(pid, start=win[0] - 0.25, travel=0.35, tone=tone)
    return xs


def bubble(d: Diagram, x: float, y: float, w: float, text: str, wins, who: str = "agent", h: float = 24) -> None:
    """A chat bubble that appears during `wins`: the user's on a blue tint, the agent's on white."""
    fill, stroke, ink = (TONES["blue"][1], TONES["blue"][2], TONES["blue"][3]) if who == "user" else ("#FFFFFF", "#D0D7DE", INK)
    d.check(text, 12, False, w - 20, "a chat bubble")
    d.raw(f'<g opacity="0">{d.tl.anim("opacity", wins, 1, 0, fade=0.2)}<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" '
          f'height="{fmt(h)}" rx="10" fill="{fill}" stroke="{stroke}"/><text x="{fmt(x + 10)}" y="{fmt(y + h / 2 + 4.2)}" '
          f'font-family="{FONT}" font-size="12" fill="{ink}">{esc(text)}</text></g>', layer="top")


# =============================================================================
# Exercise 1: build the knowledge index and ground the agent (Task 1.2)
# =============================================================================
def exercise_1_grounding(icons: Path) -> Diagram:
    d = Diagram(
        "exercise-1-grounding",
        title="Ground the agent in your own Service Desk data",
        subtitle=("Task 1.2 turns the exported Service Desk records into the index servicedesk-knowledge and adds it to "
                  "msp-support-agent, so every answer can cite its source."),
        tag="EXERCISE 1",
        aria=("Five steps of Task 1.2. Step 1, review the export: provisioning exported the Service Desk data from Microsoft "
              "Dataverse to the Blob container servicedesk-export, one JSON file per document. Step 2, create the index "
              "servicedesk-knowledge with the key id, the citation fields title, url and sourceId, the content field and a "
              "vector field. Step 3, load and count: the indexer servicedesk-export-indexer, with the skillset "
              "servicedesk-embed-skills and the embedding model text-embedding-3-small, loads the documents, and the count "
              "matches the export manifest. Step 4, add the index to msp-support-agent as a knowledge source. Step 5, ask "
              "and check citations: the answer cites KB0058 with a link to the record. A terminal types "
              "C:\\LabFiles\\tools\\New-KnowledgeIndex.ps1 with illustrative output. A note shows an ambiguous case: "
              "KB0031 and KB0058 describe the same symptom, and Woodgrove Bank's product versions select KB0058."),
        icons_dir=icons, loop=10, fps=12)

    S = [(0.0, 1.8), (1.8, 3.6), (3.6, 5.6), (5.6, 7.4), (7.4, 9.8)]
    steps = [("st1", "c-search", "Review the export", ["One JSON per document", "in servicedesk-export"], "teal", S[0]),
             ("st2", "c-settings", "Create the index", ["Key id and the citation", "fields title, url, sourceId"], "blue", S[1]),
             ("st3", "c-arrow-sync", "Load and count", ["The indexer embeds content;", "count matches the manifest"], "blue", S[2]),
             ("st4", "c-bot", "Add as knowledge source", ["servicedesk-knowledge on", "msp-support-agent"], "purple", S[3]),
             ("st5", "c-chat", "Ask and check citations", ["Each answer links to", "the record it came from"], "green", S[4])]
    step_strip(d, steps, h=110)

    # The script that creates and loads the index (steps 2 and 3). Row 0 holds a comment that is always visible,
    # so the first frame (the still image in viewers without animation) explains the terminal.
    d.terminal(36, 262, 520, 350, "PowerShell 7 on the lab VM", [
        ("", "out", 0.0, 0),
        ("C:\\LabFiles\\tools\\New-KnowledgeIndex.ps1", "cmd", 1.9, 0.9),
        ("Index servicedesk-knowledge created", "ok", 3.0, 0),
        ("  Key id; citation fields title, url, sourceId", "out", 3.15, 0),
        ("  contentVector: text-embedding-3-small, 1536", "out", 3.3, 0),
        ("Data source servicedesk-export-ds", "out", 3.8, 0),
        ("Skillset servicedesk-embed-skills", "out", 4.0, 0),
        ("Indexer servicedesk-export-indexer: running", "out", 4.3, 0),
        ("Indexer servicedesk-export-indexer: success", "ok", 5.0, 0),
        ("Documents match the export manifest", "ok", 5.35, 0),
        ("Next: add the index to msp-support-agent", "warn", 5.7, 0),
    ], note="Illustrative output")
    label(d, 52, 314, "# Steps 2 and 3: create, load and count the index", size=12, mono=True, weight=400,
          color="#7C8BA1")

    # From the data to a cited answer.
    d.lane(580, 262, 584, 350, "FROM SERVICE DESK DATA TO A CITED ANSWER", tone="teal")
    d.card("dv", 596, 276, 168, 62, "Dataverse", ["Service Desk data"], icon="dataverse", tone="teal", icon_size=26,
           title_size=13.5, glow=[(0.0, 0.9)])
    d.card("blob", 800, 276, 348, 62, "servicedesk-export", ["Blob container: one JSON file per document,",
           "exported by provisioning"], icon="storage-account", tone="teal", icon_size=28, title_size=13.5, title_mono=True,
           glow=[(0.6, 1.8)])
    p = d.flow("exp", "M764 307 H800", tone="teal", active=[(0.2, 1.2)])
    d.packet_once(p, start=0.3, travel=0.6, tone="teal")

    d.card("idx", 596, 382, 552, 64, "servicedesk-knowledge", ["Azure AI Search index: key id; title, url and sourceId",
           "for citations; content and a 1536-dimension contentVector"], icon="ai-search", tone="blue", icon_size=30,
           title_size=13.5, title_mono=True, glow=[(2.9, 3.6), (5.0, 5.8)])
    p = d.flow("load", "M974 338 V382", tone="blue", active=[S[2]])
    for k in range(3):
        d.packet_once(p, start=3.9 + k * 0.45, travel=0.4, tone="blue")
    label(d, 960, 355, "servicedesk-export-indexer", size=10.5, mono=True, anchor="end", color=TONES["blue"][3])
    label(d, 960, 370, "embeds content with text-embedding-3-small", size=10.5, anchor="end")
    chip(d, 1136, 392, "Count matches the manifest", [(5.35, 9.8)], tone="green", mono=False, anchor="end")

    d.card("agent", 596, 470, 552, 98, "msp-support-agent", [], icon="foundry-agents", tone="purple", icon_size=26,
           title_size=13.5, title_mono=True, valign="top", glow=[(5.9, 7.4)])
    p = d.flow("ks", "M872 446 V470", tone="purple", active=[S[3]])
    d.packet_once(p, start=5.9, travel=0.4, tone="purple")
    label(d, 884, 462, "knowledge source", size=10.5)
    chip(d, 1136, 478, "Microsoft Foundry agent", None, tone="purple", mono=False, anchor="end", layer="cards")
    # Until step 5 plays, the empty chat says what will happen there.
    d.raw(f'<g>{d.tl.anim("opacity", [(7.3, 9.9)], 0, 1, fade=0.2)}<text x="872" y="540" font-family="{FONT}" '
          f'font-size="12" font-style="italic" fill="{INK2}" text-anchor="middle">Step 5: ask in the agent playground '
          f'and check the citation</text></g>', layer="top")
    bubble(d, 760, 504, 376, "Remote Access drops every hour at Woodgrove Bank. Fix?", [(7.5, 9.8)], who="user")
    bubble(d, 612, 536, 400, "Apply KB0058 on the Secure Gateway, not KB0031.", [(8.1, 9.8)])
    chip(d, 1020, 539, "KB0058", [(8.5, 9.8)], tone="green")
    label(d, 1086, 552, "title, url", size=10.5, wins=[(8.5, 9.8)], color=TONES["green"][3])
    d.toast(596, 578, 552, "Ambiguous case: Woodgrove Bank's product versions select KB0058, not KB0031",
            [(8.7, 9.8)], tone="amber", mark="info")

    d.caption = ("Every answer cites the record it came from: title, url and sourceId travel from the export through the "
                 "index to the citation.")
    return d


# =============================================================================
# Exercise 2: ticket and incident intelligence (facts from the seed manifest's scenarios)
# =============================================================================
def exercise_2_ticket_intelligence(icons: Path) -> Diagram:
    d = Diagram(
        "exercise-2-ticket-intelligence",
        title="Triage a new incident from history, and catch SLA risk early",
        subtitle=("For TCK-10561 the agent separates true matches from decoys and recommends a triage that cites its "
                  "pattern. It also summarizes Woodgrove Bank's open tickets and ranks SLA risk."),
        tag="EXERCISE 2",
        aria=("Task 2.1: the new incident TCK-10561 at A. Datum Corporation, New and unclassified: no new recovery points "
              "since Saturday, the cloud storage allowance used up after a 2019 to 2024 drawing archive was copied. True "
              "matches: KB0023, RBA-2201 cloud vault storage quota exceeded, with a history of 10 tickets, all P3 Medium; "
              "and the open ticket TCK-10521 at Trey Research with the same quota error. Decoys: KB0012 and KB0013, a "
              "failed job for Platinum and Gold or Silver and Bronze customers; KB0033, slow backups after vault "
              "encryption; KB0036, large .pst files in backups; KB0039, a device offline; KB0007, the RBA-1043 snapshot "
              "timeout; and TCK-10532, an A. Datum device that is offline. Task 2.2: Woodgrove Bank has 6 open tickets, "
              "the most of any customer, the next has 3; three are the same recurring issue, Remote Access dropping "
              "every hour, KB0058: TCK-10548, TCK-10553 and TCK-10518; the others are TCK-10531, TCK-10543 and TCK-10513. "
              "Task 2.3: the recommendation for TCK-10561 is category Backup and Recovery, subcategory Storage quota, "
              "priority P3 Medium with a 32 business hour target, technician Priya Raman, TECH-01, citing the pattern that "
              "all 10 KB0023 tickets were P3 Medium and handled by Priya Raman. Task 2.4: SLA risk in business hours, "
              "Monday to Friday 08:00 to 18:00 UTC: breached TCK-10501 Tailspin Toys 6.0 hours over and TCK-10512 "
              "Northwind Traders 1.5 hours over; near breach TCK-10540 Contoso Pharmaceuticals 0.5 hours left, TCK-10524 "
              "Humongous Insurance 1.0 hour left and TCK-10504 Bellows College 2.0 hours left; every other open ticket "
              "has 6.0 hours or more."),
        icons_dir=icons, loop=10, fps=12)

    P1, P2, P3, P4 = (0.0, 2.6), (2.6, 5.0), (5.0, 7.5), (7.5, 9.9)
    green, red, amber, blue = (TONES[t] for t in ("green", "red", "amber", "blue"))

    # Task 2.1: the new incident, its true matches and the decoys.
    lcard(d, "inc", 36, 112, 552, 64, "c-mail", "TCK-10561: A. Datum Corporation, new and unclassified",
          ["No new recovery points since Saturday; the cloud storage", "allowance is used up after a 2019 to 2024 archive copy"],
          tone="blue", icon_size=30, title_size=14, glow=[(0.0, 0.9)])
    d.lane(36, 236, 552, 186, "TASK 2.1: TRUE MATCHES AND DECOYS", tone="teal")
    lcard(d, "kb23", 52, 250, 248, 78, "c-lightbulb-checkmark", "KB0023", ["RBA-2201: cloud vault quota",
          "History: 10 tickets, all P3"], title_mono=True, title_size=13, tone="green", icon_size=26, glow=[(0.8, 1.7)])
    lcard(d, "t521", 52, 336, 248, 78, "c-task-list-square", "TCK-10521", ["Trey Research, open:",
          "the same RBA-2201 quota"], title_mono=True, title_size=13, tone="green", icon_size=26, glow=[(1.2, 2.1)])
    for y, t in ((262, 1.0), (348, 1.4)):
        done_mark(d, 288, y, [(t, 9.9)], tone="green", r=8)
    d.card("decoys", 316, 250, 256, 164, "", (), tone="red", style="card")
    label(d, 332, 270, "DECOYS: SIMILAR WORDS, OTHER CAUSE", size=10, mono=True, weight=700, color=red[0])
    decoys = [("KB0012", "failed job, Platinum and Gold"), ("KB0013", "failed job, Silver and Bronze"),
              ("KB0033", "slow after vault encryption"), ("KB0036", "large .pst files in backups"),
              ("KB0039", "device offline, vault fine"), ("KB0007", "RBA-1043 snapshot timeout"),
              ("TCK-10532", "A. Datum device offline")]
    for i, (code, why) in enumerate(decoys):
        ry = 292 + i * 17
        label(d, 352, ry, code, size=10.5, mono=True, weight=700, color=INK, layer="cards")
        label(d, 424, ry, why, size=11, weight=400, color=INK2, layer="cards")
        done_mark(d, 340, ry - 4, [(1.0 + i * 0.18, 9.9)], tone="red", mark="cross", r=6)

    # Task 2.3: the recommendation and the pattern it cites.
    d.lane(36, 456, 552, 156, "TASK 2.3: RECOMMENDATION FOR TCK-10561", tone="green")
    d.card("rec", 52, 472, 520, 124, "", (), tone="green", style="card", glow=[P3])
    fields = [(68, 492, "CATEGORY", "Backup and Recovery", 5.2), (318, 492, "SUBCATEGORY", "Storage quota", 5.45),
              (68, 528, "PRIORITY", "P3 Medium, 32 h target", 5.7), (318, 528, "TECHNICIAN", "Priya Raman, TECH-01", 5.95)]
    for fx, fy, name, value, t in fields:
        label(d, fx, fy - 2, name, size=9.5, mono=True, weight=700, color=TONES["slate"][0], layer="cards")
        label(d, fx, fy + 14, value, size=13, weight=700, color=INK, layer="cards")
        halo(d, fx - 6, fy - 14, 236, 34, [(t, t + 0.8)], "green", rx=6)
    d.raw(f'<rect x="64" y="558" width="496" height="28" rx="8" fill="{green[1]}" stroke="{green[2]}"/>', layer="cards")
    label(d, 76, 576, "Pattern cited: all 10 KB0023 tickets were P3 Medium, handled by Priya Raman",
          size=11.5, weight=600, color=green[3], layer="cards")
    halo(d, 64, 558, 496, 28, [(6.3, 7.5)], "green", rx=8)

    # Task 2.2: Woodgrove Bank's open tickets, with the recurring issue.
    d.lane(612, 122, 552, 266, "TASK 2.2: WOODGROVE BANK (CUST-007), 6 OPEN TICKETS", tone="blue")
    label(d, 628, 148, "The most open tickets of any customer; the next has 3. History: 35 resolved or closed.",
          size=11, weight=400, layer="cards")
    wg = [("TCK-10548", "VPN drops every hour for branch managers", "P2", True),
          ("TCK-10553", "Mortgage team kicked off VPN hourly", "P2", True),
          ("TCK-10518", "Remote Access calls drop during long client calls", "P3", True),
          ("TCK-10531", "Third floor printer offline after network change", "P3", False),
          ("TCK-10543", "Laptop very slow since this week's agent update", "P3", False),
          ("TCK-10513", "Shared mailbox access for the compliance team", "P4", False)]
    for i, (tck, title, pri, rec) in enumerate(wg):
        ry = 162 + i * 29
        d.raw(f'<rect x="628" y="{ry}" width="520" height="24" rx="6" fill="#FFFFFF" stroke="{LINE_SOFT}"/>', layer="cards")
        if rec:
            d.raw(f'<rect x="628" y="{ry}" width="520" height="24" rx="6" fill="{amber[1]}" stroke="{amber[2]}" opacity="0">'
                  f'{d.tl.anim("opacity", [(3.0 + i * 0.25, 9.9)], 1, 0)}</rect>', layer="cards")
        label(d, 638, ry + 16, tck, size=10.5, mono=True, weight=700, color=blue[3], layer="cards")
        label(d, 712, ry + 16, title, size=11.5, weight=400, color=INK, layer="cards")
        chip(d, 1140, ry + 3, pri, None, tone="red" if pri == "P2" else ("amber" if pri == "P3" else "slate"),
             anchor="end", layer="cards")
    rw = chip(d, 628, 342, "Recurring: Remote Access drops hourly on 3 tickets, KB0058", None, tone="amber", mono=False,
              layer="cards")
    halo(d, 628, 342, rw, 18, [(3.8, 5.0)], "amber", rx=9)
    d.raw(f'<rect x="618" y="156" width="540" height="94" rx="10" fill="none" stroke="{blue[0]}" stroke-width="2.4" opacity="0">'
          f'{d.tl.anim("opacity", [P2], 1, 0)}</rect>', layer="top")

    # Task 2.4: SLA risk in business hours (Monday to Friday, 08:00 to 18:00 UTC).
    d.lane(612, 420, 552, 192, "TASK 2.4: SLA RISK IN BUSINESS HOURS", tone="red")
    zx, ppu = 972, 15
    label(d, zx - 8, 446, "BREACHED", size=9.5, mono=True, weight=700, color=red[0], anchor="end", layer="cards")
    label(d, zx + 8, 446, "AT RISK", size=9.5, mono=True, weight=700, color=amber[0], layer="cards")
    d.raw(f'<line x1="{zx}" y1="452" x2="{zx}" y2="582" stroke="#8C959F" stroke-width="1.4"/>', layer="cards")
    sla = [("TCK-10501", "Tailspin Toys", -6.0), ("TCK-10512", "Northwind Traders", -1.5),
           ("TCK-10540", "Contoso Pharmaceuticals", 0.5), ("TCK-10524", "Humongous Insurance", 1.0),
           ("TCK-10504", "Bellows College", 2.0)]
    for i, (tck, cust, hrs) in enumerate(sla):
        ry = 458 + i * 25
        tone = "red" if hrs < 0 else "amber"
        col = TONES[tone][0]
        bw = abs(hrs) * ppu
        bx = zx - bw if hrs < 0 else zx
        label(d, 628, ry + 13, tck, size=10.5, mono=True, weight=700, color=INK, layer="cards")
        label(d, 700, ry + 13, cust, size=11, weight=400, color=INK2, layer="cards")
        d.raw(f'<rect x="{fmt(bx)}" y="{ry + 2}" width="{fmt(bw)}" height="15" rx="3" fill="{col}"/>', layer="cards")
        text = f"{abs(hrs):.1f} h over" if hrs < 0 else f"{hrs:.1f} h left"
        label(d, 1072, ry + 13, text, size=11, weight=700, color=col, layer="cards")
    halo(d, 622, 456, 530, 46, [(7.7, 9.9)], "red", rx=6)
    halo(d, 622, 506, 530, 71, [(8.4, 9.9)], "amber", rx=6)
    label(d, 628, 598, "Every other open ticket has 6.0 or more business hours left.", size=11, weight=400,
          color=INK2, layer="cards")

    # Phase cues: one short note per task, at the same place.
    for text, win, tone in (("Task 2.1: KB0023 and TCK-10521 match; the decoys share words, not the cause", P1, "teal"),
                            ("Task 2.2: Woodgrove Bank's Remote Access drops are one recurring issue", P2, "blue"),
                            ("Task 2.3: the triage cites the KB0023 pattern, not a guess", P3, "green"),
                            ("Task 2.4: act first on the two breached tickets, then the three at risk", P4, "red")):
        d.toast(36, 184, 552, text, [win], tone=tone, mark="info")

    d.caption = ("Every answer cites the records it rests on, and SLA hours count only business time: Monday to Friday, "
                 "08:00 to 18:00 UTC.")
    return d


# =============================================================================
# Exercise 3: the MCP read path, its failure path and the redeploy loop
# =============================================================================
def exercise_3_mcp_read_path(icons: Path) -> Diagram:
    d = Diagram(
        "exercise-3-mcp-read-path",
        title="A read tool call: checked at every hop, structured when it fails",
        subtitle=("msp-support-agent calls get_ticket on the servicedesk-read connection. Reads need no approval, and "
                  "every result carries its request's correlation ID."),
        tag="EXERCISE 3",
        aria=("msp-support-agent calls the read tool get_ticket on the servicedesk-read connection, without approval. "
              "API Management validates the technician's token and adds the correlation ID. The MCP server's read "
              "endpoint, /read/mcp on Azure Container Apps, checks the input against the tool's input schema and queries "
              "the Dataverse Web API on behalf of the signed-in technician. A structured result returns to the agent "
              "with ok true and the correlation_id. Failure path: a call with no ticket_number is rejected by the input "
              "schema with INVALID_ARGUMENT before anything reaches Dataverse, and a call for TCK-99999 returns "
              "TICKET_NOT_FOUND. Both errors are structured, with a code, a message and the correlation_id, and no stack "
              "trace. At the bottom, the redeploy loop of Task 3.4: edit the source in Visual Studio Code, build the "
              "image mcp-server:3.0.1 with az acr build, the Container App ca-mcp-123456 starts a new revision that "
              "reports 3.0.1 on /health, and if needed az containerapp revision copy rolls back to the previous revision."),
        icons_dir=icons, loop=10, fps=12)

    cids = ["0b6f3c9e-6d2a-4f55-9a43-2d7c1e8b5a10", "5d1a7f20-3b8e-4c19-8f6d-0a2e9b7c4d31",
            "9c3e44b1-7a05-4e2d-b6f8-1d4c8e2a9f07"]
    # Three calls play in turn: a good call (0 to 4.4 s), a call with no ticket_number (4.5 to 6.8 s) and a call
    # for a ticket that does not exist (6.9 to 9.9 s).
    xs = [36, 332, 628, 924]
    Y, H, W = 126, 96, 240
    lcard(d, "agent", xs[0], Y, W, H, "c-bot", "msp-support-agent", ["Calls get_ticket on the", "servicedesk-read connection",
          "Reads need no approval"], title_mono=True, title_size=13.5, tone="blue", icon_size=30,
          glow=[(0.0, 0.8), (3.9, 4.6)], glow_tone="blue")
    lcard(d, "apim", xs[1], Y, W, H, "api-management", "API Management", ["Validates the technician's",
          "token, adds x-correlation-id"], tone="blue", icon_size=30, glow=[(0.7, 1.6), (4.8, 5.3), (7.1, 7.6)])
    lcard(d, "mcp", xs[2], Y, W, H, "container-app", "MCP server /read/mcp", ["Azure Container Apps",
          "Checks input against the", "tool's input schema"], tone="blue", icon_size=30,
          glow=[(1.5, 2.3)], alt_glow=([(5.2, 6.0)], "red"))
    lcard(d, "dv", xs[3], Y, W, H, "dataverse", "Dataverse Web API", ["Queries the ticket on behalf",
          "of the signed-in technician"], tone="blue", icon_size=30, glow=[(2.3, 3.0)], alt_glow=([(7.8, 8.4)], "red"))

    # Requests go right along the upper line; results come back along the lower line.
    rq, rs = Y + 36, Y + 66
    reqs = [(0, [(0.2, 0.9), (4.5, 5.1), (6.9, 7.4)], [0.3, 4.6, 7.0]),
            (1, [(0.9, 1.7), (5.0, 5.5), (7.3, 7.8)], [1.1, 5.05, 7.35]),
            (2, [(1.9, 2.6), (7.7, 8.2)], [2.0, 7.75])]
    for i, active, starts in reqs:
        pid = d.flow(f"rq{i}", f"M{xs[i] + W} {rq} H{xs[i + 1]}", tone="blue", active=active)
        for s in starts:
            d.packet_once(pid, start=s, travel=0.45, tone="blue")
    for i, (win, s) in enumerate([((3.6, 4.2), 3.7), ((3.2, 3.8), 3.3), ((2.8, 3.4), 2.85)]):
        pid = d.flow(f"rs{i}", f"M{xs[i + 1]} {rs} H{xs[i] + W}", tone="green", active=[win])
        d.packet_once(pid, start=s, travel=0.4, tone="green")
    label(d, (xs[0] + W + xs[1]) / 2, rq - 9, "request", anchor="middle", size=10)
    label(d, (xs[0] + W + xs[1]) / 2, rs + 17, "result", anchor="middle", size=10, color=TONES["green"][3])
    for (t0, t1), cid in zip([(0.8, 4.5), (4.9, 6.9), (7.2, 9.9)], cids):
        chip(d, xs[1] + W - 12, Y + H + 6, f"ID {cid[:8]}", [(t0, t1)], anchor="end")

    # What the agent receives: the result, or a structured error.
    PY, PH = 262, 112
    d.wire(f"M{xs[0] + 120} {Y + H} V{PY}", color="#9AA7B4", width=1.6, dash="3 4")
    d.card("got", 36, PY, 536, PH, "", (), tone="slate", glow=[(4.1, 4.9)], glow_tone="green",
           alt_glow=([(6.1, 6.9), (8.9, 9.7)], "red"))
    label(d, 54, PY + 22, "WHAT THE AGENT RECEIVES", size=10.5, mono=True, weight=700, color=TONES["slate"][0])
    chip(d, 556, PY + 9, "No stack trace", None, tone="red", mono=False, anchor="end", layer="cards")
    ok_wins, bad1, bad2 = [(9.9, 15.6)], [(5.6, 8.4)], [(8.4, 9.9)]
    code_lines(d, 54, PY + 46, ['{"ok": true,',
                                ' "ticket": { number, status, customer, SLA },',
                                f' "correlation_id": "{cids[0]}"}}'], ok_wins, avail=500)
    code_lines(d, 54, PY + 46, ['{"ok": false, "error": {"code": "INVALID_ARGUMENT",',
                                ' "message": "\'ticket_number\' is not valid: Field required."},',
                                f' "correlation_id": "{cids[1]}"}}'], bad1, avail=500, color=TONES["red"][3])
    code_lines(d, 54, PY + 46, ['{"ok": false, "error": {"code": "TICKET_NOT_FOUND",',
                                ' "message": "No ticket \'TCK-99999\' exists in the Service Desk."},',
                                f' "correlation_id": "{cids[2]}"}}'], bad2, avail=500, color=TONES["red"][3])

    # The failure branches: a bad argument stops at the schema; an unknown ticket comes back from Dataverse.
    lcard(d, "inv", xs[2], 272, W, 92, None, "INVALID_ARGUMENT", ["get_ticket with no ticket_number:",
          "rejected by the input schema,", "nothing reaches Dataverse"], title_mono=True, title_size=13, style="danger",
          tone="red", glow=[(5.3, 6.3)])
    lcard(d, "tnf", xs[3], 272, W, 92, None, "TICKET_NOT_FOUND", ["get_ticket for TCK-99999:",
          "Dataverse has no such ticket,", "returned as a structured error"], title_mono=True, title_size=13, style="danger",
          tone="red", glow=[(8.1, 9.1)])
    p = d.flow("e1", f"M{xs[2] + 120} {Y + H} V272", tone="red", active=[(5.3, 5.9)])
    d.packet_once(p, start=5.35, travel=0.4, tone="red")
    p = d.flow("e1b", f"M{xs[2]} 318 H572", tone="red", active=[(5.7, 6.3)])
    d.packet_once(p, start=5.75, travel=0.4, tone="red")
    p = d.flow("e2", f"M{xs[3] + 120} {Y + H} V272", tone="red", active=[(8.0, 8.6)])
    d.packet_once(p, start=8.05, travel=0.4, tone="red")
    p = d.flow("e2b", f"M{xs[3] + 120} 364 V384 Q{xs[3] + 120} 392 {xs[3] + 112} 392 H528 Q520 392 520 384 V{PY + PH}",
               tone="red", active=[(8.3, 9.2)])
    d.packet_once(p, start=8.35, travel=0.7, tone="red")

    # The redeploy loop of Task 3.4.
    d.lane(36, 434, 1128, 178, "REDEPLOY YOUR COPY OF THE MCP SERVER (TASK 3.4)", tone="teal")
    loop = [("l1", 52, 220, "c-code", "Edit the source", ["Visual Studio Code,", "C:\\LabFiles\\mcp-server"], (), False,
             (0.0, 2.5)),
            ("l2", 302, 236, "container-registry", "az acr build", ["Image mcp-server:3.0.1 in", "Azure Container Registry"],
             (), True, (2.5, 5.0)),
            ("l3", 568, 250, "container-app", "New revision", ["ca-mcp-123456 serves 3.0.1;", "/health reports the version"],
             (), False, (5.0, 7.5)),
            ("l4", 848, 300, "c-arrow-sync", "Roll back if needed", ["az containerapp revision copy",
             "from the previous revision"], (0,), False, (7.5, 9.9))]
    for key, x, w, icon, title, lines, mono, tmono, win in loop:
        lcard(d, key, x, 450, w, 84, icon, title, lines, tone="teal", icon_size=28, title_size=13.5, title_mono=tmono,
              mono_lines=mono, glow=[win], style="ghost" if key == "l4" else "card")
    for (k0, x0, w0, *_a), (k1, x1, *_b), t in zip(loop, loop[1:], (2.3, 4.8, 7.3)):
        p = d.flow(f"lp{k0}", f"M{x0 + w0} 492 H{x1}", tone="teal", active=[(t - 0.1, t + 0.6)])
        d.packet_once(p, start=t, travel=0.4, tone="teal")
    p = d.flow("back", "M998 534 V552 Q998 560 990 560 H170 Q162 560 162 552 V534", tone="teal",
               active=[(9.2, 9.95)])
    d.packet_once(p, start=9.25, travel=0.65, tone="teal")
    label(d, 580, 584, "Each change goes round the loop; a rollback starts a new revision from the previous one",
          anchor="middle", size=11, color=TONES["teal"][3])

    d.caption = ("A bad call never reaches the agent as a crash: it gets a code, a message and a correlation ID it can "
                 "act on, and nothing reaches Dataverse that the schema rejects.")
    return d


def halo(d: Diagram, x: float, y: float, w: float, h: float, wins, tone: str, rx: float = 9) -> None:
    """A colored ring around a small shape (a button, a table row) during `wins`."""
    col = TONES[tone][0]
    d.raw(f'<rect x="{fmt(x - 3)}" y="{fmt(y - 3)}" width="{fmt(w + 6)}" height="{fmt(h + 6)}" rx="{fmt(rx + 3)}" fill="none" '
          f'stroke="{col}" stroke-width="3" opacity="0">{d.tl.anim("opacity", wins, 0.9, 0)}</rect>', layer="top")


def placeholder(d: Diagram, x: float, y: float, text: str, hidden, anchor: str = "middle") -> None:
    """Gray italic text that explains an empty area and hides while `hidden` windows play."""
    d.raw(f'<g>{d.tl.anim("opacity", hidden, 0, 1, fade=0.2)}<text x="{fmt(x)}" y="{fmt(y)}" font-family="{FONT}" '
          f'font-size="12" font-style="italic" fill="{INK2}" text-anchor="{anchor}">{esc(text)}</text></g>', layer="top")


# =============================================================================
# Exercise 4: approval on every write, reject, duplicate, public reply or internal note
# =============================================================================
def exercise_4_approval_flow(icons: Path) -> Diagram:
    d = Diagram(
        "exercise-4-approval-flow",
        title="Every write waits for your approval and leaves a trail",
        subtitle=("msp-support-agent proposes a write on the servicedesk-write connection. You see the server, the tool "
                  "and the full arguments, and you decide."),
        tag="EXERCISE 4",
        aria=("msp-support-agent proposes a write on the servicedesk-write connection. The approval request names the MCP "
              "server servicedesk-write, the tool update_ticket_priority and the full arguments: ticket_number TCK-10544, "
              "priority 3 and a reason. Approve: the call goes through API Management, which adds the correlation ID, to "
              "the MCP server's write endpoint /write/mcp; the tool changes TCK-10544 to P3 Medium in Dataverse on behalf "
              "of the signed-in technician, adds an internal audit note, and the MCP server writes an Agent Action row with "
              "the outcome Succeeded. Reject: the tool is never called and nothing changes; in the lab you decline a "
              "status change on TCK-10544, which stays New, and the agent says the call was not approved. Duplicate: the "
              "same tool with the same arguments for the same user within 10 minutes returns the first result and makes no "
              "second change; its Agent Action row, with its own correlation ID, says Duplicate, first result returned. "
              "Side panel for TCK-10524: "
              "add_public_reply writes a note with the internal flag false, which the customer can read, and "
              "add_internal_note writes a note with the internal flag true, for technicians only."),
        icons_dir=icons, loop=10, fps=12)

    tcard(d, "agent", 36, 112, 214, 116, "c-bot", "msp-support-agent", ["Proposes a write on the",
          "servicedesk-write connection"], tone="blue", glow=[(0.0, 1.0), (7.2, 7.6)])

    # The approval request: server, tool and the full arguments, then your decision.
    AX, AY, AW, AH = 282, 112, 412, 196
    d.card("ask", AX, AY, AW, AH, "", (), tone="purple", glow=[(1.0, 2.5), (7.4, 7.9)])
    d.icon("c-checkmark-circle", AX + 18, AY + 14, 26)
    d.text(AX + 54, AY + 33, "Approval request", size=15, color=INK, weight=700)
    d.text(AX + AW - 16, AY + 33, "Task 4.1 example", size=10.5, color="#8C959F", anchor="end", extra=' font-style="italic"')
    rows = [("SERVER", ["servicedesk-write"], AY + 52, (1.0, 2.5)),
            ("TOOL", ["update_ticket_priority"], AY + 74, (1.3, 2.5)),
            ("ARGUMENTS", ['{"ticket_number": "TCK-10544",', ' "priority": 3,', ' "reason": "The technician asked for P3"}'],
             AY + 96, (1.6, 2.5))]
    for name, vals, ry, win in rows:
        hgt = 20 + (len(vals) - 1) * 16
        d.raw(f'<rect x="{AX + 10}" y="{ry}" width="{AW - 20}" height="{hgt}" rx="6" fill="{TONES["purple"][1]}" '
              f'opacity="0">{d.tl.anim("opacity", [win], 1, 0)}</rect>', layer="cards")
        label(d, AX + 18, ry + 14, name, size=10, mono=True, weight=700, color=TONES["purple"][0])
        code_lines(d, AX + 104, ry + 14, vals, size=11.5, avail=AW - 118, color=TONES["purple"][3])
    bx, by = AX + 18, AY + 158
    d.raw(f'<rect x="{bx}" y="{by}" width="100" height="28" rx="8" fill="{TONES["green"][0]}"/>'
          f'<text x="{bx + 50}" y="{by + 18.5}" font-family="{FONT}" font-size="12.5" font-weight="700" fill="#FFFFFF" '
          f'text-anchor="middle">Approve</text>'
          f'<rect x="{bx + 112}" y="{by}" width="92" height="28" rx="8" fill="#FFFFFF" stroke="{TONES["red"][0]}" stroke-width="1.6"/>'
          f'<text x="{bx + 158}" y="{by + 18.5}" font-family="{FONT}" font-size="12.5" font-weight="700" fill="{TONES["red"][0]}" '
          f'text-anchor="middle">Reject</text>', layer="cards")
    halo(d, bx, by, 100, 28, [(2.4, 3.1), (7.6, 8.1)], "green")
    halo(d, bx + 112, by, 92, 28, [(5.5, 6.1)], "red")
    label(d, bx + 216, by + 18, "Each call needs its own decision", size=10.5, color=INK2, weight=400)
    p = d.flow("prop", f"M250 170 H{AX}", tone="blue", active=[(0.2, 1.0), (7.2, 7.6)])
    d.packet_once(p, start=0.25, travel=0.5, tone="blue")
    d.packet_once(p, start=7.2, travel=0.35, tone="blue")

    # Approve: through the gateway to the write tool, the change, the audit note and the Agent Action row.
    tcard(d, "apim", 726, 112, 190, 116, "api-management", "API Management", ["Validates the token,",
          "adds the correlation ID"], tone="blue", glow=[(2.9, 3.6), (8.0, 8.5)])
    tcard(d, "mcp", 948, 112, 216, 116, "container-app", "MCP server /write/mcp", ["update_ticket_priority",
          "Checks for a duplicate"], mono_lines=(0,), tone="blue", glow=[(3.5, 4.3)], alt_glow=([(8.4, 9.0)], "amber"))
    p = d.flow("ok1", f"M{AX + AW} 170 H726", tone="green", active=[(2.5, 3.1), (7.7, 8.2)])
    d.packet_once(p, start=2.55, travel=0.45, tone="green")
    d.packet_once(p, start=7.75, travel=0.35, tone="green")
    p = d.flow("ok2", "M916 170 H948", tone="green", active=[(3.2, 3.8), (8.1, 8.6)])
    d.packet_once(p, start=3.25, travel=0.4, tone="green")
    d.packet_once(p, start=8.15, travel=0.35, tone="green")
    chip(d, 916 - 12, 112 + 20, f"ID {CID}", [(3.0, 9.9)], anchor="end")

    lcard(d, "chg", 948, 262, 216, 70, "dataverse", "TCK-10544 updated", ["Now P3 Medium, changed", "on behalf of the technician"],
          tone="green", icon_size=26, title_size=13.5, glow=[(4.2, 5.0)])
    lcard(d, "note", 948, 350, 216, 70, "c-document-text", "Audit note added", ["Internal note: what, why,",
          "for whom, correlation ID"], tone="green", icon_size=26, title_size=13.5, glow=[(4.6, 5.4)])
    p = d.flow("ok3", "M1056 228 V262", tone="green", active=[(3.9, 4.5)])
    d.packet_once(p, start=3.95, travel=0.35, tone="green")
    p = d.flow("ok4", "M1056 332 V350", tone="green", active=[(4.4, 4.9)])
    d.packet_once(p, start=4.45, travel=0.3, tone="green")
    p = d.flow("ok5", "M1056 420 V478", tone="green", active=[(4.8, 5.4)])
    d.packet_once(p, start=4.85, travel=0.4, tone="green")

    # Duplicate: the same tool, arguments and user within 10 minutes (a new correlation ID, matched on the call).
    lcard(d, "dup", 726, 262, 190, 158, "c-clock", "Same call again", ["Same tool, arguments", "and user in 10 min:",
          "first result returned,", "no second change"], tone="amber", icon_size=24, title_size=13.5, style="tint",
          glow=[(8.8, 9.8)])
    p = d.flow("dup1", "M964 228 V240 Q964 246 958 246 H827 Q821 246 821 252 V262", tone="amber", active=[(8.5, 9.1)])
    d.packet_once(p, start=8.55, travel=0.45, tone="amber")
    p = d.flow("dup2", "M900 420 V478", tone="amber", active=[(9.0, 9.5)])
    d.packet_once(p, start=9.05, travel=0.35, tone="amber")

    # Reject: the tool is never called.
    lcard(d, "rej", AX, 338, AW, 82, "c-shield-error", "Rejected: the tool is never called",
          ["In the lab you decline a status change on TCK-10544:", "it stays New, and the agent says it was not approved"],
          style="danger", tone="red", icon_size=28, title_size=14, glow=[(5.9, 7.1)])
    p = d.flow("no", f"M{bx + 158} {AY + AH} V338", tone="red", active=[(5.6, 6.2)])
    d.packet_once(p, start=5.65, travel=0.4, tone="red")

    # The Agent Action rows the MCP server writes.
    d.lane(726, 478, 438, 134, "AGENT ACTION ROWS", tone="purple")
    for x, head in ((744, "ID"), (814, "TOOL"), (978, "OUTCOME")):
        label(d, x, 504, head, size=10, mono=True, weight=700, color=TONES["slate"][0])
    trows = [(530, "Succeeded", "green", [(5.2, 9.95)], CID),
             (558, "Duplicate, first result returned", "amber", [(9.3, 9.95)], "5d1a7f20")]
    for ry, outcome, tone, win, row_id in trows:
        d.raw(f'<g opacity="0">{d.tl.anim("opacity", win, 1, 0, fade=0.2)}<rect x="738" y="{ry - 15}" width="414" height="22" '
              f'rx="6" fill="#FFFFFF" stroke="{LINE_SOFT}"/>'
              f'<text x="746" y="{ry}" font-family="{MONO}" font-size="10.5" fill="{TONES["purple"][3]}">{row_id}</text>'
              f'<text x="814" y="{ry}" font-family="{MONO}" font-size="10.5" fill="{INK}">update_ticket_priority</text>'
              f'<text x="978" y="{ry}" font-family="{FONT}" font-size="10.5" font-weight="700" fill="{TONES[tone][0]}">'
              f'{esc(outcome)}</text></g>', layer="top")
    placeholder(d, 945, 560, "A row appears for each call the MCP server runs", [(5.1, 9.95)])

    # Side panel: the internal flag decides who can read a note.
    d.lane(36, 470, 658, 142, "PUBLIC REPLY OR INTERNAL NOTE ON TCK-10524 (TASK 4.2)", tone="teal")
    lcard(d, "pub", 52, 488, 306, 108, "c-chat", "add_public_reply", ["Internal flag: false", "The customer can read it"],
          title_mono=True, title_size=13, tone="teal", icon_size=30)
    lcard(d, "int", 372, 488, 306, 108, "c-lock-closed", "add_internal_note", ["Internal flag: true",
          "Technicians only, never in", "a customer-facing reply"], title_mono=True, title_size=13, tone="purple",
          icon_size=30)

    d.caption = ("Nothing changes until you approve: a rejected call never reaches the MCP server, and a repeat returns the "
                 "first result instead of changing the ticket twice.")
    return d


def panel(d: Diagram, key: str, x: float, y: float, w: float, h: float, caption: str, lines=(), mono_lines=(),
          tone: str = "slate", glow=(), glow_tone=None, style: str = "tint", size: float = 12, lh: float = 17) -> None:
    """A detail panel under a card: a monospace caption and a few lines (any of them monospace)."""
    d.card(key, x, y, w, h, "", (), tone=tone, style=style, glow=glow, glow_tone=glow_tone)
    strong, _, _, tink = TONES[tone]
    if mono_width(caption, 10) * 1.1 > w - 28:
        d.warnings.append(f"{d.name}: panel caption '{caption}' may overflow")
    out = [f'<text x="{fmt(x + 16)}" y="{fmt(y + 22)}" font-family="{MONO}" font-size="10" font-weight="700" letter-spacing="0.8" '
           f'fill="{strong}">{esc(caption)}</text>']
    for i, line in enumerate(lines):
        ly = y + 44 + i * lh
        if i in mono_lines:
            if mono_width(line, size - 1) > w - 28:
                d.warnings.append(f"{d.name}: '{line}' may overflow panel {key}")
            out.append(f'<text x="{fmt(x + 16)}" y="{fmt(ly)}" font-family="{MONO}" font-size="{fmt(size - 1)}" fill="{tink}" '
                       f'xml:space="preserve">{esc(line)}</text>')
        else:
            d.check(line, size, False, w - 28, f"panel {key}")
            out.append(f'<text x="{fmt(x + 16)}" y="{fmt(ly)}" font-family="{FONT}" font-size="{fmt(size)}" fill="{INK2}">{esc(line)}</text>')
    if y + 44 + (len(lines) - 1) * lh + 8 > y + h:
        d.warnings.append(f"{d.name}: panel {key} is too short for its lines")
    d.raw("".join(out), layer="cards")


# =============================================================================
# Exercise 5: whose token, whose permissions
# =============================================================================
def exercise_5_identity_token_flow(icons: Path) -> Diagram:
    d = Diagram(
        "exercise-5-identity-token-flow",
        title="The agent acts with your permissions, never more",
        subtitle=("Your token reaches the gateway, your object ID reaches the MCP server, and Dataverse allows only what "
                  "both your role and the server's role allow."),
        tag="EXERCISE 5",
        aria=("The token chain, played twice. You sign in with Microsoft Entra ID as the Tier 1 Technician, then as the "
              "Senior Technician. msp-support-agent has its own Microsoft Entra Agent ID and no Dataverse permission. Its "
              "OAuth connection servicedesk-write obtains your token for the gateway: audience the gateway app, scope "
              "ServiceDesk.Access, object ID yours. API Management validates the token, adds x-correlation-id, forwards "
              "your object ID and adds the backend key from Azure Key Vault. The MCP server's managed identity "
              "id-mcp-123456 read that key at startup; it calls Microsoft Dataverse as its application user with "
              "CallerObjectId set to you, and Dataverse applies the intersection of your role and the application user's "
              "role. The request is update_ticket_priority on TCK-10543, from P3 Medium to P2 High. Tier 1 Technician: "
              "denied by Dataverse with PrivilegeDenied 0x80040220, nothing changed, logged as Denied by Dataverse. "
              "Senior Technician: allowed, TCK-10543 is now P2 High. Same agent, same MCP server."),
        icons_dir=icons, loop=10, fps=12)

    xs = [36 + 192 * i for i in range(6)]
    W, Y1, H1, Y2, H2 = 168, 112, 118, 262, 124
    runs = [0.0, 5.0]

    def wins(a: float, b: float):
        return [(o + a, o + b) for o in runs]

    tcard(d, "you", xs[0], Y1, W, H1, "entra-id", "You sign in", ["Microsoft Entra ID", "Tier 1 or Senior"],
          tone="blue", icon_size=26, glow=wins(0.0, 0.7))
    tcard(d, "agent", xs[1], Y1, W, H1, "c-bot", "msp-support-agent", ["Own Entra Agent ID", "No Dataverse rights"],
          tone="blue", icon_size=26, glow=wins(0.8, 1.4))
    tcard(d, "conn", xs[2], Y1, W, H1, "c-key", "OAuth connection", ["servicedesk-write", "Gets your token"],
          mono_lines=(0,), tone="purple", icon_size=26, glow=wins(1.4, 2.0))
    tcard(d, "apim", xs[3], Y1, W, H1, "api-management", "API Management", ["Validates your token,", "forwards who you are"],
          tone="blue", icon_size=26, glow=wins(2.1, 2.7))
    tcard(d, "mcp", xs[4], Y1, W, H1, "container-app", "MCP server", ["id-mcp-123456", "Calls as its app user"],
          mono_lines=(0,), tone="blue", icon_size=26, glow=wins(2.8, 3.4))
    tcard(d, "dv", xs[5], Y1, W, H1, "dataverse", "Microsoft Dataverse", ["Checks your role and", "the server's role"],
          tone="blue", icon_size=26, glow=[(8.4, 9.0)], alt_glow=([(3.4, 4.0)], "red"))
    cy = Y1 + 59
    for i, (a, b) in enumerate([(0.5, 1.0), (1.1, 1.6), (1.8, 2.3), (2.5, 3.0), (3.1, 3.6)]):
        pid = d.flow(f"t{i}", f"M{xs[i] + W} {cy} H{xs[i + 1]}", tone="purple" if i in (1, 2) else "blue",
                     active=wins(a, b))
        for o in runs:
            d.packet_once(pid, start=o + a + 0.05, travel=0.35, tone="purple" if i in (1, 2) else "blue")

    # What each hop holds, in the column under it.
    for i in (0, 1, 2, 3, 5):
        d.wire(f"M{xs[i] + W / 2} {Y1 + H1} V{Y2}", color="#B7C2CE", width=1.4, dash="3 4")
    d.card("signed", xs[0], Y2, W, H2, "", (), tone="slate", style="tint")
    label(d, xs[0] + 16, Y2 + 22, "SIGNED IN AS", size=10, mono=True, weight=700, color=TONES["slate"][0])
    for text, role1, role2, tone, w in (("Tier 1 Technician", "Service Desk Tier 1", "Technician: read only", "red",
                                         [(9.95, 14.95)]),
                                        ("Senior Technician", "Service Desk Senior", "Technician: read, write", "green",
                                         [(4.95, 9.95)])):
        d.raw(f'<g opacity="0">{d.tl.anim("opacity", w, 1, 0, fade=0.2)}'
              f'<text x="{xs[0] + 16}" y="{Y2 + 48}" font-family="{FONT}" font-size="13.5" font-weight="700" '
              f'fill="{TONES[tone][0]}">{esc(text)}</text>'
              f'<text x="{xs[0] + 16}" y="{Y2 + 72}" font-family="{FONT}" font-size="12" fill="{INK2}">Role: {esc(role1)}</text>'
              f'<text x="{xs[0] + 16}" y="{Y2 + 89}" font-family="{FONT}" font-size="12" fill="{INK2}">{esc(role2)}</text></g>',
              layer="top")
    panel(d, "aid", xs[1], Y2, W, H2, "AGENT IDENTITY", ["Microsoft Entra Agent ID", "No Dataverse permission",
          "Not in the token the", "gateway receives"])
    panel(d, "tok", xs[2], Y2, W, H2, "YOUR TOKEN", ["aud  gateway app", "scp  ServiceDesk.Access", "oid  your object ID"],
          mono_lines=(0, 1, 2), tone="purple", glow=wins(1.5, 2.2), size=11, lh=19)
    panel(d, "fwd", xs[3], Y2, W, H2, "GATEWAY ADDS", ["x-correlation-id", "Your object ID", "Backend key from",
          "Key Vault"], mono_lines=(0,), tone="blue", glow=wins(2.2, 2.9))
    lcard(d, "kv", xs[4], Y2, W, H2, None, "Azure Key Vault", ["mcp-backend-key", "Read at startup by", "id-mcp-123456",
          "and by the gateway"], mono_lines=(0, 2), tone="purple", title_size=13.5, glow=wins(2.9, 3.4))
    d.icon("key-vault", xs[4] + W - 40, Y2 + 12, 24)
    d.wire(f"M{xs[4] + W / 2} {Y2} V{Y1 + H1 + 1}", color="#9EA1DD", width=1.8, arrow=True)

    # Dataverse: the intersection of both roles decides.
    vx, vy = xs[5], Y2
    d.card("venn", vx, vy, W, H2, "", (), tone="slate", style="tint")
    label(d, vx + 16, vy + 22, "BOTH ROLES MUST ALLOW", size=10, mono=True, weight=700, color=TONES["slate"][0])
    c1, c2, cyv, r = vx + 62, vx + 106, vy + 66, 30
    hy = (r * r - ((c2 - c1) / 2) ** 2) ** 0.5
    mx = (c1 + c2) / 2
    lens = (f"M{fmt(mx)} {fmt(cyv - hy)} A{r} {r} 0 0 1 {fmt(mx)} {fmt(cyv + hy)} "
            f"A{r} {r} 0 0 1 {fmt(mx)} {fmt(cyv - hy)} Z")
    for tone, w in (("red", [(3.5, 4.95)]), ("green", [(8.5, 9.95)])):
        d.raw(f'<path d="{lens}" fill="{TONES[tone][0]}" opacity="0">{d.tl.anim("opacity", w, 0.85, 0)}</path>', layer="cards")
    d.raw(f'<circle cx="{fmt(c1)}" cy="{fmt(cyv)}" r="{r}" fill="none" stroke="{TONES["blue"][0]}" stroke-width="1.8"/>'
          f'<circle cx="{fmt(c2)}" cy="{fmt(cyv)}" r="{r}" fill="none" stroke="{TONES["purple"][0]}" stroke-width="1.8"/>',
          layer="cards")
    label(d, c1 - 12, cyv - 2, "Your", size=10, anchor="middle", color=TONES["blue"][3])
    label(d, c1 - 12, cyv + 10, "role", size=10, anchor="middle", color=TONES["blue"][3])
    label(d, c2 + 12, cyv - 2, "App", size=10, anchor="middle", color=TONES["purple"][3])
    label(d, c2 + 12, cyv + 10, "user", size=10, anchor="middle", color=TONES["purple"][3])
    d.raw(f'<g>{d.tl.anim("opacity", [(3.5, 4.95), (8.5, 9.95)], 0, 1, fade=0.2)}<text x="{fmt(vx + W / 2)}" y="{vy + 114}" '
          f'font-family="{FONT}" font-size="11" font-weight="700" fill="{INK2}" text-anchor="middle">Only what both allow</text></g>',
          layer="top")
    label(d, vx + W / 2, vy + 114, "No Write: denied", size=11, anchor="middle", weight=700, color=TONES["red"][0],
          wins=[(3.5, 4.95)])
    label(d, vx + W / 2, vy + 114, "Write allowed", size=11, anchor="middle", weight=700, color=TONES["green"][0],
          wins=[(8.5, 9.95)])

    # The same call, two technicians.
    d.lane(36, 428, 1128, 168, "ONE CALL ON TCK-10543, TWO TECHNICIANS", tone="slate")
    lcard(d, "deny", 52, 446, 540, 132, "c-shield-error", "Tier 1 Technician: denied by Dataverse",
          ["Asks to raise TCK-10543 from P3 Medium to P2 High", "PrivilegeDenied 0x80040220: no Write privilege on tickets",
           "Nothing changed; logged as Denied by Dataverse"], style="danger", tone="red", icon_size=30,
          glow=[(3.8, 4.95)])
    lcard(d, "allow", 608, 446, 540, 132, "c-checkmark-circle", "Senior Technician: allowed",
          ["The same request through the same agent and server", "TCK-10543 is now P2 High, on the technician's behalf",
           "Dataverse audits the change"], style="tint", tone="green", icon_size=30,
          glow=[(8.8, 9.95)])
    p = d.flow("o1", f"M{xs[5] + 40} {Y2 + H2} V{Y2 + H2 + 10} Q{xs[5] + 40} {Y2 + H2 + 16} {xs[5] + 34} {Y2 + H2 + 16} "
               f"H446 Q440 {Y2 + H2 + 16} 440 {Y2 + H2 + 22} V446", tone="red", active=[(3.7, 4.3)])
    d.packet_once(p, start=3.75, travel=0.5, tone="red")
    p = d.flow("o2", f"M{xs[5] + 120} {Y2 + H2} V446", tone="green", active=[(8.7, 9.2)])
    d.packet_once(p, start=8.75, travel=0.35, tone="green")

    d.caption = ("The same agent and the same MCP server give the two technicians different results, because Dataverse "
                 "checks the person behind every call.")
    return d


# =============================================================================
# Exercise 6: what the agent cannot return, and the trail of one action
# =============================================================================
def exercise_6_protection_and_trail(icons: Path) -> Diagram:
    d = Diagram(
        "exercise-6-protection-and-trail",
        title="What the agent cannot see, and the trail that proves it",
        subtitle=("Column security, a Microsoft Purview DLP policy and a label check withhold sensitive data. One "
                  "correlation ID ties every hop of an action together."),
        tag="EXERCISE 6",
        aria=("Left, what the agent cannot return. Contact phone and email: Dataverse column security, the profile "
              "Contact Phone Protection, secures the phone columns from the start and Task 6.1 adds the email column, so "
              "get_customer_contacts returns no phone or email. A card number in an internal note of TCK-10521: the "
              "Microsoft Purview DLP policy for Credit Card Number blocks it and the result says withheld_by_policy. The "
              "document Woodgrove-Bank-Secure-Gateway-configuration.docx is labeled Relecloud Confidential: the MCP server's label "
              "check refuses it with CONTENT_BLOCKED_BY_LABEL. Right, the trail of one action in Task 6.3: "
              "C:\\LabFiles\\tools\\Get-ActionTrail.ps1 takes the correlation ID 0b6f3c9e-6d2a-4f55-9a43-2d7c1e8b5a10 and "
              "finds it in Application Insights (the agent's request and tool decision), the API Management gateway log, "
              "the MCP server log (authorization result and backend call), the Dataverse audit record of TCK-10544 "
              "changing from P4 Low to P3 Medium, the Agent Action row, and the outcome returned to the agent."),
        icons_dir=icons, loop=10, fps=12)

    # Left: three protections, each enforced before data reaches the agent.
    d.lane(36, 120, 548, 492, "WHAT THE AGENT CANNOT RETURN", tone="purple")
    prot = [("cs", "c-lock-closed", "Contact phone and email: withheld", "purple",
             ["Dataverse column security, profile Contact Phone", "Protection: phones from the start, email in Task 6.1",
              "get_customer_contacts: no phone, no email"], (2,), (0.2, 1.6)),
            ("dlp", "c-lock-shield", "Card number: blocked by Microsoft Purview", "purple",
             ["An internal note on TCK-10521 holds a card number;", "the DLP policy for Credit Card Number blocks it",
              "withheld_by_policy"], (2,), (1.6, 3.0)),
            ("lbl", "c-document-lock", "Labeled document: refused", "purple",
             ["Woodgrove-Bank-Secure-Gateway-configuration.docx", "is labeled Relecloud Confidential; the label check",
              "CONTENT_BLOCKED_BY_LABEL"], (0, 2), (3.0, 4.4))]
    for i, (key, icon, title, tone, lines, mono, win) in enumerate(prot):
        y = 138 + i * 158
        lcard(d, key, 52, y, 516, 142, icon, title, lines, mono_lines=mono, tone=tone, icon_size=34, title_size=14.5,
              glow=[win])
        chip(d, 552, y + 12, "Withheld", [(win[0] + 0.6, 9.9)], tone="red", mono=False, anchor="end")

    # Right: one correlation ID found at every hop.
    d.lane(600, 120, 564, 492, "ONE CORRELATION ID, EVERY HOP (TASK 6.3)", tone="blue")
    d.terminal(616, 136, 532, 124, "PowerShell 7 on the lab VM", [
        ("", "out", 0.0, 0),
        ("$id = '0b6f3c9e-6d2a-4f55-9a43-2d7c1e8b5a10'", "cmd", 4.5, 0.6),
        ("C:\\LabFiles\\tools\\Get-ActionTrail.ps1 -CorrelationId $id", "cmd", 5.2, 0.8),
    ], note="Illustrative")
    label(d, 632, 188, "# Task 6.3: assemble the trail of one action", size=12, mono=True, weight=400, color="#7C8BA1")
    hops = [("app-insights", "Application Insights", "Agent request and tool decision: update_ticket_priority"),
            ("api-management", "API Management gateway log", "Token validated, HTTP 200 on servicedesk-write"),
            ("container-app", "MCP server log", "Authorization Allowed; backend call to the Dataverse Web API"),
            ("dataverse", "Dataverse audit record", "TCK-10544 P4 Low to P3 Medium, for the Senior Technician"),
            ("c-task-list-square", "Agent Action row", "update_ticket_priority: Allowed, Succeeded"),
            ("c-chat", "Outcome returned", "The agent's tool result ends with the same correlation_id")]
    for i, (icon, title, line) in enumerate(hops):
        y = 264 + i * 56
        t = 6.15 + i * 0.55
        lcard(d, f"hop{i}", 640, y, 508, 48, icon, title, [line], tone="blue", icon_size=24, title_size=13,
              glow=[(t, t + 0.6)])
        chip(d, 1136, y + 6, f"ID {CID}", [(t + 0.1, 9.9)], anchor="end")
        d.raw(f'<circle cx="624" cy="{y + 24}" r="5" fill="#FFFFFF" stroke="{TONES["blue"][0]}" stroke-width="2"/>', layer="top")
        done_mark(d, 624, y + 24, [(t + 0.1, 9.9)], tone="blue", r=6)
    p = d.flow("trail", f"M624 {264 + 24} V{264 + 5 * 56 + 24}", tone="blue", arrow=False, track=False,
               active=[(6.0, 9.2)])
    d.packet_once(p, start=6.05, travel=2.8, tone="blue", r=4.5)

    d.caption = ("Protection acts before data reaches the agent, and Get-ActionTrail.ps1 finds the same correlation ID in "
                 "every log, from the agent's trace to the Dataverse audit.")
    return d


def tline(d: Diagram, x: float, y: float, text: str, avail: float, size: float = 11.5, weight: int = 400,
          color: str = INK2, mono: bool = False, layer: str = "cards") -> None:
    """One line of panel text, with an overflow warning against `avail` pixels."""
    if mono:
        if mono_width(text, size) > avail:
            d.warnings.append(f"{d.name}: '{text}' may overflow ({mono_width(text, size):.0f} > {avail:.0f})")
    else:
        d.check(text, size, weight >= 600, avail, "a panel")
    label(d, x, y, text, size=size, weight=weight, color=color, mono=mono, layer=layer)


# =============================================================================
# Exercise 7: the end-to-end scenario and the business case (facts from the seed manifest's scenarios)
# =============================================================================
def exercise_7_end_to_end(icons: Path) -> Diagram:
    d = Diagram(
        "exercise-7-end-to-end",
        title="End to end: from a new incident to an approved, traced fix",
        subtitle=("TCK-10562 at Consolidated Messenger: the agent reads the context, recommends a cited triage, makes the "
                  "writes you approve and leaves a trail for the business case."),
        tag="EXERCISE 7",
        aria=("Five stages. One, the new incident TCK-10562 at Consolidated Messenger, CUST-020, Silver, Fully Managed: "
              "dispatchers can't load routes because of a certificate warning; five dispatchers at the north depot see "
              "that the routing application's certificate has expired, vans are waiting, and the south depot works; the "
              "ticket is New with no priority, category or technician, and it is not in the search index. Two, the agent "
              "reads the context: procedure CUST-020-PR3, Dispatch hours, makes a routing outage that stops dispatchers a "
              "P2 and says to phone the operations contact; the KB0133 history has 10 tickets, all handled by Daniel Cho, "
              "TECH-06, the 7 P2 tickets escalated to the Vendor and 2 of them in a routing application; runbook RB-005 "
              "says to find the server and binding and bind the renewed certificate; configuration notes CDOC-032 name "
              "the north depot routing server CMRT-N01. Three, the recommendation: Line-of-Business App, Certificate, P2 "
              "High with a 16 business hour target, Daniel Cho, TECH-06, escalate to the Vendor and phone Victor Murphy, "
              "the operations contact. Four, you approve each write: update_ticket_category, update_ticket_priority, "
              "assign_ticket and add_public_reply, each through API Management and the MCP server, on your behalf. Five, "
              "each write leaves a correlated trail in Application Insights, API Management, the MCP server log, the "
              "Dataverse audit and an Agent Action row, which becomes the evidence for the business case: last quarter "
              "11 Platinum and Gold SLA breaches cost USD 18,400 in service credits."),
        icons_dir=icons, loop=10, fps=12)

    ws = [196, 236, 212, 252, 176]
    xs = [36]
    for w in ws[:-1]:
        xs.append(xs[-1] + w + 14)
    S = [(0.0, 1.8), (1.8, 3.8), (3.8, 5.6), (5.6, 7.8), (7.8, 9.9)]
    stages = [("c-mail", "New incident", "blue"), ("c-search", "Read the context", "teal"), ("c-lightbulb", "Recommend", "green"),
              ("c-checkmark-circle", "Approve and write", "purple"), ("c-ribbon-star", "Prove it", "amber")]
    for i, ((icon, title, tone), x, w, win) in enumerate(zip(stages, xs, ws, S)):
        lcard(d, f"s{i}", x, 110, w, 56, icon, title, (), tone=tone, icon_size=24, title_size=14, glow=[win])
        d.badge(x + w - 12, 116, i + 1, tone=tone, active=[win])
        d.card(f"p{i}", x, 182, w, 430, "", (), tone=tone, style="card", glow=[win])
        if i:
            pid = d.flow(f"a{i}", f"M{xs[i - 1] + ws[i - 1]} 138 H{x}", tone=tone, active=[(win[0] - 0.2, win[0] + 0.5)])
            d.packet_once(pid, start=win[0] - 0.15, travel=0.3, tone=tone)
    cap = lambda i, text: label(d, xs[i] + 16, 204, text, size=10, mono=True, weight=700, color=TONES[stages[i][2]][0],
                                layer="cards")

    # 1. The new incident.
    x, a = xs[0] + 16, ws[0] - 30
    cap(0, "TCK-10562")
    tline(d, x, 228, "Dispatchers can't load", a, 12.5, 700, INK)
    tline(d, x, 245, "routes: certificate warning", a, 12.5, 700, INK)
    tline(d, x, 272, "Consolidated Messenger", a, 12, 600, INK)
    tline(d, x, 289, "CUST-020, Silver,", a)
    tline(d, x, 305, "Fully Managed", a)
    for j, line in enumerate(["Five dispatchers at the north", "depot see that the routing", "application's certificate has",
                              "expired. Vans are waiting;", "the south depot works."]):
        tline(d, x, 332 + j * 16, line, a)
    for j, (text, tone) in enumerate((("Status: New", "blue"), ("No priority or category", "slate"),
                                      ("No technician yet", "slate"), ("Not in the index", "amber"))):
        chip(d, x, 428 + j * 26, text, None, tone=tone, mono=False, layer="cards")

    # 2. The context the agent reads.
    x, a = xs[1] + 16, ws[1] - 30
    cap(1, "WHAT THE AGENT READS")
    srcs = [("CUST-020-PR3", "Dispatch hours", ["A routing outage that stops", "dispatchers is P2: phone the",
             "operations contact at once"]),
            ("KB0133", "Certificate expired warning", ["10 tickets, all Daniel Cho;", "the 7 P2 tickets escalated",
             "to the Vendor; 2 were in a", "routing application"]),
            ("RB-005", "Certificate expired runbook", ["Find the server and binding,", "bind the renewed certificate"]),
            ("CDOC-032", "Configuration notes", ["North depot routing server", "CMRT-N01"])]
    y = 226
    for j, (code, name, lines) in enumerate(srcs):
        h = 24 + len(lines) * 16
        t = 2.0 + j * 0.45
        halo(d, x - 8, y - 14, ws[1] - 18, h + 4, [(t, t + 0.8)], "teal", rx=8)
        tline(d, x, y, code, a, 11, 700, TONES["teal"][3], mono=True)
        tline(d, x + mono_width(code, 11) + 8, y, name, a - mono_width(code, 11) - 8, 11.5, 600, INK)
        for k, line in enumerate(lines):
            tline(d, x, y + 18 + k * 16, line, a)
        y += h + 22

    # 3. The recommendation, with what it cites.
    x, a = xs[2] + 16, ws[2] - 30
    cap(2, "RECOMMENDATION")
    recs = [("CATEGORY", "Line-of-Business App"), ("SUBCATEGORY", "Certificate"), ("PRIORITY", "P2 High, 16 h target"),
            ("TECHNICIAN", "Daniel Cho, TECH-06"), ("ESCALATE TO", "Vendor"), ("PHONE THE OPERATIONS CONTACT", "Victor Murphy")]
    for j, (name, value) in enumerate(recs):
        y = 232 + j * 44
        t = 4.0 + j * 0.25
        label(d, x, y, name, size=9.5, mono=True, weight=700, color=TONES["slate"][0], layer="cards")
        tline(d, x, y + 17, value, a, 12.5, 700, INK)
        halo(d, x - 8, y - 13, ws[2] - 18, 38, [(t, t + 0.7)], "green", rx=6)
    d.raw(f'<rect x="{x - 4}" y="506" width="{ws[2] - 24}" height="88" rx="8" fill="{TONES["green"][1]}" '
          f'stroke="{TONES["green"][2]}"/>', layer="cards")
    for j, line in enumerate(["Cites CUST-020-PR3 for P2,", "KB0133 for Daniel Cho and", "the Vendor, RB-005 for", "the fix"]):
        tline(d, x + 6, 526 + j * 17, line, a - 10, 11.5, 600, TONES["green"][3])

    # 4. Approve each write; each runs through the gateway and the MCP server on your behalf.
    x, a = xs[3] + 16, ws[3] - 30
    cap(3, "APPROVE EACH WRITE")
    writes = [("update_ticket_category", "Line-of-Business App, Certificate"), ("update_ticket_priority", "2, that is P2 High"),
              ("assign_ticket", "TECH-06, Daniel Cho"), ("add_public_reply", "Customer-visible update")]
    for j, (tool, args) in enumerate(writes):
        y = 228 + j * 62
        t = 5.8 + j * 0.5
        d.raw(f'<rect x="{x - 6}" y="{y - 14}" width="{ws[3] - 20}" height="50" rx="8" fill="#FFFFFF" stroke="{LINE_SOFT}"/>',
              layer="cards")
        tline(d, x + 2, y + 2, tool, a - 30, 11, 700, TONES["purple"][3], mono=True)
        tline(d, x + 2, y + 21, args, a - 30, 11.5)
        done_mark(d, xs[3] + ws[3] - 30, y + 11, [(t + 0.3, 9.9)], tone="green", r=9)
        halo(d, x - 6, y - 14, ws[3] - 20, 50, [(t, t + 0.5)], "purple", rx=8)
    for j, line in enumerate(["Each call: servicedesk-write,", "API Management, the MCP server,",
                              "then Dataverse on your behalf,", "with its own correlation ID"]):
        tline(d, x, 488 + j * 17, line, a, 11.5, 400, INK2)
    chip(d, x, 562, "4 approvals, 4 Agent Action rows", [(7.6, 9.9)], tone="purple", mono=False)

    # 5. Prove it: the trail of each write feeds the business case.
    x, a = xs[4] + 16, ws[4] - 30
    cap(4, "TRAIL OF EACH WRITE")
    trail = ["Application Insights", "API Management log", "MCP server log", "Dataverse audit", "Agent Action row"]
    for j, hop in enumerate(trail):
        y = 228 + j * 24
        tline(d, x + 20, y, hop, a - 20, 11.5, 600, INK)
        d.raw(f'<circle cx="{x + 6}" cy="{y - 4}" r="6" fill="#FFFFFF" stroke="{TONES["amber"][2]}" stroke-width="1.6"/>',
              layer="cards")
        done_mark(d, x + 6, y - 4, [(8.0 + j * 0.2, 9.9)], tone="amber", r=6)
    d.raw(f'<rect x="{x - 4}" y="358" width="{ws[4] - 24}" height="236" rx="8" fill="{TONES["amber"][1]}" '
          f'stroke="{TONES["amber"][2]}"/>', layer="cards")
    label(d, x + 4, 380, "BUSINESS CASE", size=10, mono=True, weight=700, color=TONES["amber"][0], layer="cards")
    for j, (line, wgt) in enumerate((("Last quarter: 11", 700), ("Platinum and Gold", 700), ("breaches cost", 700),
                                     ("USD 18,400 in", 700), ("service credits", 700), ("", 400),
                                     ("Here: every change", 400), ("approved, made on", 400), ("your behalf and", 400),
                                     ("traced end to end", 400))):
        if line:
            tline(d, x + 4, 404 + j * 18, line, a - 8, 12, wgt, TONES["amber"][3] if wgt == 700 else INK2)
    halo(d, x - 4, 358, ws[4] - 24, 236, [(9.0, 9.9)], "amber", rx=8)

    d.caption = ("Each step cites a record, each change waits for your approval, and the trail of every write becomes the "
                 "evidence behind the business case.")
    return d


# =============================================================================
# Agenda: the 4-hour lab window
# =============================================================================
def session_journey(icons: Path) -> Diagram:
    d = Diagram(
        "session-journey",
        title="Your 4-hour lab window at a glance",
        subtitle="Sign in, seven hands-on exercises back to back, and a short close. There are no scheduled breaks.",
        tag="AGENDA",
        aria=("A timeline of the 4-hour lab window, counted from the start time: 10 minutes to sign in, launch the lab and "
              "check readiness; Exercise 1, grounding the agent, 35 minutes; Exercise 2, ticket and incident intelligence, "
              "25 minutes; Exercise 3, the MCP read tools, 35 minutes; Exercise 4, the MCP action tools, 50 minutes; "
              "Exercise 5, identity, secrets and authorization, 30 minutes; Exercise 6, data protection and auditability, "
              "30 minutes; Exercise 7, the end-to-end scenario and business case, 15 minutes; and 10 minutes to close. "
              "A marker moves along the timeline and each exercise card lights up in turn. After the window, reviewers "
              "judge the submitted work for 24 hours, with no participant work."),
        icons_dir=icons, loop=10, fps=12)

    blocks = [  # (start minute, length, kind, label)
        (0, 10, "x", "Sign in"), (10, 35, "l", "Ex 1"), (45, 25, "l", "Ex 2"), (70, 35, "l", "Ex 3"),
        (105, 50, "l", "Ex 4"), (155, 30, "l", "Ex 5"), (185, 30, "l", "Ex 6"), (215, 15, "l", "Ex 7"),
        (230, 10, "x", "Close"),
    ]
    total = 240
    x0, x1, ty = 60, 1140, 208
    ppm = (x1 - x0) / total
    colors = {"l": ("#0E7C86", "#FFFFFF"), "x": ("#E7EBF0", "#59636E")}
    for s, n, kind, label in blocks:
        bx = x0 + s * ppm
        bw = n * ppm - 3
        fill, ink = colors[kind]
        d.raw(f'<rect x="{fmt(bx)}" y="{ty}" width="{fmt(bw)}" height="44" rx="8" fill="{fill}"/>', layer="cards")
        size = 12.5 if n >= 15 else 11
        d.raw(f'<text x="{fmt(bx + bw / 2)}" y="{ty + 27}" font-family="{FONT}" font-size="{size}" font-weight="700" '
              f'fill="{ink}" text-anchor="middle">{esc(label)}</text>', layer="cards")
    for m in range(0, total + 1, 30):
        hh, mm = divmod(m, 60)
        d.text(x0 + m * ppm, ty + 70, f"{hh:02d}:{mm:02d}", size=11.5, color="#59636E", anchor="middle", mono=True)
        d.raw(f'<line x1="{fmt(x0 + m * ppm)}" y1="{ty + 50}" x2="{fmt(x0 + m * ppm)}" y2="{ty + 56}" '
              f'stroke="#9AA7B4" stroke-width="1.4"/>', layer="cards")
    # The "now" marker walks across the window once per loop.
    d.raw(f'<g><animateTransform attributeName="transform" type="translate" dur="10s" repeatCount="indefinite" '
          f'calcMode="linear" keyTimes="0;0.96;1" values="0 0;{fmt(x1 - x0)} 0;{fmt(x1 - x0)} 0"/>'
          f'<line x1="{x0}" y1="{ty - 14}" x2="{x0}" y2="{ty + 58}" stroke="#C50F1F" stroke-width="2.4"/>'
          f'<circle cx="{x0}" cy="{ty - 18}" r="6" fill="#C50F1F" stroke="#FFFFFF" stroke-width="2"/></g>', layer="fx")
    for lx, label, fill, ink in [(60, "HANDS-ON EXERCISE", "#0E7C86", "#0E7C86"), (236, "SIGN IN AND CLOSE", "#E7EBF0", "#59636E")]:
        d.raw(f'<rect x="{lx}" y="160" width="22" height="12" rx="3" fill="{fill}"/>', layer="top")
        d.text(lx + 30, 170, label, size=10.5, color=ink, weight=700, mono=True)
    d.text(1140, 170, "TIMES FROM THE START OF YOUR WINDOW", size=10.5, color="#59636E", weight=700, mono=True, anchor="end")

    mods = [("m1", "ai-search", "1. Ground", ["Index and cite", "your own data"], 10, 45),
            ("m2", "c-task-list-square", "2. Triage", ["Similar tickets", "and SLA risk"], 45, 70),
            ("m3", "container-app", "3. Read", ["MCP read tools", "and redeploy"], 70, 105),
            ("m4", "c-checkmark-circle", "4. Act", ["Approved writes", "and a new tool"], 105, 155),
            ("m5", "entra-id", "5. Identity", ["Tokens, secrets", "and denials"], 155, 185),
            ("m6", "c-lock-shield", "6. Protect", ["Purview and the", "audit trail"], 185, 215),
            ("m7", "c-ribbon-star", "7. Deliver", ["End to end and", "business case"], 215, 230)]
    cw, gap = 146, 9
    for i, (key, icon, title, lines, s, e) in enumerate(mods):
        t0, t1 = s / total * 9.6, e / total * 9.6
        cx0 = 60 + i * (cw + gap)
        tone = "purple" if key in ("m5", "m6") else "teal"
        # Narrow cards: the icon sits above the text instead of beside it, so the lines keep their width.
        d.card(key, cx0, 330, cw, 140, title, lines, tone=tone, title_size=14.5, glow=[(t0, t1)], valign="middle")
        d.icon(icon, cx0 + 18, 346, 30)
        mx = x0 + (s + (e - s) / 2) * ppm
        ccx = cx0 + cw / 2
        d.raw(f'<path d="M{fmt(mx)} {ty + 78} C{fmt(mx)} {ty + 100} {fmt(ccx)} 300 {fmt(ccx)} 328" stroke="#B7C2CE" '
              f'stroke-width="1.4" stroke-dasharray="3 4" fill="none"/>', layer="wires")
    d.card("review", 60, 494, 520, 104, "After the window: 24-hour review", ["Reviewers judge your submitted work.",
           "You do no lab work, and the environment is then deleted."], icon="c-clock", tone="slate", style="tint",
           icon_size=34, title_size=14.5)
    d.card("out", 600, 494, 540, 104, "You leave with", ["A grounded support agent, governed MCP tools including one",
           "you designed, and a business case backed by an audit trail."], icon="c-ribbon-star", tone="green",
           style="tint", icon_size=34, title_size=14.5)
    d.caption = "Exercises take 220 minutes of the 4 hours; the other 20 are for sign-in and the close."
    return d


DIAGRAMS = {
    "architecture": architecture,
    "exercise-1-grounding": exercise_1_grounding,
    "exercise-2-ticket-intelligence": exercise_2_ticket_intelligence,
    "exercise-3-mcp-read-path": exercise_3_mcp_read_path,
    "exercise-4-approval-flow": exercise_4_approval_flow,
    "exercise-5-identity-token-flow": exercise_5_identity_token_flow,
    "exercise-6-protection-and-trail": exercise_6_protection_and_trail,
    "exercise-7-end-to-end": exercise_7_end_to_end,
    "session-journey": session_journey,
}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Build the lab's diagrams as animated SVG files.")
    parser.add_argument("names", nargs="*", metavar="name", help=f"diagrams to build (default: all): {', '.join(DIAGRAMS)}")
    parser.add_argument("--out", type=Path, help="folder for the SVG files (default: Instructions/media in the lab repository)")
    parser.add_argument("--icons", type=Path, default=DEFAULT_ICONS, help="folder with the staged icons (default: icons next to this script)")
    args = parser.parse_args(argv)

    unknown = [n for n in args.names if n not in DIAGRAMS]
    if unknown:
        parser.error(f"unknown diagram(s): {', '.join(unknown)}; choose from {', '.join(DIAGRAMS)}")
    out = args.out or DEFAULT_OUT
    if not args.icons.is_dir():
        parser.error(f"no icons folder at {args.icons}; run Get-ProductIcons.ps1 first or pass --icons")

    warned = False
    for name in args.names or list(DIAGRAMS):
        d = DIAGRAMS[name](args.icons)
        path = d.save(out)
        print(f"wrote {path} ({path.stat().st_size // 1024} KB)")
        for warning in d.warnings:
            warned = True
            print("  WARN", warning)
    return 1 if warned else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
