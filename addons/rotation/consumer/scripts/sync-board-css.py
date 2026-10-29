"""Generate board/static/tokens.css from the console's ui/app/assets/css/main.css.

The Secure Door board is a separate, dependency-free page but the same design
system (Vault daylight glass). Rather than hand-copying tokens that would drift,
this extracts the token layer, the hero's ink re-scope and the shared
primitives verbatim. `make rotation-validate` runs it with --check.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
SRC = ROOT / "ui/app/assets/css/main.css"
OUT = ROOT / "addons/rotation/consumer/board/static/tokens.css"

# Top-level rules copied verbatim, in source order (selector prefix match).
KEEP = (":root", ".vg-hero", "*, *::before", "html, body", "body", "*:focus-visible", ".skip-link",
        "@media (prefers-reduced-motion", "a ", "a:hover", ".vg-glass", ".vg-pill", ".door-chip",
        ".vg-table", ".panel", ".panel-head", ".inline-notice", ".vg-kpi", ".eyebrow", ".hero-status",
        ".source-tag", ".mono")


def rules(css: str):
    """Yield (selector, full_text) for every top-level rule or at-rule block."""
    i, n = 0, len(css)
    while i < n:
        j = css.find("{", i)
        if j < 0:
            return
        selector = css[i:j].strip()
        depth, k = 0, j
        while k < n:
            if css[k] == "{":
                depth += 1
            elif css[k] == "}":
                depth -= 1
                if depth == 0:
                    break
            k += 1
        yield selector, css[i:k + 1].strip()
        i = k + 1


def build() -> str:
    css = re.sub(r"/\*.*?\*/", "", SRC.read_text(), flags=re.S)
    css = re.sub(r"^@import[^;]*;", "", css, flags=re.M)
    out = ["/* GENERATED from ui/app/assets/css/main.css by sync-board-css.py — do not edit. */",
           "@font-face { font-family: 'Hanken Grotesk Variable'; src: url('/fonts/hanken-grotesk.woff2') format('woff2-variations'); font-weight: 100 900; font-display: swap; }",
           "@font-face { font-family: 'JetBrains Mono Variable'; src: url('/fonts/jetbrains-mono.woff2') format('woff2-variations'); font-weight: 100 800; font-display: swap; }",
           ":root { --font-sans: 'Hanken Grotesk Variable', ui-sans-serif, system-ui, sans-serif; --font-mono: 'JetBrains Mono Variable', ui-monospace, 'SF Mono', monospace; }"]
    for selector, text in rules(css):
        if selector.startswith("@theme"):
            continue
        if any(selector == k or selector.startswith(k) for k in KEEP):
            out.append(text)
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    generated = build()
    if "--check" in sys.argv:
        current = OUT.read_text() if OUT.exists() else ""
        if current != generated:
            print("board tokens.css is out of date with ui/app/assets/css/main.css — run sync-board-css.py")
            sys.exit(1)
        print("board tokens.css matches main.css")
    else:
        OUT.write_text(generated)
        print(f"wrote {OUT.relative_to(ROOT)} ({len(generated)} bytes)")
