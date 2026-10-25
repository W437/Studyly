"""Wrap site/plan.html (the artifact source, no document skeleton) into site/index.html for local and Tailscale viewing.

The Artifact tool adds the same skeleton at publish time, so the two copies render alike.
Usage: python3 build.py
"""
import os

SITE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'site'))

HEAD = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<link rel="icon" type="image/png" href="img/favicon.png">
<link rel="apple-touch-icon" href="img/apple-touch-icon.png">
<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style>
</head>
<body>
"""

with open(os.path.join(SITE, 'plan.html'), encoding='utf-8') as f:
    body = f.read()
with open(os.path.join(SITE, 'index.html'), 'w', encoding='utf-8') as f:
    f.write(HEAD + body + '\n</body>\n</html>\n')
print('wrote', os.path.join(SITE, 'index.html'))
