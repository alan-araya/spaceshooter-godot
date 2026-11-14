"""Gera um PDF de um .md de docs/ (com as imagens) usando o Chrome/Edge sem janela.

    python -I -X utf8 tools/build_pdf.py [docs/DEVELOPMENT_JOURNEY.md]

Saída: o mesmo caminho com .pdf. Precisa do pacote `markdown` e do Chrome ou Edge instalado.
"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parent.parent
BROWSERS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]

CSS = """
@page { size: A4; margin: 16mm 15mm 18mm 15mm; }
body { font-family: 'Segoe UI', 'Noto Sans', Arial, sans-serif; font-size: 10.5pt; line-height: 1.5;
       color: #1d1a20; max-width: 100%; }
h1 { font-size: 22pt; color: #2a1f2e; border-bottom: 3px solid #d9a24a; padding-bottom: 6px; margin-top: 0; }
h2 { font-size: 15pt; color: #2a1f2e; border-bottom: 1px solid #d8cbb5; padding-bottom: 3px;
     margin-top: 26px; break-after: avoid; }
h3 { font-size: 12pt; color: #6b4a2a; break-after: avoid; }
a { color: #9a3d8a; text-decoration: none; }
img { max-width: 100%; max-height: 120mm; display: block; margin: 10px auto 2px; border-radius: 4px;
      break-inside: avoid; }
p:has(> img) { break-inside: avoid; }
em { color: #555; }
blockquote { border-left: 4px solid #d9a24a; margin: 10px 0; padding: 4px 12px; background: #faf5ec; color: #444; }
code { font-family: Consolas, 'Cascadia Mono', monospace; font-size: 9pt; background: #f3eee6;
       padding: 1px 4px; border-radius: 3px; }
pre { background: #f3eee6; padding: 8px 10px; border-radius: 4px; overflow-wrap: anywhere;
      white-space: pre-wrap; break-inside: avoid; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; width: 100%; font-size: 9pt; margin: 8px 0; break-inside: auto; }
th, td { border: 1px solid #d8cbb5; padding: 4px 6px; vertical-align: top; }
th { background: #2a1f2e; color: #f4e6c8; text-align: left; }
tr:nth-child(even) td { background: #faf6ef; }
hr { border: none; border-top: 1px solid #d8cbb5; margin: 18px 0; }
"""


LIST = re.compile(r"^\s*([-*+]|\d+\.)\s")


def _list_gaps(text: str) -> str:
    """O GitHub aceita lista logo abaixo de um parágrafo; o Python-Markdown precisa de linha em branco."""
    out: list[str] = []
    fence = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            fence = not fence
        prev = out[-1] if out else ""
        if (not fence and LIST.match(line) and prev.strip() and not LIST.match(prev)
                and not prev.startswith(("    ", "\t", "|", ">"))):
            out.append("")
        # sublista com 2 espaços (GitHub) → 4 espaços (Python-Markdown)
        if not fence and re.match(r"^ {2}([-*+]|\d+\.)\s", line):
            line = "  " + line
        out.append(line)
    return "\n".join(out)


def main() -> int:
    src = ROOT / (sys.argv[1] if len(sys.argv) > 1 else "docs/DEVELOPMENT_JOURNEY.md")
    out = src.with_suffix(".pdf")
    browser = next((b for b in BROWSERS if os.path.exists(b)), None)
    if browser is None:
        print("Chrome/Edge não encontrado")
        return 1
    body = markdown.markdown(_list_gaps(src.read_text(encoding="utf-8")),
                             extensions=["tables", "fenced_code", "toc", "sane_lists"])
    title = src.stem.replace("_", " ").title()
    html = (f"<!doctype html><html lang='pt-BR'><head><meta charset='utf-8'>"
            f"<base href='{src.parent.as_uri()}/'><title>{title}</title><style>{CSS}</style></head>"
            f"<body>{body}</body></html>")
    with tempfile.TemporaryDirectory() as tmp:
        page = Path(tmp) / "page.html"
        page.write_text(html, encoding="utf-8")
        subprocess.run([browser, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                        "--allow-file-access-from-files", f"--user-data-dir={tmp}\\profile",
                        f"--print-to-pdf={out}", page.as_uri()], check=True, timeout=180,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"{out} ({out.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
