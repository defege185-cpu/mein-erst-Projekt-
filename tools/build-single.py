#!/usr/bin/env python3
"""Construit detecteur-test.html : toute l'application dans un seul fichier (test hors ligne)."""
import pathlib
root = pathlib.Path(__file__).resolve().parent.parent
app = root / 'app'
h = (app / 'index.html').read_text(encoding='utf-8')
h = h.replace('<link rel="stylesheet" href="style.css">', '<style>\n' + (app / 'style.css').read_text(encoding='utf-8') + '</style>')
for js in ('i18n.js', 'i18n-report.js', 'detector.js', 'app.js', 'report.js'):
    h = h.replace('<script src="%s"></script>' % js, '<script>\n' + (app / js).read_text(encoding='utf-8') + '</script>')
h = h.replace('<link rel="manifest" href="manifest.json">\n', '').replace('<link rel="icon" href="icon.svg" type="image/svg+xml">\n', '')
(root / 'detecteur-test.html').write_text(h, encoding='utf-8')
print('OK ->', root / 'detecteur-test.html')
