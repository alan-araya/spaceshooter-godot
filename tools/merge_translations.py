"""Junta os rascunhos i18n/_draft_<idioma>.json na tabela i18n/strings.csv e confere os {valores}.

Uso: python -I tools/merge_translations.py [idioma ...]   (sem argumento: todos os rascunhos achados)
Para cada idioma: toda chave do CSV tem de estar no rascunho, com os mesmos {nomes} do pt-BR.
Problemas são listados e a coluna daquele idioma não é gravada.
"""
import csv
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "i18n")
PH = re.compile(r"\{([a-z_]+)\}")

rows = list(csv.reader(open(os.path.join(ROOT, "strings.csv"), encoding="utf-8")))
hdr = rows[0]
langs = sys.argv[1:] or [l for l in hdr[2:] if os.path.exists(os.path.join(ROOT, "_draft_%s.json" % l))]
ok_any = False
for lang in langs:
    draft = json.load(open(os.path.join(ROOT, "_draft_%s.json" % lang), encoding="utf-8"))
    col = hdr.index(lang)
    problems = []
    for r in rows[1:]:
        key, pt = r[0], r[1]
        if key not in draft:
            problems.append("%s: falta" % key)
            continue
        t = str(draft[key]).strip()
        if not t:
            problems.append("%s: vazio" % key)
        elif sorted(PH.findall(pt)) != sorted(PH.findall(t)):
            problems.append("%s: valores %s x %s" % (key, PH.findall(pt), PH.findall(t)))
    extra = set(draft) - {r[0] for r in rows[1:]}
    if extra:
        problems.append("chaves a mais: %s" % ", ".join(sorted(extra)))
    if problems:
        print("%s: %d problemas, NÃO gravado" % (lang, len(problems)))
        for p in problems[:30]:
            print("   ", p)
        continue
    for r in rows[1:]:
        r[col] = str(draft[r[0]]).strip()
    ok_any = True
    print("%s: %d frases gravadas" % (lang, len(rows) - 1))
if ok_any:
    with open(os.path.join(ROOT, "strings.csv"), "w", encoding="utf-8", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(rows)
