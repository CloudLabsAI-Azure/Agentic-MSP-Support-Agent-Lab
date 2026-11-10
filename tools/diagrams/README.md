# Animated Lab Diagrams Toolkit

Every v2 lab explains its architecture and each exercise's mechanism with an animated diagram: official Microsoft product icons on a Fluent palette, flowing connectors, moving packets, step glows, pop-up notes and typing terminals. Diagrams are written as code, so they can be rebuilt when the lab changes, reviewed as text, and kept consistent across labs.

Lab authors copy the `diagrams` and `qa` folders from the CloudLabs Lab Builder plugin's `assets/tools/` into the lab repository's `tools/` folder, so this toolkit lives in `tools/diagrams/` and every command below runs from the lab repository root.

## What is in this folder

| File | What it does |
|---|---|
| `svgkit.py` | The design system and the Diagram API: lanes, cards, hero containers, flows, packets, pulses, toasts, badges, terminals, and the timeline that drives them. Its docstrings document every method and the timing model. Standard library only. |
| `build_diagrams_example.py` | A complete example for a fictional Contoso lab: an architecture diagram and a five-step concept flow with a typing terminal. Copy it to `build_diagrams.py` and replace the diagrams. |
| `Get-ProductIcons.ps1` | Downloads the official Microsoft icon packs to a cache outside the repository and stages the icons the diagrams use, by key, into `icons/`. |
| `Render-Diagrams.ps1` | Renders each SVG to a verified animated PNG (APNG) with headless Microsoft Edge or Chrome, and captures review stills. |
| `.gitignore` | Keeps the staged `icons/` folder and Python caches out of the repository. |

## How it works end to end

1. **Fetch the icons once per machine.** The packs are cached in your local application data folder and only the SVG files are extracted. The staged `icons/` folder is git-ignored.

   ```powershell
   pwsh tools/diagrams/Get-ProductIcons.ps1 -IconsPath tools/diagrams/icons
   pwsh tools/diagrams/Get-ProductIcons.ps1 -ListKeys          # the keys diagrams can use
   pwsh tools/diagrams/Get-ProductIcons.ps1 -Find 'key vault'  # locate an icon to add to the map
   ```

   To add an icon, run `-Find`, paste the printed row into `$IconMap` at the top of the script (or add a name to a concept list in `$ConceptSets`), and run the first command again.

2. **Author the diagrams in Python.** Copy `build_diagrams_example.py` to `tools/diagrams/build_diagrams.py`. Write one function per diagram that returns a `Diagram`, and register it in `DIAGRAMS`. Use the lab's real names: objects, commands, and an example Deployment ID such as 123456.

3. **Build the SVG files.** The script writes `Instructions/media/<name>.svg` and prints a `WARN` line for every text that may overflow, every element outside the canvas and every timing that does not divide the loop. Fix every warning; the script exits with code 1 while any remain.

   ```powershell
   python tools/diagrams/build_diagrams.py                 # every diagram
   python tools/diagrams/build_diagrams.py architecture    # one diagram
   ```

4. **Review stills.** Capture a few time points and look at them as images for overlaps, clipped text, connectors that cross cards, and legibility at guide width. Stills go to the system temp folder, never to the media folder.

   ```powershell
   pwsh tools/diagrams/Render-Diagrams.ps1 -Name architecture -Snapshot 0, 2.5, 7.5
   ```

5. **Render the animated PNG files.** One run renders 120 frames per diagram in batches of 12 per browser launch, packs them into `Instructions/media/<name>.png`, decodes the file again and fails unless every frame is within the tolerance. Expect about three to four minutes per diagram; run up to three renders in parallel, one `-Name` each.

   ```powershell
   pwsh tools/diagrams/Render-Diagrams.ps1 -Name architecture
   pwsh tools/diagrams/Render-Diagrams.ps1                 # every diagram in Instructions/media
   ```

6. **Embed them.** Guide pages embed the PNG, because some renderers serve SVG as text. Write alt text that describes the flow, and follow every embed with a paragraph that starts "How to read this diagram:". The repository README embeds the SVG files in a Diagram Gallery section, because GitHub animates SVG and every source is then referenced.

   ```markdown
   ![Five steps from az login to a live site, with the resources each command creates](./media/exercise-2-deploy.png)

   How to read this diagram: the numbered steps across the top are the order of this exercise. The terminal types each command, and the resources appear on the right as each command finishes.
   ```

7. **Commit** the SVG and PNG files and `build_diagrams.py`. Never commit the icon packs or the staged icons: every diagram embeds the icons it uses as data URIs, so the SVG and PNG files are self-contained. When the lab changes a name or a behavior that a diagram shows, change `build_diagrams.py`, rebuild and re-render in the same commit.

## Design rules

- **The set:** one concept diagram per exercise, the architecture diagram (getting-started page and README), and a session journey diagram for instructor-led labs (agenda, getting-started page and README).
- **Canvas and timing:** 1200 by 675 pixels, a 10-second loop at 12 frames per second (120 frames). Every repeating animation period must divide the loop; `svgkit` warns when one does not.
- **Self-explanatory:** every diagram has a title that states what to understand, a one-sentence subtitle, a tag pill (`GETTING STARTED`, `EXERCISE 3`, `AGENDA`) and a "Key idea" caption, plus a full `aria` description for screen readers. Before you draw, finish this sentence: "After ten seconds of watching, the learner understands that ...".
- **Palette:** Fluent tones only, from `TONES` in `svgkit.py`. A useful convention: blue for the main flow, purple for security and governance, teal for the learner's own resources and data, green for success, amber for cost and warnings, red for a blocked or failed path, slate for the platform and neutral parts.
- **Icons:** official Microsoft product icons, unaltered, with the product name next to each one; Microsoft 365 concept icons (`c-` and `p-` keys) for generic ideas such as a person, a script or a document.
- **Animate meaning, not decoration:** connectors flow during the step that uses them (`flow(..., active=...)`), packets show data in motion, glows walk through the sequence, toasts announce events, and CLI labs get a typing terminal labeled "Illustrative output".
- **Layout:** lanes group related cards, connectors never cross a card, and many sources merge into one trunk.
- **Text:** short, US English, no em dashes, en dashes or spaced double hyphens; `save()` refuses to write a diagram that has one.
- **The first frame:** viewers that do not play APNG (Word, PDF export, some previews) show the frame at time 0, so keep the static parts (cards, lanes, the caption) readable on their own.

## The timing model in brief

`svgkit.py` documents the details. Highlights take windows, lists of `(start, end)` seconds inside the loop; an end past the loop wraps around, and overlapping windows merge. Card glows, badge halos, appearing cards and toasts fade in and out at the window edges. A flow with `active` windows rests as a thin line and flows only inside them. `packet_loop` repeats every `dur` seconds, which must divide the loop; `packet_once` must start and finish inside one loop. The renderer samples the second loop, so animations that begin late are already running in every frame.

## Size budget

Aim for under 2.5 MB per PNG; the renderer warns above that. The example diagrams render to about 1.8 MB (architecture) and 1.0 MB (exercise flow) at the default scale of 1.2 (1440 by 810 pixels). Each frame after the first stores only the rectangle of pixels that changed, so the size grows with how much of the canvas moves at once. To shrink a diagram:

- Use active-step flows instead of connectors that flow all the time.
- Keep glow windows and simultaneous animations few, and avoid animating large areas.
- Keep packets flat: soft gradients change many pixels in every frame.
- Render at `-Scale 1.0` as a last resort.

The renderer prints sizes in bytes with comma grouping and in MB. Some locales group digits differently (1,31,31,595 bytes is 13 MB, not 1.3 MB), so read the MB figure.

## Why the renderer uses a tolerance

Edge rasterizes identical static content with differences of one to three levels per color channel between frames rendered in one batch, mostly in gradients, shadows and the dotted background. Without a tolerance that noise is stored as change in every frame, and a diagram that should be 1 to 2 MB grows to 5 to 13 MB. The encoder compares each new frame with the canvas the viewer already shows, not with the previous screenshot, so the error of every pixel stays within the tolerance (4 levels by default, which is invisible) for the whole loop instead of accumulating. The verification step checks exactly that. Use `-Tolerance 0` for an exact encoding.

Each batched copy of the SVG gets its own element ids. Without that, references such as a typing terminal's clip path resolve into the first copy on the page, and typed text advances only once per batch. Renders made before this fix show typing that jumps once a second; render them again.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Icon 'x' not found in ...` when building | The key is not staged | Run `Get-ProductIcons.ps1`; if the key is new, add it to the map first |
| `Not found in the current packs: ...` from `Get-ProductIcons.ps1` | Microsoft renamed or moved the icon in a new pack version | Run `-Find` with the product name and update the row |
| A pack download fails | The download URL changed | Get the current link from the pack's download page (in the script's help), update `$Packs`, run with `-Refresh` |
| `WARN ... may overflow` | The text is wider than its card, lane, toast or terminal | Shorten the text, widen the element, or lower `title_size` |
| `save()` raises `ValueError` naming an em dash, an en dash or a spaced double hyphen | The diagram text holds one | Rewrite with a comma, colon or full stop |
| `ValueError: packet on ... wraps the loop` | `start + travel` passes the end of the loop | Start the packet earlier |
| `ValueError: ... used twice` | Two cards, heroes or flows share a key | Give each a unique key |
| The animation jumps at the end of the loop | A period does not divide the loop | Fix the timing that `svgkit` warned about |
| `Microsoft Edge or Google Chrome was not found` | The browser is not in a standard location | Pass `-EdgePath` |
| `the browser wrote no screenshot after three attempts` | The browser could not start or write to the temp folder | Read the error text it prints, close stray headless browser processes, and try `-Batch 4` |
| `width or height x scale is not a whole number` | The scale makes frames land between pixels | Use a scale such as 1.0, 1.2 or 1.6 (675 times the scale must be whole) |
| `failed verification` | A frame differs from its screenshot beyond the tolerance | Render again; if it repeats, render with `-Batch 1` |
| The guide shows SVG source as text | The page embeds the SVG | Embed the PNG in guide pages and keep the SVG for the README |
| Word or a PDF shows a still image | Those viewers do not play APNG | Expected; browsers and GitHub play it |

## Microsoft icon terms

Microsoft permits its architecture icons in diagrams, training materials and documentation. Use them unaltered (no cropping, flipping, rotating, distorting or recoloring), show the product name near each product icon, and never use them to represent your own product. The terms are on each download page and in the packs:

- [Azure architecture icons](https://learn.microsoft.com/azure/architecture/icons/)
- [Microsoft Entra architecture icons](https://learn.microsoft.com/entra/architecture/architecture-icons)
- [Power Platform icons](https://learn.microsoft.com/power-platform/guidance/icons), which include Copilot Studio and Microsoft Agent 365
- [Microsoft 365 architecture icons and templates](https://learn.microsoft.com/microsoft-365/solutions/architecture-icons-templates), the source of the concept icons

The QA tools that check diagrams and the rest of the lab are described in [the QA tools README](../qa/README.md).
