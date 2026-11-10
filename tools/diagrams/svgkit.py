"""svgkit: the design system and animation API for CloudLabs lab diagrams.

Every lab diagram is an SVG written by a small Python function that calls this module. The
diagrams share one design system: a Fluent-aligned palette (TONES), white cards with soft shadows,
official Microsoft product and concept icons (embedded once per file as data URIs), dashed lanes
with monospace captions, flowing connectors, comet-style packets that travel along the connectors,
glows that walk the story step by step, pulse rings, pop-up notes (toasts) and typing terminals.

All animation is SMIL, so the SVG animates in a browser and in a GitHub README without any script.
Render-Diagrams.ps1 turns each SVG into a verified animated PNG for the lab guide.

Requires Python 3.11 or later and the standard library only.

Workflow in a lab repository (the toolkit is copied to tools/diagrams/)
======================================================================
    pwsh tools/diagrams/Get-ProductIcons.ps1 -IconsPath tools/diagrams/icons   # once
    python tools/diagrams/build_diagrams.py [name ...]       # writes Instructions/media/<name>.svg
    pwsh tools/diagrams/Render-Diagrams.ps1 -Name <name>     # writes Instructions/media/<name>.png
build_diagrams.py is the lab's own script, started from build_diagrams_example.py: one function
per diagram and a registry of names. See README.md in this folder for the design rules.

Quick start
===========
    from pathlib import Path
    from svgkit import Diagram

    d = Diagram("architecture", title="Your lab environment at a glance",
                subtitle="You work from a jump VM in your browser.", tag="GETTING STARTED",
                aria="Long description of the whole diagram for screen readers.",
                icons_dir=Path("tools/diagrams/icons"))
    d.card("vm", 330, 140, 260, 90, "Jump VM", ["Windows Server 2022"], icon="vm", glow=[(0, 2)])
    pid = d.flow("a1", "M290 185 H330", tone="blue")
    d.packet_loop(pid, dur=2.5)
    d.caption = "Everything you need is installed on the jump VM."
    d.save(Path("Instructions/media"))
    for warning in d.warnings:
        print("WARN", warning)

Canvas and layout zones (default 1200 by 675)
=============================================
    y 0 to about 88      header: title (24 px, baseline 50), subtitle (13.5 px, baseline 75) and
                         the tag pill at the top right. Keep content below y = 88; lane captions
                         sit 9 px above their lane, so lanes start at y = 104 or lower on the page.
    y 88 to h - 50       content: lanes, cards, flows, toasts, terminals.
    y h - 46 to h        footer: a rule, then "Key idea" and the caption, with an optional legend
                         at the right.
Elements that leave the canvas or cut into the header or footer produce a warning.

Timing model
============
* loop: the length of one animation cycle in seconds (default 10). Every animation repeats once
  per loop, so the diagram plays seamlessly forever.
* fps: frames per second for the animated PNG (default 12). loop times fps must be a whole number
  (10 s at 12 fps gives 120 frames). Both values are written to the svg root as
  data-loop-seconds and data-frames-per-second, which Render-Diagrams.ps1 reads.
* Windows: most highlights take a list of (start, end) pairs in seconds inside one loop, for
  example glow=[(1.6, 3.2), (8.0, 9.6)]. An end past the loop wraps around (a window of (9, 11)
  is on from 9 s to 10 s and from 0 s to 1 s). Overlapping windows are merged. A window fades in
  and out over 0.17 s by default (toasts 0.2 s, cards that appear 0.25 s).
* Glow windows (card glow and alt_glow, badge active): when a card's step of the story plays, a
  colored ring and a soft halo light it up.
* Active flow windows (flow active): the connector's dashes flow only during these windows; the
  rest of the time it rests as a thin calm line with its arrow, so the eye follows the step that
  is playing. Without active windows a connector flows all the time.
* Periods: every repeating animation must divide the loop, or it jumps at the loop boundary.
  Dash flow speed (default 0.5 s), packet_loop dur, pulse period and the terminal cursor (1 s)
  are checked and produce a warning when they do not divide the loop.
* packet_once: a packet that starts at `start` and travels for `travel` seconds must finish
  inside the same loop; shift its start if it would wrap.
* Render-Diagrams.ps1 samples frames from the second loop (t = loop + k / fps), so animations with
  negative or delayed begin times are already under way in every frame.

Layers (drawing order, first is at the back)
============================================
    lanes, wires, cards, flows, fx, top
Cards sit above wires, flows and packets (fx) above cards, and toasts, badges and free text (top)
above everything. raw(), text() and icon() take a layer argument.

Public API (details in each docstring)
======================================
    Diagram(name, title, subtitle, tag, aria, icons_dir, w=1200, h=675, loop=10.0, fps=12,
            caption=None, legend=None)
    Diagram.lane(x, y, w, h, label, tone="slate", fill=True)
    Diagram.text(x, y, s, size=12, color=INK2, weight=400, anchor="start", mono=False,
                 layer="top", extra="", max_width=None)
    Diagram.icon(key, x, y, size, layer="cards")
    Diagram.symbol(key) -> str
    Diagram.card(key, x, y, w, h, title, lines=(), icon=None, tone="blue", style="card",
                 glow=(), icon_size=None, title_size=14.5, badge=None, chip=None,
                 glow_tone=None, alt_glow=None, title_mono=False, appear=None, valign="middle")
    Diagram.hero(key, x, y, w, h, title, subtitle, icon, header_h=86, tone_a="#0F6CBD",
                 tone_b="#5B5FC7")
    Diagram.flow(key, d, tone="blue", arrow=True, width=2.6, track=True, speed=0.5,
                 active=None) -> path id
    Diagram.wire(d, color=INK3, width=1.6, dash=None, arrow=False)
    Diagram.packet_loop(path_id, dur, begin=0.0, tone="blue", r=5.5)
    Diagram.packet_once(path_id, start, travel, tone="blue", r=5.5)
    Diagram.pulse(cx, cy, r0, r1, tone="blue", period=2.0, begin=0.0, width=2.0)
    Diagram.toast(x, y, w, text, wins, icon=None, tone="green", mark="check")
    Diagram.badge(cx, cy, n, tone="blue", active=(), r=13)
    Diagram.raw(svg, layer="top")
    Diagram.terminal(x, y, w, h, title, lines, note=None, prompt="PS> ")
    Diagram.check(text, size, bold, avail, where)
    Diagram.render(caption=None, legend=None) -> str
    Diagram.save(out_dir, caption=None, legend=None) -> Path
    Diagram.tl (a Timeline), Diagram.warnings (list of str), Diagram.caption (str),
    Diagram.legend (list of (label, tone, kind) or None)
    Timeline(loop).windows(wins, on, off, fade=0.17) and Timeline(loop).anim(attr, wins, on, off,
             fade=0.17)
    esc(text), fmt(value), text_width(text, size, bold=False), mono_width(text, size, spacing=0)

Icons
=====
Icons are loaded by key from icons_dir: the key "vm" reads icons_dir/vm.svg. Get-ProductIcons.ps1
downloads the official Microsoft icon packs and stages the icons by key. Each icon is embedded
once per diagram as a base64 data URI inside a <symbol>, then placed with <use>. Show the
product name next to every product icon, and never recolor, crop or distort an icon.

House style
===========
save() refuses to write a diagram whose text contains an em dash, an en dash or a spaced double
hyphen (typed terminal commands may contain a double hyphen, because it is command syntax).
"""
from __future__ import annotations

import base64
import html
import re
from pathlib import Path

__all__ = [
    "FONT", "MONO", "INK", "INK2", "INK3", "LINE", "LANE", "LANELINE", "CARD", "TONES",
    "esc", "fmt", "text_width", "mono_width", "Timeline", "Diagram",
]

# ==== Design tokens ===========================================================================

FONT = "Segoe UI, Helvetica Neue, Arial, sans-serif"
MONO = "Cascadia Mono, Consolas, Menlo, monospace"

INK, INK2, INK3 = "#1F2328", "#59636E", "#8C959F"
LINE, LANE, LANELINE, CARD = "#D0D7DE", "#F6F8FA", "#D8DEE4", "#FFFFFF"

TONES = {
    #          strong     tint 1     tint 2     text on tint
    "blue":   ("#0F6CBD", "#EBF3FC", "#CFE4FA", "#0C3B5E"),
    "purple": ("#5B5FC7", "#F0F0FB", "#DCDDF7", "#2F2F7A"),
    "teal":   ("#0E7C86", "#E6F4F5", "#C3E6E9", "#08474D"),
    "green":  ("#107C10", "#EAF6EA", "#C9E7C9", "#0B4F0B"),
    "amber":  ("#B35C00", "#FFF4E5", "#FBDDB5", "#6B3700"),
    "red":    ("#C50F1F", "#FDECEE", "#F6C6CB", "#6E0811"),
    "slate":  ("#59636E", "#F3F5F7", "#DDE3E9", "#24292F"),
}

LAYERS = ("lanes", "wires", "cards", "flows", "fx", "top")

# Forbidden in diagram text. Written as escapes so this file never contains the characters.
_EM_DASH = "\u2014"
_EN_DASH = "\u2013"
_SPACED_DOUBLE_HYPHEN = re.compile(r"\S\s--\s\S")

# Monospace glyphs are about 0.6 em wide.
_MONO_EM = 0.6
# Typed terminal text is 12 px; this is the width per character used for the typing clip.
_TERM_CHAR = 7.4


# ==== Helpers =================================================================================

def esc(text: str) -> str:
    """Escape text for use in SVG text content and attribute values."""
    return html.escape(str(text), quote=True)


def fmt(v: float) -> str:
    """Format a number compactly for SVG: at most four decimals, no trailing zeros, no -0."""
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return s if s not in ("", "-0") else "0"


_NARROW = set("il.,:;|!'ftjrI ()[]")
_WIDE = set("mwMW@%")


def text_width(text: str, size: float, bold: bool = False) -> float:
    """Rough Segoe UI width estimate in pixels. Used only to warn about overflow."""
    w = 0.0
    for ch in text:
        if ch in _NARROW:
            w += 0.30
        elif ch in _WIDE:
            w += 0.82
        elif ch.isupper():
            w += 0.63
        elif ch.isdigit():
            w += 0.55
        else:
            w += 0.52
    return w * size * (1.05 if bold else 1.0)


def mono_width(text: str, size: float, spacing: float = 0.0) -> float:
    """Width estimate in pixels for monospace text with optional letter spacing."""
    return len(text) * (size * _MONO_EM + spacing)


def _divides(loop: float, period: float) -> bool:
    if period <= 0:
        return False
    ratio = loop / period
    return abs(ratio - round(ratio)) < 1e-6


# ==== Timeline ================================================================================

class Timeline:
    """Builds SMIL keyTimes and values that switch a property on and off inside one loop.

    Parameters
    ==========
    loop : float
        The loop length in seconds.

    Methods
    =======
    windows(wins, on, off, fade=0.17) -> (key_times, values)
        wins is a list of (start, end) pairs in seconds. An end past the loop wraps around to the
        start of the loop; overlapping or touching windows are merged; a window of a whole loop or
        longer is always on. The value is `on` inside a window and `off` outside it, with a linear
        fade of `fade` seconds at each edge (shortened for very short windows).
    anim(attr, wins, on, off, fade=0.17) -> str
        The same windows as a complete <animate> element for the attribute `attr`, for example
        d.tl.anim("opacity", [(2.0, 4.0)], 1, 0) inside a raw <g opacity="0"> group.
    """

    def __init__(self, loop: float):
        self.loop = float(loop)

    def _segments(self, wins):
        L = self.loop
        segs = []
        for s, e in wins:
            s, e = float(s), float(e)
            if e <= s:
                raise ValueError(f"window ({s}, {e}) must end after it starts")
            span = e - s
            if span >= L:
                return [(0.0, L, False, False)]
            s = s % L
            e = s + span
            if e <= L:
                segs.append([s, e, True, True])
            else:  # wraps around the loop boundary
                segs.append([s, L, True, False])
                segs.append([0.0, e - L, False, True])
        segs.sort(key=lambda g: (g[0], g[1]))
        merged = []
        for g in segs:
            if merged and g[0] <= merged[-1][1] + 1e-9:
                last = merged[-1]
                if g[1] >= last[1]:
                    last[1], last[3] = g[1], g[3]
            else:
                merged.append(list(g))
        if len(merged) >= 2 and merged[0][0] == 0.0 and merged[-1][1] >= L - 1e-9:
            # The first window starts at zero and the last ends at the loop: one wrapped window.
            merged[0][2] = False
            merged[-1][3] = False
        return [tuple(g) for g in merged]

    def windows(self, wins, on, off, fade=0.17):
        L = self.loop
        segs = self._segments(wins)
        pts = []

        def add(t, v):
            t = min(max(t, 0.0), L)
            if pts and abs(pts[-1][0] - t) < 1e-6:
                pts[-1] = (t, v)
            elif not pts or t > pts[-1][0]:
                pts.append((t, v))

        starts_on = any(s == 0.0 and not fin for s, _, fin, _ in segs)
        add(0.0, on if starts_on else off)
        for s, e, fade_in, fade_out in segs:
            f = min(fade, (e - s) / 3)
            if fade_in:
                add(s, off)
                add(s + f, on)
            else:
                add(s, on)
            if fade_out:
                add(e - f, on)
                add(e, off)
            else:
                add(e, on)
        if pts[-1][0] < L:
            add(L, pts[-1][1])
        key_times = ";".join(fmt(t / L) for t, _ in pts)
        values = ";".join(str(v) for _, v in pts)
        return key_times, values

    def anim(self, attr, wins, on, off, fade=0.17):
        kt, vals = self.windows(wins, on, off, fade)
        return (f'<animate attributeName="{attr}" dur="{fmt(self.loop)}s" repeatCount="indefinite" '
                f'calcMode="linear" keyTimes="{kt}" values="{vals}"/>')


# ==== Diagram =================================================================================

class Diagram:
    """One animated diagram.

    Parameters
    ==========
    name : str
        Base file name without extension, for example "architecture" or "exercise-2-flow".
    title : str
        The headline at the top left (24 px bold). Say what the learner should understand.
    subtitle : str
        One sentence under the title (13.5 px) that sets the context.
    tag : str
        The pill at the top right, in capitals, for example "GETTING STARTED" or "EXERCISE 3".
    aria : str
        A full text description of the diagram for screen readers (the svg aria-label).
    icons_dir : Path
        Folder with the staged icons (<key>.svg), as written by Get-ProductIcons.ps1.
    w, h : int
        Canvas size in pixels. Lab diagrams use 1200 by 675.
    loop : float
        Loop length in seconds (default 10).
    fps : int
        Frames per second for the animated PNG (default 12). loop times fps must be whole.
    caption : str, optional
        The "Key idea" sentence in the footer. Can also be set later through d.caption or
        passed to save().
    legend : list of (label, tone, kind), optional
        Legend entries at the right of the footer, where kind is "flow" (a dashed line), "dot"
        (a packet) or "box" (a card outline). Can also be set later through d.legend.

    Attributes
    ==========
    tl : Timeline
        The diagram's timeline, for custom animations in raw SVG.
    warnings : list of str
        Overflow, layout and timing warnings collected while building. Print them and fix them.
    caption : str or None
        The default caption used by render() and save().
    legend : list or None
        The default legend used by render() and save().
    """

    def __init__(self, name: str, title: str, subtitle: str, tag: str, aria: str,
                 icons_dir: Path, w: int = 1200, h: int = 675, loop: float = 10.0, fps: int = 12,
                 caption: str | None = None, legend=None):
        frames = loop * fps
        if abs(frames - round(frames)) > 1e-6:
            raise ValueError(f"{name}: loop ({loop} s) times fps ({fps}) must be a whole number of frames")
        self.name, self.title, self.subtitle, self.tag, self.aria = name, title, subtitle, tag, aria
        self.icons_dir = Path(icons_dir)
        self.w, self.h, self.loop, self.fps = w, h, float(loop), int(fps)
        self.caption = caption
        self.legend = legend
        self.tl = Timeline(self.loop)
        self.icons: dict[str, str] = {}
        self.clips: list[str] = []
        self.layers: dict[str, list[str]] = {layer: [] for layer in LAYERS}
        self.warnings: list[str] = []
        self._n = 0
        self._ids: set[str] = set()
        self._cmd_texts: list[str] = []

    # ==== Internal helpers ====================================================================

    def _id(self, prefix: str) -> str:
        self._n += 1
        return f"{prefix}{self._n}"

    def _claim(self, element_id: str) -> None:
        if element_id in self._ids:
            raise ValueError(f"{self.name}: the key behind id '{element_id}' is used twice; keys must be unique")
        self._ids.add(element_id)

    def _warn(self, message: str) -> None:
        self.warnings.append(f"{self.name}: {message}")

    def _period(self, value: float, what: str) -> None:
        if not _divides(self.loop, value):
            self._warn(f"{what} of {fmt(value)} s does not divide the {fmt(self.loop)} s loop, so it jumps at the loop boundary")

    def _bounds(self, x: float, y: float, w: float, h: float, where: str) -> None:
        if x < 0 or y < 0 or x + w > self.w or y + h > self.h:
            self._warn(f"{where} extends beyond the {self.w} x {self.h} canvas")
        elif y < 88:
            self._warn(f"{where} starts at y = {fmt(y)}, inside the title area (keep content below y = 88)")
        elif y + h > self.h - 50:
            self._warn(f"{where} ends at y = {fmt(y + h)}, inside the caption area (keep content above y = {self.h - 50})")

    @staticmethod
    def _color(value: str) -> str:
        return TONES[value][0] if value in TONES else value

    def check(self, text: str, size: float, bold: bool, avail: float, where: str) -> None:
        """Warn when `text` at `size` px (bold or not) is estimated wider than `avail` pixels."""
        if text_width(text, size, bold) > avail:
            self._warn(f"'{text}' may overflow {where} ({text_width(text, size, bold):.0f} > {avail:.0f})")

    # ==== Icons ===============================================================================

    def symbol(self, key: str) -> str:
        """Return the id of the <symbol> for icon `key` (loads icons_dir/<key>.svg once).

        Use it in raw SVG: d.raw(f'<use href="#{d.symbol("vm")}" x="10" y="10" width="28" height="28"/>').
        """
        if key not in self.icons:
            path = self.icons_dir / f"{key}.svg"
            if not path.exists():
                raise FileNotFoundError(
                    f"Icon '{key}' not found in {self.icons_dir}. Run Get-ProductIcons.ps1, or add the key to its icon map.")
            raw = path.read_bytes()
            root = re.search(rb"<svg\b[^>]*>", raw)
            head = root.group(0) if root else b""
            vb = re.search(rb'viewBox\s*=\s*"([^"]+)"', head)
            if vb:
                viewbox = vb.group(1).decode()
            else:
                wm = re.search(rb'\bwidth\s*=\s*"([\d.]+)', head)
                hm = re.search(rb'\bheight\s*=\s*"([\d.]+)', head)
                viewbox = f"0 0 {wm.group(1).decode()} {hm.group(1).decode()}" if wm and hm else "0 0 48 48"
            parts = [float(v) for v in viewbox.replace(",", " ").split()]
            data = base64.b64encode(raw).decode()
            self.icons[key] = (
                f'<symbol id="ic-{key}" viewBox="{viewbox}">'
                f'<image href="data:image/svg+xml;base64,{data}" x="{fmt(parts[0])}" y="{fmt(parts[1])}" '
                f'width="{fmt(parts[2])}" height="{fmt(parts[3])}"/></symbol>'
            )
        return f"ic-{key}"

    # Kept for build scripts written against the first version of the toolkit.
    _icon_symbol = symbol

    def icon(self, key: str, x: float, y: float, size: float, layer: str = "cards") -> None:
        """Place icon `key` with its top left corner at (x, y), `size` pixels square."""
        sid = self.symbol(key)
        self.layers[layer].append(
            f'<use href="#{sid}" x="{fmt(x)}" y="{fmt(y)}" width="{fmt(size)}" height="{fmt(size)}"/>')

    # ==== Primitives ==========================================================================

    def lane(self, x, y, w, h, label, tone="slate", fill=True):
        """A dashed rounded container that groups related cards, with a monospace caption.

        x, y, w, h : the rectangle. The caption sits 9 px above the top edge.
        label : the caption, in capitals by convention ("YOUR AZURE RESOURCE GROUP").
        tone : the caption color, a TONES name.
        fill : True for a light gray fill, False for an outline only.
        """
        strong = TONES[tone][0]
        bg = LANE if fill else "none"
        self._bounds(x, y - 22, w, h + 22, f"lane '{label}'")
        if mono_width(label, 11, 1.3) > w - 32:
            self._warn(f"lane caption '{label}' may overflow its lane ({mono_width(label, 11, 1.3):.0f} > {w - 32:.0f})")
        self.layers["lanes"].append(
            f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="16" fill="{bg}" '
            f'stroke="{LANELINE}" stroke-width="1.2" stroke-dasharray="4 5"/>'
            f'<text x="{fmt(x + 16)}" y="{fmt(y - 9)}" font-family="{MONO}" font-size="11" font-weight="700" '
            f'letter-spacing="1.3" fill="{strong}">{esc(label)}</text>')

    def text(self, x, y, s, size=12, color=INK2, weight=400, anchor="start", mono=False, layer="top", extra="",
             max_width=None):
        """Free text with its baseline at (x, y).

        size, color, weight : font size in px, fill color, font weight.
        anchor : "start", "middle" or "end".
        mono : True for the monospace font (labels, code).
        layer : the layer to draw on (default "top").
        extra : raw attributes appended to the <text> element, for example ' opacity="0"'.
        max_width : when given, warn if the text is estimated wider than this many pixels.
        """
        fam = MONO if mono else FONT
        if max_width is not None:
            est = mono_width(s, size) if mono else text_width(s, size, weight >= 600)
            if est > max_width:
                self._warn(f"text '{s}' may overflow its {max_width:.0f} px ({est:.0f})")
        self.layers[layer].append(
            f'<text x="{fmt(x)}" y="{fmt(y)}" font-family="{fam}" font-size="{fmt(size)}" fill="{color}" '
            f'font-weight="{weight}" text-anchor="{anchor}"{extra}>{esc(s)}</text>')

    def card(self, key, x, y, w, h, title, lines=(), icon=None, tone="blue", style="card",
             glow=(), icon_size=None, title_size=14.5, badge=None, chip=None, glow_tone=None, alt_glow=None,
             title_mono=False, appear=None, valign="middle"):
        """A card: a rounded rectangle with a colored accent bar, an optional icon, a title and lines.

        key : unique id for this card (used for clip paths).
        x, y, w, h : the rectangle.
        title : the bold first line. lines : up to three short lines of 12 px text below it.
        icon : an icon key, drawn at the left; icon_size defaults to min(44, h - 22).
        tone : a TONES name for the accent bar, glow and chip.
        style : "card" (white), "tint" (tinted fill), "ghost" (white with a dashed border, for an
            optional or manual step) or "danger" (red tint, for a blocked or failed path).
        glow : windows when the card lights up (see the timing model).
        glow_tone : tone of the glow when it differs from `tone`.
        alt_glow : (windows, tone) for a second glow in another color, for example a red glow when
            the same card blocks a request later in the story.
        title_size : title font size in px. title_mono : monospace title (for code names).
        badge : a number or short text in a filled circle at the top right corner.
        chip : a short label in a pill at the bottom right corner.
        appear : windows when the card is visible; outside them it is hidden (objects that are
            created during the story).
        valign : "middle" centers the text block; "top" keeps it at the top of a tall card.
        """
        self._claim(f"cp-{key}")
        strong, t1, t2, tink = TONES[tone]
        gtone = TONES[glow_tone or tone][0]
        glows = [(glow, gtone)] if glow else []
        if alt_glow:
            glows.append((alt_glow[0], TONES[alt_glow[1]][0]))
        self._bounds(x, y, w, h, f"card {key}")
        L = self.layers["cards"]
        cid = f"cp-{key}"
        fill = CARD
        stroke = LINE
        dash = ""
        if style == "tint":
            fill, stroke = t1, t2
        elif style == "ghost":
            fill, stroke, dash = "#FFFFFF", t2, ' stroke-dasharray="5 4"'
        elif style == "danger":
            fill, stroke = TONES["red"][1], TONES["red"][2]
        elif style != "card":
            raise ValueError(f"{self.name}: card {key} has unknown style '{style}'")
        self.clips.append(f'<clipPath id="{cid}"><rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="12"/></clipPath>')
        if appear:
            L.append(f'<g id="card-{key}" opacity="0">{self.tl.anim("opacity", appear, 1, 0, fade=0.25)}')
        else:
            L.append(f'<g id="card-{key}">')
        L.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="12" fill="{fill}" '
                 f'stroke="{stroke}" stroke-width="1.2"{dash} filter="url(#sh)"/>')
        bar = strong if style != "danger" else TONES["red"][0]
        L.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="5" height="{fmt(h)}" fill="{bar}" clip-path="url(#{cid})"/>')
        for wins, col in glows:
            L.append(f'<rect x="{fmt(x - 3)}" y="{fmt(y - 3)}" width="{fmt(w + 6)}" height="{fmt(h + 6)}" rx="15" fill="none" '
                     f'stroke="{col}" stroke-width="7" opacity="0" filter="url(#blur)">{self.tl.anim("opacity", wins, 0.55, 0)}</rect>')
            L.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="12" fill="none" '
                     f'stroke="{col}" stroke-width="2.4" opacity="0">{self.tl.anim("opacity", wins, 1, 0)}</rect>')
        isz = icon_size or min(44, h - 22)
        tx = x + 18
        n = len(lines)
        block = title_size + (n * 16 if n else 0)
        top_area = min(h, block + 36) if valign == "top" else h
        if icon:
            iy = y + (top_area - isz) / 2
            self.icon(icon, x + 18, iy, isz)
            tx = x + 18 + isz + 14
        avail = x + w - 14 - tx
        ty = y + top_area / 2 - block / 2 + title_size * 0.8
        if block + 12 > h:
            self._warn(f"card {key}: {n} lines need about {block + 12:.0f} px but the card is {h:.0f} px tall")
        if badge is not None:
            bx, by = x + w - 20, y + 18
            L.append(f'<circle cx="{fmt(bx)}" cy="{fmt(by)}" r="10.5" fill="{strong}"/>'
                     f'<text x="{fmt(bx)}" y="{fmt(by + 4)}" font-family="{FONT}" font-size="11.5" font-weight="700" '
                     f'fill="#FFFFFF" text-anchor="middle">{esc(str(badge))}</text>')
            avail -= 18
        if title_mono:
            if mono_width(title, title_size) > avail:
                self._warn(f"'{title}' may overflow card {key} ({mono_width(title, title_size):.0f} > {avail:.0f})")
        else:
            self.check(title, title_size, True, avail, f"card {key}")
        tfam, tcol = (MONO, tink) if title_mono else (FONT, INK)
        L.append(f'<text x="{fmt(tx)}" y="{fmt(ty)}" font-family="{tfam}" font-size="{fmt(title_size)}" font-weight="600" '
                 f'fill="{tcol}">{esc(title)}</text>')
        chip_w = 0.0
        if chip:
            chip_w = text_width(chip, 10.5, True) + 18
        for i, line in enumerate(lines):
            room = avail - (chip_w + 6 if chip and i == n - 1 else 0)
            self.check(line, 12, False, room, f"card {key}")
            L.append(f'<text x="{fmt(tx)}" y="{fmt(ty + 17 + i * 16)}" font-family="{FONT}" font-size="12" fill="{INK2}">{esc(line)}</text>')
        if chip:
            cx = x + w - chip_w - 12
            cy = y + h - 26
            L.append(f'<rect x="{fmt(cx)}" y="{fmt(cy)}" width="{fmt(chip_w)}" height="18" rx="9" fill="{t1}" stroke="{t2}"/>'
                     f'<text x="{fmt(cx + chip_w / 2)}" y="{fmt(cy + 12.5)}" font-family="{FONT}" font-size="10.5" font-weight="600" '
                     f'fill="{tink}" text-anchor="middle">{esc(chip)}</text>')
        L.append("</g>")

    def hero(self, key, x, y, w, h, title, subtitle, icon, header_h=86, tone_a="#0F6CBD", tone_b="#5B5FC7"):
        """A large container with a gradient header, for the central platform of a diagram.

        key : unique id. x, y, w, h : the container. title, subtitle : header text (19 px and
        12.5 px, white). icon : icon key shown on a white tile in the header.
        header_h : header height in px. tone_a, tone_b : gradient start and end colors, as hex
        values or TONES names (for example tone_a="amber", tone_b="red").
        Place cards inside the container below the header.
        """
        self._claim(f"cp-{key}")
        self._bounds(x, y, w, h, f"hero {key}")
        L = self.layers["cards"]
        cid = f"cp-{key}"
        gid = f"gr-{key}"
        ca, cb = self._color(tone_a), self._color(tone_b)
        self.clips.append(f'<clipPath id="{cid}"><rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="18"/></clipPath>'
                          f'<linearGradient id="{gid}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{ca}"/>'
                          f'<stop offset="1" stop-color="{cb}"/></linearGradient>')
        L.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="18" fill="#FBFCFE" stroke="#C9D5E3" '
                 f'stroke-width="1.4" filter="url(#sh2)"/>')
        L.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(header_h)}" fill="url(#{gid})" clip-path="url(#{cid})"/>')
        L.append(f'<rect x="{fmt(x + 18)}" y="{fmt(y + (header_h - 52) / 2)}" width="52" height="52" rx="12" fill="#FFFFFF" opacity="0.96"/>')
        self.icon(icon, x + 24, y + (header_h - 40) / 2, 40)
        self.check(title, 19, True, w - 100, f"hero {key}")
        self.check(subtitle, 12.5, False, w - 100, f"hero {key} subtitle")
        L.append(f'<text x="{fmt(x + 84)}" y="{fmt(y + header_h / 2 - 2)}" font-family="{FONT}" font-size="19" font-weight="700" '
                 f'fill="#FFFFFF">{esc(title)}</text>')
        L.append(f'<text x="{fmt(x + 84)}" y="{fmt(y + header_h / 2 + 17)}" font-family="{FONT}" font-size="12.5" '
                 f'fill="#E8EEFF">{esc(subtitle)}</text>')

    def flow(self, key, d, tone="blue", arrow=True, width=2.6, track=True, speed=0.5, active=None):
        """A connector with flowing dashes. Returns the path id, for packets.

        key : unique id. d : SVG path data, for example "M290 210 C310 210 310 260 330 260".
            Route connectors around cards, never through them.
        tone : a TONES name. arrow : arrow head at the end. width : stroke width in px.
        track : draw a soft wide track under the dashes.
        speed : seconds for the dashes to move one dash period; must divide the loop.
        active : windows when the dashes flow. Outside them the connector rests as a thin calm line
            with its arrow. Without active windows the connector flows all the time.
        """
        self._claim(f"p-{key}")
        self._period(speed, f"flow {key}: dash speed")
        strong, t1, t2, _ = TONES[tone]
        pid = f"p-{key}"
        F = self.layers["flows"]
        if track:
            F.append(f'<path d="{d}" fill="none" stroke="{t2}" stroke-width="{fmt(width + 3.4)}" stroke-linecap="round" '
                     f'stroke-linejoin="round" opacity="0.75"/>')
        marker = f' marker-end="url(#ar-{tone})"' if arrow else ""
        dash_anim = f'<animate attributeName="stroke-dashoffset" from="18" to="0" dur="{fmt(speed)}s" repeatCount="indefinite"/>'
        if active is None:
            F.append(f'<path id="{pid}" d="{d}" fill="none" stroke="{strong}" stroke-width="{fmt(width)}" stroke-linecap="round" '
                     f'stroke-linejoin="round" stroke-dasharray="9 9"{marker}>{dash_anim}</path>')
        else:
            F.append(f'<path d="{d}" fill="none" stroke="{strong}" stroke-opacity="0.42" stroke-width="1.5" stroke-linecap="round" '
                     f'stroke-linejoin="round"{marker}/>')
            F.append(f'<path id="{pid}" d="{d}" fill="none" stroke="{strong}" stroke-width="{fmt(width)}" stroke-linecap="round" '
                     f'stroke-linejoin="round" stroke-dasharray="9 9" opacity="0">{dash_anim}{self.tl.anim("opacity", active, 1, 0)}</path>')
        return pid

    def wire(self, d, color=INK3, width=1.6, dash=None, arrow=False):
        """A static line, for structure such as a tree or a "starts" arrow.

        d : SVG path data. color : stroke color. width : stroke width in px.
        dash : an SVG dash array such as "3 4", or None for a solid line. arrow : slate arrow head.
        """
        dsh = f' stroke-dasharray="{dash}"' if dash else ""
        mk = ' marker-end="url(#ar-slate)"' if arrow else ""
        self.layers["wires"].append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{fmt(width)}"{dsh}{mk} '
                                    f'stroke-linecap="round" stroke-linejoin="round"/>')

    # Packets are flat colors on purpose: soft gradients change many pixels per frame and bloat
    # the animated PNG. Each entry is (lag in seconds, radius factor, opacity).
    TRAIL = [(0.0, 1.0, 1.0), (0.07, 0.62, 0.45)]

    def packet_loop(self, path_id, dur, begin=0.0, tone="blue", r=5.5):
        """A comet that travels the whole path every `dur` seconds, forever.

        path_id : the id returned by flow(). dur : seconds per trip; must divide the loop.
        begin : offset in seconds, to stagger several packets (negative values are fine).
        tone : a TONES name. r : head radius in px.
        """
        self._period(dur, f"packet on {path_id}: dur")
        strong, t1, t2, _ = TONES[tone]
        out = []
        trail = [(lag, r * k, op) for lag, k, op in self.TRAIL]
        out.append(f'<circle r="{fmt(r * 1.9)}" fill="{strong}" opacity="0.18"><animateMotion dur="{fmt(dur)}s" '
                   f'begin="{fmt(begin - dur)}s" repeatCount="indefinite"><mpath href="#{path_id}"/></animateMotion></circle>')
        for lag, rr, op in reversed(trail):
            b = begin + lag - dur
            stroke = ' stroke="#FFFFFF" stroke-width="1.6"' if lag == 0 else ""
            out.append(f'<circle r="{fmt(rr)}" fill="{strong}" opacity="{fmt(op)}"{stroke}><animateMotion dur="{fmt(dur)}s" '
                       f'begin="{fmt(b)}s" repeatCount="indefinite"><mpath href="#{path_id}"/></animateMotion></circle>')
        self.layers["fx"].extend(out)

    def packet_once(self, path_id, start, travel, tone="blue", r=5.5):
        """A comet that appears at `start`, travels the path in `travel` seconds, then disappears.

        It repeats once per loop. start + travel must stay inside the loop (it raises ValueError
        when the packet would wrap; shift its start). Use it for one step of the story, together
        with the flow's active window.
        """
        strong = TONES[tone][0]
        L = self.loop
        out = []
        trail = [(lag, r * k, op) for lag, k, op in self.TRAIL]
        for lag, rr, op in reversed(trail):
            s = (start + lag) % L
            e = s + travel
            if e > L:
                raise ValueError(f"{self.name}: packet on {path_id} wraps the loop; shift its start")
            kt = f"0;{fmt(s / L)};{fmt(e / L)};1"
            motion = (f'<animateMotion dur="{fmt(L)}s" repeatCount="indefinite" calcMode="linear" keyPoints="0;0;1;1" '
                      f'keyTimes="{kt}"><mpath href="#{path_id}"/></animateMotion>')
            vis = (f'<animate attributeName="opacity" dur="{fmt(L)}s" repeatCount="indefinite" calcMode="discrete" '
                   f'keyTimes="0;{fmt(s / L)};{fmt(min(e / L + 0.004, 1))}" values="0;{fmt(op)};0"/>')
            stroke = ' stroke="#FFFFFF" stroke-width="1.6"' if lag == 0 else ""
            if lag == 0:
                out.append(f'<circle r="{fmt(r * 1.9)}" fill="{strong}" opacity="0">{motion}'
                           f'<animate attributeName="opacity" dur="{fmt(L)}s" repeatCount="indefinite" calcMode="discrete" '
                           f'keyTimes="0;{fmt(s / L)};{fmt(min(e / L + 0.004, 1))}" values="0;0.18;0"/></circle>')
            out.append(f'<circle r="{fmt(rr)}" fill="{strong}" opacity="0"{stroke}>{motion}{vis}</circle>')
        self.layers["fx"].extend(out)

    def pulse(self, cx, cy, r0, r1, tone="blue", period=2.0, begin=0.0, width=2.0):
        """Two expanding rings around (cx, cy), from radius r0 to r1, every `period` seconds.

        Use it to mark the heart of the diagram (the platform icon). period must divide the loop.
        begin : offset in seconds. width : ring stroke width.
        """
        self._period(period, "pulse period")
        strong = TONES[tone][0]
        for k in (0, 1):
            b = begin + k * period / 2 - period
            self.layers["fx"].append(
                f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r0)}" fill="none" stroke="{strong}" stroke-width="{fmt(width)}" opacity="0">'
                f'<animate attributeName="r" from="{fmt(r0)}" to="{fmt(r1)}" dur="{fmt(period)}s" begin="{fmt(b)}s" repeatCount="indefinite"/>'
                f'<animate attributeName="opacity" values="0.65;0" dur="{fmt(period)}s" begin="{fmt(b)}s" repeatCount="indefinite"/></circle>')

    def toast(self, x, y, w, text, wins, icon=None, tone="green", mark="check"):
        """A pop-up note, 30 px tall, that shows an event of the story during its windows.

        x, y, w : position and width. text : one short line (12 px bold).
        wins : windows when the note is visible. Several toasts can share one position if their
            windows do not overlap, to play a sequence of events in one place.
        icon : an icon key drawn at the left instead of the mark.
        tone : a TONES name. mark : "check", "alert" or "info".
        """
        strong, t1, t2, tink = TONES[tone]
        self._bounds(x, y, w, 30, f"toast '{text}'")
        g = [f'<g opacity="0">{self.tl.anim("opacity", wins, 1, 0, fade=0.2)}']
        g.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="30" rx="15" fill="#FFFFFF" stroke="{t2}" '
                 f'stroke-width="1.2" filter="url(#sh)"/>')
        if icon:
            g.append(f'<use href="#{self.symbol(icon)}" x="{fmt(x + 7)}" y="{fmt(y + 6)}" width="18" height="18"/>')
        else:
            g.append(f'<circle cx="{fmt(x + 16)}" cy="{fmt(y + 15)}" r="8" fill="{strong}"/>')
            if mark == "check":
                g.append(f'<path d="M{fmt(x + 12)} {fmt(y + 15)} l3 3 l5 -6" fill="none" stroke="#FFFFFF" stroke-width="1.8" '
                         f'stroke-linecap="round" stroke-linejoin="round"/>')
            elif mark == "alert":
                g.append(f'<path d="M{fmt(x + 16)} {fmt(y + 10)} v6" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round"/>'
                         f'<circle cx="{fmt(x + 16)}" cy="{fmt(y + 20)}" r="1.3" fill="#FFFFFF"/>')
            else:  # info
                g.append(f'<circle cx="{fmt(x + 16)}" cy="{fmt(y + 10.5)}" r="1.3" fill="#FFFFFF"/>'
                         f'<path d="M{fmt(x + 16)} {fmt(y + 14)} v6" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round"/>')
        self.check(text, 12, True, w - 40, "toast")
        g.append(f'<text x="{fmt(x + 32)}" y="{fmt(y + 19.5)}" font-family="{FONT}" font-size="12" font-weight="600" '
                 f'fill="{tink}">{esc(text)}</text>')
        g.append("</g>")
        self.layers["top"].append("".join(g))

    def badge(self, cx, cy, n, tone="blue", active=(), r=13):
        """A numbered circle at (cx, cy) that marks a step, with an optional halo during `active`.

        n : the number or short text. tone : a TONES name. r : radius in px.
        """
        strong = TONES[tone][0]
        if active:
            self.layers["fx"].append(
                f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r + 7)}" fill="{strong}" opacity="0">'
                f'{self.tl.anim("opacity", active, 0.22, 0)}</circle>')
        self.layers["top"].append(
            f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r)}" fill="{strong}" stroke="#FFFFFF" stroke-width="2"/>'
            f'<text x="{fmt(cx)}" y="{fmt(cy + 4.5)}" font-family="{FONT}" font-size="13" font-weight="700" fill="#FFFFFF" '
            f'text-anchor="middle">{esc(str(n))}</text>')

    def raw(self, svg, layer="top"):
        """Append raw SVG markup to a layer, for shapes the API does not cover (gauges, bars).

        Use d.tl.anim(...) for timing and d.symbol(key) for icons, and escape text with esc().
        """
        self.layers[layer].append(svg)

    def terminal(self, x, y, w, h, title, lines, note=None, prompt="PS> "):
        """A dark terminal window that types commands and prints their output.

        x, y, w, h : the window. title : the title bar text ("PowerShell 7 on the jump VM").
        note : small italic text at the right of the title bar; use "Illustrative output" when the
            output is not a literal capture.
        prompt : the prompt shown before commands, for example "PS> " or "$ ".
        lines : a list of (text, kind, start, type_seconds) tuples, one per line, top to bottom.
            kind "cmd" is typed character by character from `start` for `type_seconds` seconds;
            kinds "out" (gray), "ok" (green) and "warn" (yellow) appear at `start` at once
            (type_seconds is ignored). Lines stay until the loop restarts; a blinking prompt
            appears after the last line has printed. Each line is 21 px tall, and spaces are kept
            as typed, so aligned columns in illustrative output stay aligned.
        """
        self._bounds(x, y, w, h, f"terminal '{title}'")
        L = self.layers["cards"]
        L.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="12" fill="#0E1726" stroke="#1E2B3F" filter="url(#sh2)"/>')
        L.append(f'<path d="M{fmt(x)} {fmt(y + 12)} a12 12 0 0 1 12 -12 h{fmt(w - 24)} a12 12 0 0 1 12 12 v18 h{fmt(-w)} z" fill="#18243A"/>')
        for i, c in enumerate(("#FF5F57", "#FEBC2E", "#28C840")):
            L.append(f'<circle cx="{fmt(x + 18 + i * 16)}" cy="{fmt(y + 15)}" r="5" fill="{c}"/>')
        L.append(f'<text x="{fmt(x + w / 2)}" y="{fmt(y + 19.5)}" font-family="{FONT}" font-size="11.5" fill="#A9B8CC" '
                 f'text-anchor="middle">{esc(title)}</text>')
        if note:
            L.append(f'<text x="{fmt(x + w - 14)}" y="{fmt(y + 19.5)}" font-family="{FONT}" font-size="10.5" fill="#7C8BA1" '
                     f'text-anchor="end" font-style="italic">{esc(note)}</text>')
        lh = 21
        last_end = 0.0
        colors = {"cmd": "#E6EDF6", "out": "#9FB2C8", "ok": "#7EE2A8", "warn": "#FFD27A"}
        for i, (text, kind, start, typing) in enumerate(lines):
            if kind not in colors:
                raise ValueError(f"{self.name}: terminal line kind must be cmd, out, ok or warn, not '{kind}'")
            ty = y + 52 + i * lh
            body = (prompt + text) if kind == "cmd" else text
            end = start + (typing if kind == "cmd" else 0.0)
            if end > self.loop - 0.3:
                self._warn(f"terminal line '{text}' finishes at {fmt(end)} s, too close to the end of the {fmt(self.loop)} s loop")
            last_end = max(last_end, end)
            if mono_width(body, 12) > w - 32:
                self._warn(f"terminal line '{body}' may overflow the terminal ({mono_width(body, 12):.0f} > {w - 32:.0f})")
            if kind == "cmd":
                self._cmd_texts.append(text)
                cid = self._id("tc")
                full = len(body) * _TERM_CHAR + 24
                self.clips.append(
                    f'<clipPath id="{cid}"><rect x="{fmt(x + 14)}" y="{fmt(ty - 14)}" height="20" width="0">'
                    f'<animate attributeName="width" dur="{fmt(self.loop)}s" repeatCount="indefinite" calcMode="linear" '
                    f'keyTimes="0;{fmt(start / self.loop)};{fmt(end / self.loop)};1" values="0;0;{fmt(full)};{fmt(full)}"/></rect></clipPath>')
                L.append(f'<g clip-path="url(#{cid})"><text x="{fmt(x + 16)}" y="{fmt(ty)}" font-family="{MONO}" font-size="12" '
                         f'fill="{colors[kind]}" xml:space="preserve"><tspan fill="#5CC8FF">{esc(prompt)}</tspan>{esc(text)}</text></g>')
            else:
                L.append(f'<text x="{fmt(x + 16)}" y="{fmt(ty)}" font-family="{MONO}" font-size="12" fill="{colors[kind]}" opacity="0" '
                         f'xml:space="preserve">'
                         f'{self.tl.anim("opacity", [(start, self.loop - 0.05)], 1, 0, fade=0.08)}{esc(text)}</text>')
        # A blinking prompt under the last line, shown once everything has printed.
        cy = y + 52 + len(lines) * lh
        if cy + 8 > y + h:
            self._warn(f"terminal '{title}' has {len(lines)} lines, more than its {fmt(h)} px height holds")
        mark = prompt.rstrip() or ">"
        cursor_x = x + 16 + mono_width(mark, 12) + 14.4
        L.append(f'<g opacity="0">{self.tl.anim("opacity", [(last_end + 0.3, self.loop - 0.05)], 1, 0, fade=0.05)}'
                 f'<text x="{fmt(x + 16)}" y="{fmt(cy)}" font-family="{MONO}" font-size="12" fill="#5CC8FF">{esc(mark)}</text>'
                 f'<rect x="{fmt(cursor_x)}" y="{fmt(cy - 12)}" width="8" height="15" fill="#5CC8FF">'
                 f'<animate attributeName="opacity" dur="1s" repeatCount="indefinite" calcMode="discrete" keyTimes="0;0.5" values="1;0"/></rect></g>')
        self._period(1.0, "terminal cursor blink")

    # ==== Output ==============================================================================

    def _legend_items(self, legend, y):
        """Legend markup right-aligned at the footer and its total width."""
        lx = self.w - 36
        items = []
        for label, tone, kind in reversed(legend):
            tw = text_width(label, 11.5) + 8
            lx -= tw
            items.append(f'<text x="{fmt(lx)}" y="{y}" font-family="{FONT}" font-size="11.5" fill="{INK2}">{esc(label)}</text>')
            lx -= 30
            strong = TONES[tone][0]
            if kind == "flow":
                items.append(f'<path d="M{fmt(lx)} {y - 4} h24" stroke="{strong}" stroke-width="2.6" stroke-dasharray="6 5" stroke-linecap="round"/>')
            elif kind == "dot":
                items.append(f'<circle cx="{fmt(lx + 12)}" cy="{y - 4}" r="5" fill="{strong}" stroke="#FFFFFF" stroke-width="1.5"/>')
            else:  # box
                items.append(f'<rect x="{fmt(lx + 2)}" y="{y - 12}" width="20" height="14" rx="4" fill="none" stroke="{strong}" stroke-width="2.2"/>')
            lx -= 16
        return items, (self.w - 36) - lx

    def render(self, caption: str | None = None, legend=None) -> str:
        """Return the complete SVG document as a string.

        caption : the "Key idea" sentence (defaults to self.caption).
        legend : optional list of (label, tone, kind) shown at the right of the footer, where kind
            is "flow" (a dashed line), "dot" (a packet) or "box" (a card outline). Defaults to
            self.legend.
        """
        caption = caption if caption is not None else self.caption
        legend = legend if legend is not None else self.legend
        if not caption:
            raise ValueError(f"{self.name}: every diagram needs a Key idea caption (pass caption or set d.caption)")
        W, H = self.w, self.h
        defs = ['<filter id="sh" x="-10%" y="-10%" width="120%" height="140%"><feDropShadow dx="0" dy="2" stdDeviation="3" '
                'flood-color="#0F1E2E" flood-opacity="0.10"/></filter>',
                '<filter id="sh2" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="0" dy="6" stdDeviation="9" '
                'flood-color="#0F1E2E" flood-opacity="0.13"/></filter>',
                '<filter id="blur" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="4"/></filter>',
                '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/>'
                '<stop offset="1" stop-color="#F7F9FC"/></linearGradient>',
                '<pattern id="dots" width="22" height="22" patternUnits="userSpaceOnUse"><circle cx="2" cy="2" r="1" fill="#E3E8EE"/></pattern>']
        for name, (strong, t1, t2, _) in TONES.items():
            defs.append(f'<marker id="ar-{name}" markerUnits="userSpaceOnUse" markerWidth="11" markerHeight="11" refX="9" refY="5.5" orient="auto">'
                        f'<path d="M0,0 L11,5.5 L0,11 L2.5,5.5 z" fill="{strong}"/></marker>')
            defs.append(f'<radialGradient id="halo-{name}"><stop offset="0" stop-color="{strong}" stop-opacity="0.45"/>'
                        f'<stop offset="1" stop-color="{strong}" stop-opacity="0"/></radialGradient>')
        defs.extend(self.clips)
        defs.extend(self.icons.values())
        tag_w = text_width(self.tag, 11, True) * 1.12 + 26
        blue = TONES["blue"]
        head = [
            f'<rect x="0.5" y="0.5" width="{W - 1}" height="{H - 1}" rx="20" fill="url(#bg)" stroke="#E1E7ED"/>',
            f'<rect x="0.5" y="0.5" width="{W - 1}" height="{H - 1}" rx="20" fill="url(#dots)" opacity="0.55"/>',
            f'<text x="36" y="50" font-family="{FONT}" font-size="24" font-weight="700" fill="{INK}">{esc(self.title)}</text>',
            f'<text x="36" y="75" font-family="{FONT}" font-size="13.5" fill="{INK2}">{esc(self.subtitle)}</text>',
            f'<rect x="{fmt(W - 36 - tag_w)}" y="30" width="{fmt(tag_w)}" height="26" rx="13" fill="{blue[1]}" stroke="{blue[2]}"/>',
            f'<text x="{fmt(W - 36 - tag_w / 2)}" y="47.5" font-family="{MONO}" font-size="11" font-weight="700" letter-spacing="1.2" '
            f'fill="{blue[0]}" text-anchor="middle">{esc(self.tag)}</text>',
        ]
        self.check(self.title, 24, True, W - 72 - tag_w - 20, "the title")
        self.check(self.subtitle, 13.5, False, W - 72, "the subtitle")
        foot = [f'<line x1="36" y1="{H - 46}" x2="{W - 36}" y2="{H - 46}" stroke="#E1E7ED"/>',
                f'<text x="36" y="{H - 21}" font-family="{FONT}" font-size="12.5" fill="{INK2}"><tspan font-weight="700" '
                f'fill="{blue[0]}">Key idea </tspan>{esc(caption)}</text>']
        legend_w = 0.0
        if legend:
            items, legend_w = self._legend_items(legend, H - 21)
            foot.extend(items)
        self.check("Key idea " + caption, 12.5, False, W - 72 - (legend_w + 24 if legend else 0), "the caption")
        body = []
        for layer in LAYERS:
            body.extend(self.layers[layer])
        return (f'<svg xmlns="http://www.w3.org/2000/svg" data-loop-seconds="{fmt(self.loop)}" data-frames-per-second="{self.fps}" '
                f'viewBox="0 0 {W} {H}" width="{W}" height="{H}" font-family="{FONT}" role="img" aria-label="{esc(self.aria)}">\n'
                f'<title>{esc(self.title)}</title>\n<defs>\n' + "\n".join(defs) + "\n</defs>\n" +
                "\n".join(head) + "\n" + "\n".join(body) + "\n" + "\n".join(foot) + "\n</svg>\n")

    def save(self, out_dir: Path, caption: str | None = None, legend=None) -> Path:
        """Render the diagram and write <out_dir>/<name>.svg (UTF-8). Returns the path.

        Raises ValueError, and writes nothing, when the text contains an em dash, an en dash or a
        spaced double hyphen. Typed terminal commands are exempt from the double hyphen check,
        because there it is command syntax.
        """
        svg = self.render(caption, legend)
        for ch, label in ((_EM_DASH, "an em dash (U+2014)"), (_EN_DASH, "an en dash (U+2013)")):
            if ch in svg:
                at = svg.index(ch)
                raise ValueError(f"{self.name}: {label} found near '{svg[max(0, at - 40):at + 40]}'; house style forbids it")
        checked = svg
        for cmd in self._cmd_texts:
            checked = checked.replace(esc(cmd), "")
        m = _SPACED_DOUBLE_HYPHEN.search(checked)
        if m:
            at = m.start()
            raise ValueError(f"{self.name}: spaced double hyphen found near '{checked[max(0, at - 40):at + 40]}'; "
                             "use a comma, colon or full stop")
        out = Path(out_dir)
        out.mkdir(parents=True, exist_ok=True)
        path = out / f"{self.name}.svg"
        path.write_text(svg, encoding="utf-8", newline="\n")
        return path
