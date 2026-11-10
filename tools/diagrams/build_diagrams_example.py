"""A complete example of a lab's diagram build script, for a fictional Contoso lab.

Copy this file to tools/diagrams/build_diagrams.py in a lab repository and replace the two
diagram functions with the lab's own: one function per diagram, registered in DIAGRAMS.

    architecture       the lab environment: the learner, the jump VM and its tools, the shared
                       cloud tenant and the learner's resource group, with one pop-up note per lab
    exercise-2-deploy  a concept flow: five numbered steps with active-step connectors, a terminal
                       that types the commands, and the resources that appear as each one runs

Usage (from the lab repository root, after staging the icons once):
    pwsh tools/diagrams/Get-ProductIcons.ps1 -IconsPath tools/diagrams/icons
    python tools/diagrams/build_diagrams.py [name ...] [--out FOLDER] [--icons FOLDER]
    pwsh tools/diagrams/Render-Diagrams.ps1 -Name <name>

Arguments:
    name       diagrams to build (default: all of them)
    --out      folder for the SVG files (default: Instructions/media in the lab repository that
               holds this script, that is ../../Instructions/media from tools/diagrams)
    --icons    folder with the staged icons (default: the icons folder next to this script)

The script prints every warning from svgkit (text that may overflow, elements outside the canvas,
timings that do not divide the loop) and exits with code 1 when there is one, so fix them all.
It uses only icon keys that Get-ProductIcons.ps1 stages by default. Requires Python 3.11+.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from svgkit import Diagram, TONES, fmt

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
DEFAULT_OUT = REPO / "Instructions" / "media"
DEFAULT_ICONS = HERE / "icons"


# =============================================================================
# Getting started: the lab environment
# =============================================================================
def architecture(icons: Path) -> Diagram:
    d = Diagram(
        "architecture",
        title="Your lab environment at a glance",
        subtitle="You work from a Windows jump VM in your browser. From it you reach the shared Contoso cloud tenant "
                 "and your own Azure resource group.",
        tag="GETTING STARTED",
        aria=("The learner opens the CloudLabs lab guide and a Windows jump VM side by side in the browser. The jump VM has "
              "Microsoft Edge, Visual Studio Code, the Azure CLI and PowerShell 7, Git with the .NET 8 SDK, and the lab files "
              "in C:\\LabFiles. From the VM the learner uses the shared Contoso cloud tenant, with Microsoft Entra ID, "
              "Microsoft Defender for Cloud and Azure Policy, and their own Azure resource group with Azure App Service, "
              "Azure SQL Database, Azure Key Vault and Application Insights. Pop-up notes show what each of the four labs uses."),
        icons_dir=icons, loop=10, fps=12)

    # Left column: the learner and the platform that starts the lab.
    d.card("you", 36, 150, 254, 120, "You", ["Lab guide and jump VM", "open side by side", "Credentials: Environment tab"],
           icon="c-laptop", tone="blue", icon_size=40, title_size=16)
    d.card("cl", 36, 300, 254, 84, "CloudLabs", ["Starts and secures", "your lab environment"],
           icon="c-cloud-desktop", tone="slate", icon_size=34)
    d.wire("M163 270 V300", color="#9AA7B4", width=1.8, arrow=True)

    # Middle: the jump VM and its tools. Each lab lights up the tools it uses.
    d.hero("vm", 330, 118, 270, 488, "Jump VM", "Windows Server 2022", "vm", header_h=80, tone_a="#0078D4", tone_b="#0F6CBD")
    d.pulse(374, 158, 26, 44, tone="blue", period=2.0)
    lab1, lab2, lab3, lab4 = (0.0, 2.5), (2.5, 5.0), (5.0, 7.5), (7.5, 10.0)
    tools = [("t1", "c-globe", "Microsoft Edge", "Azure portal, the web app", [lab3, lab4]),
             ("t2", "c-code", "Visual Studio Code", "Edit the Contoso web app", [lab2]),
             ("t3", "c-script", "Azure CLI, PowerShell 7", "Deploy and inspect", [lab1]),
             ("t4", "c-window-dev-edit", "Git, .NET 8 SDK", "Build and test locally", [lab3]),
             ("t5", "c-folder-open", "C:\\LabFiles", "App code and sample data", [lab1])]
    for i, (key, icon, title, line, glow) in enumerate(tools):
        d.card(key, 344, 214 + i * 64, 242, 54, title, [line], icon=icon, tone="blue", icon_size=26, title_size=13, glow=glow)

    # Right: the shared tenant (three services) and the learner's own resource group.
    d.lane(632, 118, 532, 214, "CONTOSO CLOUD TENANT, SHARED")
    d.card("ent", 644, 136, 250, 84, "Microsoft Entra ID", ["Your lab user and roles"], icon="entra-id", tone="blue",
           icon_size=30, title_size=13, glow=[lab2])
    d.card("def", 902, 136, 250, 84, "Defender for Cloud", ["Secure score, findings"], icon="defender-for-cloud",
           tone="purple", icon_size=30, title_size=13, glow=[lab4])
    d.card("pol", 644, 230, 508, 84, "Azure Policy", ["Lab guardrails: allowed regions and VM sizes"], icon="policy",
           tone="slate", icon_size=30, title_size=13, glow=[lab4])

    d.lane(632, 372, 532, 234, "YOUR AZURE RESOURCE GROUP")
    resources = [("app", 644, 390, "app-service", "Azure App Service", "Hosts the Contoso web app", [lab1]),
                 ("sql", 902, 390, "sql-database", "Azure SQL Database", "Orders and products", [lab1]),
                 ("kv", 644, 496, "key-vault", "Azure Key Vault", "Connection secrets", [lab2]),
                 ("ai", 902, 496, "app-insights", "Application Insights", "Requests and failures", [lab3])]
    for key, x, y, icon, title, line, glow in resources:
        d.card(key, x, y, 250, 96, title, [line], icon=icon, tone="teal", icon_size=32, title_size=13, glow=glow)

    # Connectors that always flow, with packets staggered so they never move in step.
    p1 = d.flow("a1", "M290 210 C310 210 310 260 330 260", tone="blue")
    d.packet_loop(p1, dur=2.5, begin=0.0, tone="blue")
    p2 = d.flow("a2", "M600 250 C616 250 616 225 632 225", tone="purple")
    d.packet_loop(p2, dur=2.5, begin=-1.2, tone="purple")
    p3 = d.flow("a3", "M600 520 C616 520 616 491 632 491", tone="teal")
    d.packet_loop(p3, dur=2.5, begin=-0.6, tone="teal")

    # One pop-up note per lab, all in one place, so the diagram plays the lab sequence.
    for text, win in [("Lab 1: deploy the web app", lab1),
                      ("Lab 2: secrets in Key Vault", lab2),
                      ("Lab 3: add Application Insights", lab3),
                      ("Lab 4: fix Defender findings", lab4)]:
        d.toast(342, 548, 246, text, [win], tone="blue", mark="info")

    d.caption = "Everything you need is installed on the jump VM, and each lab adds one piece to your own resource group."
    d.legend = [("Data in motion", "blue", "dot"), ("Connection", "blue", "flow")]
    return d


# =============================================================================
# Exercise 2: deploy the web app with the Azure CLI
# =============================================================================
def exercise_2_deploy(icons: Path) -> Diagram:
    d = Diagram(
        "exercise-2-deploy",
        title="Deploy the Contoso web app with the Azure CLI",
        subtitle="Five commands take the app from source to a live site. Each one creates or changes one resource in your group.",
        tag="EXERCISE 2",
        aria=("Five steps: sign in with az login, provision an App Service plan and a web app, configure the app settings with a "
              "Key Vault reference, deploy the code from C:\\LabFiles, and verify the live site. A terminal types each command "
              "with illustrative output, and the resources appear in your resource group as each command finishes: the plan, "
              "the web app, the app settings and the deployment."),
        icons_dir=icons, loop=10, fps=12)

    # The steps of the story: (key, icon, title, lines, tone, window when the step plays).
    steps = [("st1", "c-key", "Sign in", ["az login with your", "lab account"], "blue", (0.2, 1.6)),
             ("st2", "c-layer-diagonal", "Provision", ["App Service plan", "and web app"], "blue", (1.6, 4.0)),
             ("st3", "c-settings", "Configure", ["App settings with a", "Key Vault reference"], "purple", (4.0, 5.6)),
             ("st4", "c-deploy", "Deploy", ["Zip deploy from", "C:\\LabFiles"], "teal", (5.6, 7.8)),
             ("st5", "c-checkmark-circle", "Verify", ["Browse the site and", "read the response"], "green", (7.8, 9.8))]
    xs = [36, 266, 496, 726, 956]
    for i, ((key, icon, title, lines, tone, win), x) in enumerate(zip(steps, xs)):
        d.card(key, x, 128, 208, 104, title, lines, icon=icon, tone=tone, icon_size=30, title_size=15, glow=[win])
        d.badge(x + 194, 134, i + 1, tone=tone, active=[win])
        # A check mark that appears when the step is done and stays until the loop restarts (raw SVG).
        cx, cy = x + 188, 214
        d.raw(f'<g opacity="0">{d.tl.anim("opacity", [(win[1], 9.9)], 1, 0, fade=0.12)}'
              f'<circle cx="{cx}" cy="{cy}" r="8" fill="{TONES["green"][0]}"/>'
              f'<path d="M{fmt(cx - 3.6)} {cy} l2.6 2.8 l4.8 -5.4" fill="none" stroke="#FFFFFF" stroke-width="1.8" '
              f'stroke-linecap="round" stroke-linejoin="round"/></g>', layer="top")
    # Active-step connectors: each one flows only while the next step starts.
    for i in range(4):
        x0 = xs[i] + 208
        tone, win = steps[i + 1][4], steps[i + 1][5]
        pid = d.flow(f"step{i}", f"M{x0} 180 H{x0 + 22}", tone=tone, active=[(win[0] - 0.3, win[0] + 0.5)])
        d.packet_once(pid, start=win[0] - 0.25, travel=0.35, tone=tone)

    # The terminal types the commands; the output is illustrative, and the terminal says so.
    d.terminal(36, 272, 620, 330, "PowerShell 7 on the jump VM", [
        ("az login", "cmd", 0.3, 0.4),
        ("Signed in to the Contoso lab subscription", "ok", 1.0, 0),
        ("az appservice plan create -n plan-contoso --sku B1", "cmd", 1.7, 0.9),
        ("Plan plan-contoso created (B1, Linux)", "ok", 2.8, 0),
        ("az webapp create -n app-contoso-123456 -p plan-contoso", "cmd", 3.0, 0.8),
        ("Web app app-contoso-123456 created", "ok", 4.0, 0),
        ("az webapp config appsettings set --settings @app.json", "cmd", 4.2, 0.9),
        ("Key Vault reference resolved for SQL_CONNECTION", "ok", 5.3, 0),
        ("az webapp deploy --src-path C:\\LabFiles\\app.zip", "cmd", 5.8, 0.9),
        ("Deployment succeeded", "ok", 7.0, 0),
        ("az webapp browse -n app-contoso-123456", "cmd", 7.9, 0.7),
        ("HTTP 200 from app-contoso-123456.azurewebsites.net", "out", 8.8, 0),
    ], note="Illustrative output")

    # The resources appear when the command that creates them finishes, and glow briefly.
    d.lane(692, 290, 472, 316, "CREATED IN YOUR RESOURCE GROUP")
    objs = [("o1", "app-service-plan", "plan-contoso", "App Service plan, B1 on Linux", 2.8),
            ("o2", "app-service", "app-contoso-123456", "Azure App Service web app", 4.0),
            ("o3", "key-vault", "App settings", "Key Vault reference, no secret in code", 5.3),
            ("o4", "c-deploy", "Deployment", "Built from C:\\LabFiles\\app.zip", 7.0)]
    for i, (key, icon, title, line, t) in enumerate(objs):
        d.card(key, 708, 308 + i * 66, 440, 58, title, [line], icon=icon, tone="teal", icon_size=30, title_size=14,
               title_mono=i < 2, appear=[(t, 9.9)], glow=[(t, t + 0.9)])
    d.toast(708, 572, 440, "Site is live: HTTP 200", [(8.9, 9.9)], tone="green", mark="check")

    d.caption = ("Every command targets your own resource group, and the web app reads its secrets from Key Vault, "
                 "never from code.")
    return d


DIAGRAMS = {
    "architecture": architecture,
    "exercise-2-deploy": exercise_2_deploy,
}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Build the example Contoso lab diagrams as animated SVG files.")
    parser.add_argument("names", nargs="*", metavar="name", help=f"diagrams to build (default: all): {', '.join(DIAGRAMS)}")
    parser.add_argument("--out", type=Path, help="folder for the SVG files (default: Instructions/media in the lab repository)")
    parser.add_argument("--icons", type=Path, default=DEFAULT_ICONS, help="folder with the staged icons (default: icons next to this script)")
    args = parser.parse_args(argv)

    unknown = [n for n in args.names if n not in DIAGRAMS]
    if unknown:
        parser.error(f"unknown diagram(s): {', '.join(unknown)}; choose from {', '.join(DIAGRAMS)}")
    out = args.out
    if out is None:
        # Only default into a lab repository, never into the toolkit's own folder.
        if not ((REPO / "masterdoc.json").exists() or (REPO / "Instructions").is_dir()):
            parser.error(f"{REPO} is not a lab repository (no masterdoc.json or Instructions folder); pass --out")
        out = DEFAULT_OUT
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
