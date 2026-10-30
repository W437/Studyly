#!/usr/bin/env python3
"""Builds the tour page: a self-contained folder (index.html, and one small film and poster per clip) that a reviewer
who can't run the product can watch and answer, through Cabinet (tshare) or any static server.

    python3 tour_page.py --content tour_content.py --films build/tour/web --out build/review/tour

Content (the brief, the sections, the decisions) is a Python file like `tour_content.example.py`; the films are package.py's
`<films>/<name>.{mp4,jpg,json}` (its .vtt is not used: a <track> made one iPhone refuse the films, so the page draws each clip's
moments over it as captions). The page follows the cabinet skill: the brief first (`data-tshare-brief`), at most five decision
cards (`data-tshare-decide`) each right after the clip it is about, light and dark, phone first. The gateway adds Comment, Done and
the save status; nothing here saves anything.

A section is a clip (`film` names a package.py film) or plain HTML (`film=None, html="..."`: a table, a chart, an economy workbook).
The page is shaped for the gateway's folds (the cabinet skill's "Sections fold"): the hero, the brief, the how-to cards, the route and the
nav stay on show; every part after them is a `<section>` that opens with its own heading (the gateway folds it to that heading), holds its
decisions, and ends with a "Mark section as done" toggle (`data-tshare-pick`: saved by the gateway, not counted as a decision). A decision
whose `after` names no section is put at the end, outside any section, with a warning. `WHERE_TITLE` + `WHERE` (optional HTML) is a section
of its own, first in the list: who the product is for and where it sits among the alternatives (the others, how it differs, its edge).
`APP_NAME`, `APP_SUBTITLE`, `APP_ACTION`, `APP_FACTS` and `ICON` (optional) draw the app as its store page will show it at the top.
`FEEDBACK` (optional) is a list of open questions, each a labelled text box at the very end of the page (`FEEDBACK_GROUP`, `FEEDBACK_LABEL`,
`FEEDBACK_TITLE`, `FEEDBACK_INTRO`, `FEEDBACK_CHIP`, `FEEDBACK_PLACEHOLDER`): the gateway saves what is typed in a textarea that carries
`data-tshare-note`, and counts one with `data-required` as a question for Done.
"""
from __future__ import annotations

import argparse
import html
import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

content = None   # set by main(): the content module

CSS = """
  :root { --bg: #F4F7FB; --surface: #FFFFFF; --ink: #14213D; --ink2: #4A5670; --ink3: #66708A; --line: #E1E7F0; --link: #1866AE;
          --tangerine: #FF7A1A; --tangerine-soft: #FFF0E3; --mint: #1E9E6A; --mint-ink: #12744D; --ring: rgba(11,18,34,.12); --night1: #0B1222; --night2: #1B2A4A; }
  @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg: #0B1222; --surface: #151E30; --ink: #F1F4FA; --ink2: #B2BCCF;
          --ink3: #93A0B8; --line: #26324C; --link: #8FD0FF; --tangerine-soft: #2A1D14; --mint: #4FD39A; --mint-ink: #7FE3BB; --ring: rgba(255,255,255,.16); } }
  :root[data-theme="dark"] { --bg: #0B1222; --surface: #151E30; --ink: #F1F4FA; --ink2: #B2BCCF; --ink3: #93A0B8; --line: #26324C;
          --link: #8FD0FF; --tangerine-soft: #2A1D14; --mint: #4FD39A; --mint-ink: #7FE3BB; --ring: rgba(255,255,255,.16); }
  * { box-sizing: border-box; }
  html { scroll-behavior: smooth; scroll-padding-top: 64px; }
  body { margin: 0; background: var(--bg); color: var(--ink); font: 17px/1.5 -apple-system, "SF Pro Text", system-ui, sans-serif; }
  main { max-width: 980px; margin: 0 auto; padding: 24px 16px 96px; }
  h1 { font-size: 32px; line-height: 1.12; margin: 8px 0 6px; letter-spacing: -.01em; }
  h2 { font-size: 24px; line-height: 1.2; margin: 0 0 6px; letter-spacing: -.005em; }
  h3 { font-size: 13px; letter-spacing: .07em; text-transform: uppercase; color: var(--ink3); margin: 0 0 8px; font-weight: 700; }
  p { margin: 0 0 12px; color: var(--ink2); }
  a { color: var(--link); }
  .eyebrow { font-size: 13px; font-weight: 700; letter-spacing: .07em; text-transform: uppercase; color: var(--tangerine); }
  .lead { font-size: 19px; color: var(--ink); }
  nav.chips { position: sticky; top: 0; z-index: 20; display: flex; gap: 8px; overflow-x: auto; padding: 10px 16px; margin: 0 -16px 18px;
              background: color-mix(in srgb, var(--bg) 92%, transparent); backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px);
              border-bottom: 1px solid var(--line); scrollbar-width: none; }
  nav.chips::-webkit-scrollbar { display: none; }
  nav.chips a { flex: none; display: inline-flex; align-items: center; min-height: 44px; padding: 0 14px; border-radius: 22px;
                border: 1px solid var(--line); background: var(--surface); color: var(--ink); text-decoration: none; font-weight: 600; font-size: 14px; white-space: nowrap; }
  nav.chips a b { color: var(--tangerine); margin-right: 6px; }
  .how { display: grid; gap: 10px; grid-template-columns: repeat(auto-fit, minmax(min(100%, 200px), 1fr)); margin: 4px 0 8px; }
  .how div { background: var(--surface); border: 1px solid var(--line); border-radius: 16px; padding: 12px 14px; font-size: 15px; color: var(--ink2); }
  .how b { display: block; color: var(--ink); margin-bottom: 2px; }
  .route { background: var(--tangerine-soft); border: 1px solid color-mix(in srgb, var(--tangerine) 40%, transparent); border-radius: 18px; padding: 12px 14px 14px; margin: 14px 0 6px; }
  .route h3 { color: var(--tangerine); margin-bottom: 8px; }
  .route .links { display: flex; flex-wrap: wrap; gap: 8px; }
  .jump, .route button { min-height: 44px; padding: 0 14px; border-radius: 22px; border: 1px solid var(--line); background: var(--surface); color: var(--ink);
                         font: 600 14px/1.2 -apple-system, system-ui, sans-serif; cursor: pointer; text-align: left; }
  .route button b { color: var(--tangerine); margin-right: 6px; }
  .group { margin: 44px 0 6px; padding-top: 6px; }
  .group h2 { font-size: 15px; letter-spacing: .08em; text-transform: uppercase; color: var(--ink3); border-top: 1px solid var(--line); padding-top: 18px; }
  .tq-folded + .group { margin-top: 26px; }                      /* after a section the gateway closed: its own line is already there */
  .tq-folded + .group h2 { border-top: 0; padding-top: 0; }
  section.film, section.plain { display: grid; gap: 18px; padding: 22px 0 6px; }
  .phone { margin: 0; justify-self: center; background: #0b0f1a; border-radius: 40px; padding: 7px; box-shadow: 0 12px 34px rgba(11,18,34,.22), 0 0 0 1px rgba(255,255,255,.06) inset; display: grid; gap: 10px; }
  .phone video { display: block; width: min(300px, calc(100vw - 48px)); height: auto; max-height: 82vh; aspect-ratio: var(--ar, 540 / 1168); border-radius: 33px; background: #000; object-fit: cover; }
  .screen { margin: 0; justify-self: center; width: 100%; max-width: 760px; display: grid; gap: 10px; }
  .screen video { display: block; width: 100%; height: auto; aspect-ratio: var(--ar, 16 / 9); border-radius: 14px; background: #000; box-shadow: 0 10px 28px rgba(11,18,34,.2); }
  .stage { display: grid; gap: 8px; }
  .cue { margin: 0; min-height: 2.7em; padding: 0 14px; text-align: center; color: #dfe6f3; font-size: 13px; line-height: 1.35; font-weight: 600; }
  .phone .cue { width: min(300px, calc(100vw - 48px)); }      /* as wide as the clip, so a long caption does not widen the frame */
  .screen .cue { color: var(--ink2); }
  .rate { display: flex; justify-content: center; gap: 8px; }
  .rate button { min-height: 44px; min-width: 56px; padding: 0 14px; border-radius: 22px; border: 1px solid #2b3550; background: transparent; color: #cdd5e6;
                 font: 600 14px/1 -apple-system, system-ui, sans-serif; cursor: pointer; }
  .screen .rate button { color: var(--ink2); border-color: var(--line); }
  .rate button[aria-pressed="true"] { background: var(--tangerine); border-color: var(--tangerine); color: #14213D; }
  .fileline { margin: 0 0 4px; text-align: center; font-size: 13px; line-height: 1.35; color: #9aa6c0; }
  .fileline a { display: inline-flex; align-items: center; min-height: 44px; padding: 0 8px; color: #9db4d8; }
  .fileline .note { display: block; margin: -4px 10px 8px; color: #ffd0a8; font-weight: 600; }
  .screen .fileline { color: var(--ink3); }
  .screen .fileline a { color: var(--link); }
  .screen .fileline .note { color: var(--tangerine); }
  .words > :last-child { margin-bottom: 0; }
  .lede { color: var(--ink); font-size: 17px; }
  .chapters { list-style: none; padding: 0; margin: 14px 0 12px; display: grid; gap: 6px; }
  .chapters button { all: unset; box-sizing: border-box; cursor: pointer; display: grid; grid-template-columns: 52px 1fr; gap: 8px; align-items: start; width: 100%;
                     min-height: 44px; padding: 8px 12px; border-radius: 12px; border: 1px solid transparent; color: var(--ink2); font-size: 15px; line-height: 1.35; }
  .chapters button:hover { background: var(--surface); }
  .chapters button:focus-visible { outline: 2px solid var(--link); outline-offset: 1px; }
  .chapters button[aria-current="true"] { background: var(--tangerine-soft); border-color: color-mix(in srgb, var(--tangerine) 45%, transparent); color: var(--ink); }
  .chapters time { font-variant-numeric: tabular-nums; color: var(--tangerine); font-weight: 700; font-size: 14px; padding-top: 1px; }
  .moments summary { cursor: pointer; min-height: 44px; display: flex; align-items: center; font-weight: 700; color: var(--ink); list-style-position: inside; }
  .look { background: var(--surface); border: 1px solid var(--line); border-radius: 16px; padding: 12px 14px; font-size: 15px; }
  .look b { color: var(--ink); }
  .look p { margin: 0; }
  /* The reading sections (where it sits, what else is in the app). Like the clips, each is a <section> that starts with its own heading,
     which the gateway folds to that heading; nothing here is an accordion of its own. */
  .ref ul { margin: 0 0 12px; padding-left: 20px; color: var(--ink2); font-size: 15px; }
  .ref li { margin: 3px 0; }
  .ref p { margin: 0 0 8px; font-size: 15px; }
  .ref p b { color: var(--ink); }
  .ref p.fine { font-size: 13px; color: var(--ink3); }
  /* "Mark section as done": the gateway saves the toggle (data-tshare-pick) and sets aria-pressed; the page draws it, with a tick on the
     section's label and on its chip. */
  .sdp { margin: 16px 0 2px; }
  .sd { display: inline-flex; align-items: center; justify-content: center; min-height: 44px; padding: 0 20px; border-radius: 22px; border: 1.5px solid var(--line);
        background: var(--surface); color: var(--ink); font: 600 15px/1 -apple-system, system-ui, sans-serif; cursor: pointer; }
  .sd .on { display: none; }
  .sd[aria-pressed="true"] { background: var(--mint); border-color: var(--mint); color: #08281B; }
  .sd[aria-pressed="true"] .on { display: inline; }
  .sd[aria-pressed="true"] .off { display: none; }
  .sd:focus-visible { outline: 3px solid var(--link); outline-offset: 2px; }
  section[data-done] .words > h3::after { content: "  \\00b7  \\2713  done"; color: var(--mint-ink); }
  nav.chips a[data-done]::after { content: "\\2713"; margin-left: 6px; color: var(--mint-ink); font-weight: 800; }
  /* The app as its store page will show it: the icon in the store's rounded shape, the name, the subtitle, the button (not live yet), and the facts under them. */
  .store { margin: 2px 0 6px; }
  .store .top { display: flex; align-items: center; gap: 16px; }
  .store .icon { position: relative; flex: none; width: 112px; height: 112px; border-radius: 22.37%; overflow: hidden; background: #75C1FD;
                 box-shadow: 0 1px 2px rgba(11,18,34,.16), 0 10px 26px rgba(11,18,34,.16); }
  .store .icon img { display: block; width: 100%; height: 100%; }
  .store .icon::after { content: ""; position: absolute; inset: 0; border-radius: inherit; box-shadow: inset 0 0 0 1px var(--ring); pointer-events: none; }
  .store .meta { min-width: 0; }
  .store .name { margin: 0; font-size: 30px; line-height: 1.08; font-weight: 800; letter-spacing: -.02em; color: var(--ink); }
  .store .sub { margin: 3px 0 0; font-size: 16px; line-height: 1.3; color: var(--ink2); }
  .store .buy { display: flex; align-items: center; gap: 10px; margin-top: 12px; }
  .store .get { display: inline-flex; align-items: center; min-height: 32px; padding: 0 16px; border-radius: 16px; font-size: 15px; font-weight: 700; color: var(--ink2);
                background: color-mix(in srgb, var(--ink) 9%, transparent); }
  .store .iap { font-size: 11px; line-height: 1.15; color: var(--ink3); }
  .facts { display: grid; grid-auto-flow: column; grid-auto-columns: minmax(0, 1fr); margin: 20px 0 0; padding: 12px 0 10px; border-top: 1px solid var(--line); border-bottom: 1px solid var(--line); }
  .facts > div { padding: 0 4px; text-align: center; border-left: 1px solid var(--line); }
  .facts > div:first-child { border-left: 0; }
  .facts .k { display: block; font-size: 11px; font-weight: 700; letter-spacing: .06em; text-transform: uppercase; color: var(--ink3); }
  .facts .v { display: flex; align-items: center; justify-content: center; height: 30px; font-size: 20px; font-weight: 700; color: var(--ink2); }
  .facts .v svg { width: 24px; height: 24px; }
  .facts .s { display: block; font-size: 12px; line-height: 1.2; color: var(--ink3); }
  .store + .eyebrow { margin-top: 26px; }
  .tag { display: inline-block; font-size: 12px; font-weight: 700; padding: 1px 8px; border-radius: 10px; margin-right: 6px; vertical-align: 1px; }
  .tag.built { background: color-mix(in srgb, var(--mint) 18%, transparent); color: var(--mint-ink); }
  .tag.pending { background: color-mix(in srgb, var(--link) 16%, transparent); color: var(--link); }
  .tag.next { background: var(--tangerine-soft); color: var(--tangerine); }
  [data-tshare-decide] { margin: 26px 0 6px; }
  /* The open questions at the end: a labelled text box each. The gateway saves what is typed in a textarea with data-tshare-note. */
  .fbq { margin: 0 0 22px; }
  .fbq label { display: block; font-weight: 700; color: var(--ink); font-size: 17px; line-height: 1.3; margin: 0 0 2px; }
  .fbq .req { margin-left: 8px; font-size: 12px; font-weight: 700; color: var(--tangerine); letter-spacing: .02em; white-space: nowrap; }
  .fbq .hint { margin: 0 0 8px; font-size: 14px; color: var(--ink3); }
  .fbq textarea { display: block; width: 100%; min-height: 112px; padding: 12px 14px; border: 1px solid var(--line); border-radius: 14px; background: var(--surface);
                  color: var(--ink); font: 16px/1.45 -apple-system, "SF Pro Text", system-ui, sans-serif; resize: vertical; }
  .fbq textarea:focus-visible { outline: 3px solid var(--link); outline-offset: 2px; }
  .nosave { font-size: 14px; color: var(--tangerine); font-weight: 600; }
  .foot { margin-top: 48px; font-size: 14px; color: var(--ink3); }
  @media (min-width: 760px) {
    h1 { font-size: 42px; }
    section.film { grid-template-columns: 340px 1fr; gap: 36px; align-items: start; }
    section.film .phone { position: sticky; top: 74px; }
    section.film.wide, section.film.tq-folded { grid-template-columns: 1fr; }      /* closed by the gateway: no empty column where the clip was */
  }
  @media (prefers-reduced-motion: reduce) { html { scroll-behavior: auto; } }
"""

JS = """
(function () {
  var videos = [].slice.call(document.querySelectorAll('video'));
  var report = function () {};                    // replaced below when the address has ?log
  // The clips are preload="none": nothing is fetched until one is tapped. Eleven films asking for their headers at the same time
  // left iPhone Safari with players stuck at 00:00 that a tap did not start. The clips are a plain src, with no source element and no track element:
  // that markup (with a captions track) is what that iPhone refused to play, though the same film in a bare video played.
  function say(v, text) {
    var n = v.closest('figure').querySelector('.note');
    if (n) { n.textContent = text || ''; n.hidden = !text; }
  }
  function start(v, t) {                          // play a clip, from t seconds if given, whether or not it has loaded yet
    if (t != null) {
      try { v.currentTime = t; } catch (e) {}
      if (v.readyState < 1) v.addEventListener('loadedmetadata', function () { if (Math.abs(v.currentTime - t) > 1) v.currentTime = t; }, { once: true });
    }
    var p = v.play(); if (p && p.catch) p.catch(function () {});
  }
  // A clip that will not start is fetched and played from memory, which does not go through the browser's media loader (the part
  // that refused the films on one iPhone). If that fails too, the note and the "Open the file" link are what is left.
  function giveUp(v) {
    clearTimeout(v._note); clearTimeout(v._wait);
    say(v, 'This clip did not load here. Use "Open the file" below.'); report(v.id + ' gave up');
  }
  function rescue(v, why) {
    clearTimeout(v._note); clearTimeout(v._wait);
    if (v._rescued) return giveUp(v);
    v._rescued = true; report(v.id + ' rescue: ' + why);
    say(v, 'Loading the clip another way...');
    var t = v.currentTime;
    fetch(v._url).then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.blob(); }).then(function (b) {
      report(v.id + ' fetched ' + b.size + ' bytes');
      v.src = URL.createObjectURL(b);
      if (t) v.currentTime = t;
      var p = v.play(); if (p && p.catch) p.catch(function () {});
      v._wait = setTimeout(function () { if (v.readyState < 1) rescue(v, 'the fetched film did not load'); }, 10000);
    }).catch(function (e) { report(v.id + ' fetch failed: ' + e); giveUp(v); });
  }
  videos.forEach(function (v) {
    v._url = v.getAttribute('src');
    var list = document.querySelector('[data-chapters-for="' + v.id + '"]');
    var buttons = list ? [].slice.call(list.querySelectorAll('button')) : [];
    var marks = buttons.map(function (b) { return { t: parseFloat(b.dataset.t), text: b.querySelector('span').textContent }; });
    var cue = document.querySelector('[data-cue-for="' + v.id + '"]');
    v.addEventListener('play', function () {
      videos.forEach(function (o) { if (o !== v && !o.paused) o.pause(); });
      clearTimeout(v._note); clearTimeout(v._wait);
      if (v.readyState >= 1) return;
      v._note = setTimeout(function () { if (v.readyState < 1 && !v.paused) say(v, 'Still loading. If nothing shows, use "Open the file" below.'); }, 8000);
      v._wait = setTimeout(function () { if (v.readyState < 1 && !v.paused) rescue(v, 'no length after 14 s'); }, 14000);
    });
    v.addEventListener('loadedmetadata', function () { clearTimeout(v._note); clearTimeout(v._wait); say(v, ''); });
    v.addEventListener('error', function () { rescue(v, 'error ' + (v.error ? v.error.code : '?')); });
    function show() {                              // the caption: the moment that is on, on a line under the clip, so it never covers the app (no track element is used)
      var now = v.currentTime, shown = '';
      marks.forEach(function (m, i) {
        var end = Math.min(i + 1 < marks.length ? marks[i + 1].t : Infinity, m.t + 5.95);
        if (now >= m.t - 0.05 && now < end) shown = m.text;
      });
      if (cue && cue.textContent !== shown) cue.textContent = shown;
    }
    v.addEventListener('timeupdate', function () {
      var current = -1;
      buttons.forEach(function (b, i) { if (v.currentTime + 0.15 >= parseFloat(b.dataset.t)) current = i; });
      buttons.forEach(function (b, i) { b.setAttribute('aria-current', i === current ? 'true' : 'false'); });
      show();
    });
    v.addEventListener('seeked', show);
    buttons.forEach(function (b) {
      b.addEventListener('click', function () { start(v, parseFloat(b.dataset.t)); });
    });
    var rates = document.querySelector('[data-rate-for="' + v.id + '"]');
    if (rates) rates.addEventListener('click', function (e) {
      var b = e.target.closest('button'); if (!b) return;
      v.defaultPlaybackRate = v.playbackRate = parseFloat(b.dataset.rate);
      [].slice.call(rates.querySelectorAll('button')).forEach(function (o) { o.setAttribute('aria-pressed', o === b ? 'true' : 'false'); });
    });
  });
  // A link that starts a clip at a moment: the route at the top, and "watch the part this is about" in a decision.
  document.addEventListener('click', function (e) {
    var b = e.target.closest('[data-jump]'); if (!b) return;
    var v = document.getElementById(b.dataset.jump); if (!v) return;
    v.scrollIntoView({ behavior: 'smooth', block: 'center' });
    start(v, parseFloat(b.dataset.t || '0'));
  });
  // Add ?log to the address and each clip's events go to /__d on the review server (scripts/review_server.py logs them): how to see
  // what a phone that will not play is doing. Nothing is sent without it.
  if (/[?&]log\\b/.test(location.search)) {
    var t0 = Date.now(), n = 0, stamp = Math.random().toString(36).slice(2, 6);
    report = function (text) { try { new Image().src = '/__d?' + stamp + '.' + (n++) + '=' + encodeURIComponent(((Date.now() - t0) / 1000).toFixed(1) + 's ' + text); } catch (e) {} };
    report('page ' + navigator.userAgent);
    videos.forEach(function (v) {
      ['loadstart', 'loadedmetadata', 'loadeddata', 'canplay', 'playing', 'pause', 'waiting', 'stalled', 'suspend', 'abort', 'emptied', 'error'].forEach(function (name) {
        v.addEventListener(name, function () { report(v.id + ' ' + name + ' rs' + v.readyState + ' ns' + v.networkState + ' t' + v.currentTime.toFixed(1) + (v.error ? ' err' + v.error.code : '')); });
      });
    });
  }
  // "Mark section as done": the gateway saves each toggle (data-tshare-pick) and sets aria-pressed; the page only shows it, as a tick on the
  // section's label and on its chip. Without the gateway (the plain address, a preview) the buttons keep their state on this device, so they still work.
  var marks = [].slice.call(document.querySelectorAll('.sd'));
  function tick() {
    marks.forEach(function (b) {
      var sec = b.closest('section'), on = b.getAttribute('aria-pressed') === 'true';
      var chip = sec && sec.id ? document.querySelector('nav.chips a[href="#' + sec.id + '"]') : null;
      [sec, chip].forEach(function (el) { if (el) { if (on) el.setAttribute('data-done', ''); else el.removeAttribute('data-done'); } });
    });
  }
  if (marks.length) {
    new MutationObserver(tick).observe(document.body, { subtree: true, attributes: true, attributeFilter: ['aria-pressed'] });
    tick();
    addEventListener('load', function () {
      setTimeout(function () {
        if (window.tshare) return;
        var KEY = 'tour-done:' + location.pathname, saved = {};
        try { saved = JSON.parse(localStorage.getItem(KEY)) || {}; } catch (e) {}
        marks.forEach(function (b) {
          var id = b.getAttribute('data-tshare-pick');
          b.setAttribute('aria-pressed', saved[id] ? 'true' : 'false');
          b.addEventListener('click', function () {
            var on = b.getAttribute('aria-pressed') !== 'true';
            b.setAttribute('aria-pressed', on ? 'true' : 'false');
            if (on) saved[id] = 1; else delete saved[id];
            try { localStorage.setItem(KEY, JSON.stringify(saved)); } catch (e) {}
          });
        });
      }, 1500);
    });
  }
  // The open questions at the end: the gateway saves each text box (data-tshare-note). Without it (the plain address) the text stays on this device,
  // and a line says that it is not saved anywhere else.
  var notes = [].slice.call(document.querySelectorAll('textarea.fbnote'));
  if (notes.length) addEventListener('load', function () {
    setTimeout(function () {
      if (window.tshare) return;
      var KEY = 'tour-notes:' + location.pathname, saved = {};
      try { saved = JSON.parse(localStorage.getItem(KEY)) || {}; } catch (e) {}
      notes.forEach(function (t) {
        var id = t.getAttribute('data-tshare-note');
        if (saved[id]) t.value = saved[id];
        t.addEventListener('input', function () { saved[id] = t.value; try { localStorage.setItem(KEY, JSON.stringify(saved)); } catch (e) {} });
      });
      var n = document.querySelector('.nosave'); if (n) n.hidden = false;
    }, 1500);
  });
  // A clip scrolled out of sight stops, so a phone is not left playing sound behind the next section.
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (!e.isIntersecting && !e.target.paused) e.target.pause(); });
    }, { threshold: 0.05 });
    videos.forEach(function (v) { io.observe(v); });
  }
})();
"""

ICON = ("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='8' fill='%230B1222'/%3E"
        "%3Cpath d='M16 5l3 8 8 .5-6.3 5 2.2 8L16 22l-6.9 4.5 2.2-8L5 13.5l8-.5z' fill='%23FF7A1A'/%3E%3C/svg%3E")


def esc(s: str) -> str:
    return html.escape(s, quote=True)


def stamp(t: float) -> str:
    return f"{int(t // 60)}:{int(t % 60):02d}"


def done_html(sid: str) -> str:
    """"Mark section as done": a toggle the gateway saves (data-tshare-pick; not counted as a decision, so Done does not wait for it)
    and draws (aria-pressed), so the reader can keep track of what he has checked."""
    return (f'<p class="sdp"><button type="button" class="sd" data-tshare-pick="done-{esc(sid)}" aria-pressed="false">'
            f'<span class="off">Mark section as done</span><span class="on">✓ Done</span></button></p>')


def film_html(sec: dict, meta: dict, extra: str = "") -> str:
    """A clip as a section: it opens with its own heading (the gateway folds it to that heading), and holds its decisions and its done toggle."""
    name = sec["film"]
    marks = [m for m in meta["marks"] if not m["text"].startswith("_")]
    wide = meta.get("aspect", 0) > 1
    chapters = "\n".join(
        f'<li><button type="button" data-t="{m["t"]:.2f}" aria-current="false"><time>{stamp(m["t"])}</time><span>{esc(m["text"])}</span></button></li>'
        for m in marks)
    look = f'<div class="look"><p><b>Look for:</b> {esc(sec["look"])}</p></div>' if sec.get("look") else ""
    moments = f"""<ol class="chapters" data-chapters-for="v-{esc(name)}" aria-label="Moments in this clip">
{chapters}
    </ol>""" if marks else ""
    if len(marks) > 8:        # a long list is folded: the clip itself is the content, the moments are a way around it
        moments = f'<details class="moments"><summary>Moments in this clip ({len(marks)})</summary>{moments}</details>'
    frame = "screen" if wide else "phone"
    ar = f' style="--ar: {meta["aspect"]:.4f}"' if wide else ""
    return f"""
<section class="film{' wide' if wide else ''}" id="{esc(sec['id'])}">
  <figure class="{frame}"{ar}>
    <div class="stage">
      <video id="v-{esc(name)}" controls playsinline preload="none" poster="films/{esc(name)}.jpg" src="films/{esc(name)}.mp4" aria-label="{esc(sec['title'])}, a recording"></video>
      <p class="cue" data-cue-for="v-{esc(name)}" aria-hidden="true"></p>
    </div>
    <div class="rate" role="group" aria-label="Playback speed" data-rate-for="v-{esc(name)}">
      <button type="button" data-rate="1" aria-pressed="true">1×</button>
      <button type="button" data-rate="1.5" aria-pressed="false">1.5×</button>
      <button type="button" data-rate="2" aria-pressed="false">2×</button>
    </div>
    <p class="fileline">Not playing? <a href="films/{esc(name)}.mp4" target="_blank" rel="noopener">Open the file</a><span class="note" role="status" hidden></span></p>
  </figure>
  <div class="words">
    <h3>{sec['n']} · {stamp(meta['duration'])}</h3>
    <h2>{esc(sec['title'])}</h2>
    <p class="lede">{sec['lede']}</p>
    {moments}
    {look}{extra}
  </div>
</section>"""


def plain_html(sec: dict, extra: str = "") -> str:
    return f"""
<section class="plain" id="{esc(sec['id'])}">
  <div class="words">
    <h3>{sec['n']}</h3>
    <h2>{esc(sec['title'])}</h2>
    {sec['html']}{extra}
  </div>
</section>"""


def ref_html(sid: str, group: str, label: str, title: str, inner: str) -> str:
    """A reading section that is not a clip (where it sits, what else is in the app), under its own group heading."""
    return f"""
<div class="group"><h2>{esc(group)}</h2></div>
<section class="plain ref" id="{esc(sid)}">
  <div class="words">
    <h3>{esc(label)}</h3>
    <h2>{esc(title)}</h2>
    {inner}
    {done_html(sid)}
  </div>
</section>"""


def copy_icon(src: Path, out: Path) -> tuple[str, str]:
    """The app icon at the sizes a page needs, next to the page: brand/icon.png (512 px, the store header) and brand/touch.png (180 px, the
    tab and home-screen icon). `sips` (macOS) resizes; anywhere else the file is copied as it is."""
    (out / "brand").mkdir(exist_ok=True)
    for name, px in (("icon.png", 512), ("touch.png", 180)):
        dst = out / "brand" / name
        ok = shutil.which("sips") and subprocess.run(["sips", "-z", str(px), str(px), str(src), "--out", str(dst)], capture_output=True).returncode == 0
        if not ok:
            shutil.copy2(src, dst)
    return "brand/icon.png", "brand/touch.png"


def store_html(icon: str) -> str:
    """The app as its store page will show it: the icon in the store's rounded shape, the name, the subtitle, the button (not live yet, so it
    says so and is not a button), and the facts the store puts under them. The content gives APP_NAME, APP_SUBTITLE, APP_ACTION and APP_FACTS
    ((label, value as HTML, sub-label) each) and, if it likes, APP_ACTION_NOTE (the small line under the button)."""
    img = f'<span class="icon"><img src="{icon}" alt="" width="112" height="112"></span>' if icon else ""
    facts = "".join(f'<div><span class="k">{esc(k)}</span><span class="v">{v}</span><span class="s">{esc(s)}</span></div>' for k, v, s in content.APP_FACTS)
    note = f'<span class="iap">{esc(content.APP_ACTION_NOTE)}</span>' if getattr(content, "APP_ACTION_NOTE", "") else ""
    return f"""
  <header class="store">
    <div class="top">
      {img}
      <div class="meta">
        <p class="name">{esc(content.APP_NAME)}</p>
        <p class="sub">{esc(content.APP_SUBTITLE)}</p>
        <div class="buy"><span class="get" aria-disabled="true">{esc(content.APP_ACTION)}</span>{note}</div>
      </div>
    </div>
    <div class="facts">{facts}</div>
  </header>"""


def decision_html(d: dict) -> str:
    rec = f' data-recommend="{esc(d["recommend"])}"' if d.get("recommend") else ""
    watch = ""
    if d.get("watch"):
        film, t = d["watch"]
        watch = f'\n  <p><button type="button" class="jump" data-jump="v-{esc(film)}" data-t="{t}">▶ Watch the part this is about</button></p>'
    return f"""
<div data-tshare-decide="{esc(d['id'])}" data-question="{esc(d['question'])}" data-options="{esc(d['options'])}"{rec}>
  <p>{d['context']}</p>{watch}
</div>"""


def feedback_html() -> str:
    """The open questions at the end (content.FEEDBACK): a labelled text box each, under a group heading of its own. The gateway saves what is
    typed in a textarea with data-tshare-note, and counts one with data-required as a question for Done."""
    rows = []
    for q in content.FEEDBACK:
        qid = esc(q["id"])
        flag = '<span class="req">needed for Done</span>' if q.get("required") else ""
        hint = f'<p class="hint" id="{qid}-hint">{esc(q["hint"])}</p>' if q.get("hint") else ""
        described = f' aria-describedby="{qid}-hint"' if q.get("hint") else ""
        required = " data-required" if q.get("required") else ""
        rows.append(f"""    <div class="fbq">
      <label for="{qid}">{esc(q['question'])}{flag}</label>
      {hint}
      <textarea id="{qid}" class="fbnote" data-tshare-note="{qid}"{required} rows="4" dir="auto"{described} placeholder="{esc(getattr(content, 'FEEDBACK_PLACEHOLDER', ''))}"></textarea>
    </div>""")
    return f"""
<div class="group"><h2>{esc(getattr(content, 'FEEDBACK_GROUP', 'Your turn'))}</h2></div>
<section class="plain" id="feedback">
  <div class="words">
    <h3>{esc(getattr(content, 'FEEDBACK_LABEL', 'In your own words'))}</h3>
    <h2>{esc(getattr(content, 'FEEDBACK_TITLE', 'What do you think?'))}</h2>
    <p class="lede">{getattr(content, 'FEEDBACK_INTRO', '')}</p>
{chr(10).join(rows)}
    <p class="nosave" role="status" hidden>This is the plain link: what you write here stays on this device. Open the page from Cabinet to save it.</p>
    {done_html("feedback")}
  </div>
</section>"""


def build(films: Path, out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    (out / "films").mkdir(exist_ok=True)
    metas: dict[str, dict] = {}
    for sec in content.SECTIONS:
        name = sec.get("film")
        if not name:
            continue
        meta_file = films / f"{name}.json"
        if not meta_file.exists():
            print(f"missing film: {name} (its section is skipped)")
            continue
        metas[name] = json.loads(meta_file.read_text())
        for ext in ("mp4", "jpg"):
            shutil.copy2(films / f"{name}.{ext}", out / "films" / f"{name}.{ext}")
    for stale in (out / "films").glob("*.vtt"):      # captions from an older build: nothing refers to them any more
        stale.unlink()

    body: list[str] = []
    chips: list[str] = []
    group = None
    decisions_after: dict[str, list[dict]] = {}
    for d in content.DECISIONS:
        decisions_after.setdefault(d["after"], []).append(d)
    total = 0.0
    number = 0
    placed: set[str] = set()
    for sec in content.SECTIONS:
        name = sec.get("film")
        meta = metas.get(name) if name else None
        if name and not meta:
            continue
        number += 1
        sec = {**sec, "n": number}              # numbered in the order they appear, among the sections that exist
        if sec["group"] != group:
            group = sec["group"]
            body.append(f'<div class="group"><h2>{esc(group)}</h2></div>')
        chips.append(f'<a href="#{esc(sec["id"])}"><b>{number}</b>{esc(sec["chip"])}</a>')
        # The cabinet skill: a decision goes inside the part it is about (so a closed row says how many are made), and each part can be marked done.
        extra = "".join(decision_html(d) for d in decisions_after.get(sec["id"], [])) + done_html(sec["id"])
        if meta:
            total += meta["duration"]
            body.append(film_html(sec, meta, extra))
        else:
            body.append(plain_html(sec, extra))
        placed.add(sec["id"])
    orphans = [d for d in content.DECISIONS if d["after"] not in placed]
    for d in orphans:
        print(f"warning: decision '{d['id']}' follows '{d['after']}', which is not on the page: it is put at the end, outside any section")
        body.append(decision_html(d))
    if len(content.DECISIONS) > 5:
        print(f"warning: {len(content.DECISIONS)} decisions; the cabinet rule is five or fewer per page")

    also = ""
    if getattr(content, "ALSO", None):
        labels = {"built": "Built", "pending": "Built, not live yet", "next": "Planned"}
        rows = "".join(f'<li><span class="tag {kind}">{labels.get(kind, kind)}</span>{text}</li>' for kind, text in content.ALSO)
        also = ref_html("also", "Reference", "For reference", content.ALSO_TITLE, f"<ul>{rows}</ul>")
    feedback = ""
    if getattr(content, "FEEDBACK", None):          # open questions at the very end, after the reference list
        feedback = feedback_html()
        chips.append(f'<a href="#feedback"><b>✎</b>{esc(getattr(content, "FEEDBACK_CHIP", "Your thoughts"))}</a>')
    where = ""
    if getattr(content, "WHERE", None):          # who it is for and where it sits among the alternatives: a section of its own, first in the list
        where = ref_html("where", "Background", "A minute to read", content.WHERE_TITLE, content.WHERE)
    icon = touch = ""
    if getattr(content, "ICON", None):
        src = (Path(content.__file__).resolve().parent / content.ICON).resolve()
        if src.is_file():
            icon, touch = copy_icon(src, out)
        else:
            print(f"warning: the icon {src} does not exist: the page is built without it")
    store = store_html(icon) if getattr(content, "APP_NAME", None) else ""
    favicon = (f'<link rel="icon" type="image/png" href="{touch}">\n<link rel="apple-touch-icon" href="{touch}">' if touch else f'<link rel="icon" href="{ICON}">')
    route = ""
    if getattr(content, "ROUTE", None):
        links = "".join(f'<button type="button" data-jump="v-{esc(f)}" data-t="{t}"><b>{i}</b>{esc(label)}</button>'
                        for i, (label, f, t) in enumerate(content.ROUTE, 1) if f in metas)
        route = f'<div class="route"><h3>{esc(content.ROUTE_TITLE)}</h3><div class="links">{links}</div></div>'
    cut = round(sum(m.get("cut_seconds", 0) for m in metas.values()))
    foot = content.FOOT + (f" {cut} seconds of waiting on the recording tool, in all, are trimmed out." if cut else "")
    minutes = min(10, max(3, round(total / 60 * 0.6)))      # honest for someone who watches what they care about, not all of it
    brief = content.BRIEF.replace("{minutes}", str(minutes)).replace("{total}", str(round(total / 60)))
    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{esc(content.TITLE)}</title>
<meta name="color-scheme" content="light dark">
{favicon}
<style>{CSS}</style>
</head>
<body>
<main>{store}
  <div class="eyebrow">{esc(content.EYEBROW)}</div>
  <h1>{esc(content.HEADLINE)}</h1>
  <p class="lead">{content.INTRO}</p>
  <section data-tshare-brief data-minutes="{minutes}">
{brief}
  </section>
  <div class="how">{''.join(f'<div><b>{esc(t)}</b>{esc(b)}</div>' for t, b in content.HOW)}</div>
  {route}
  <nav class="chips" aria-label="Sections">{''.join(chips)}</nav>{where}
{''.join(body)}
{also}{feedback}
  <p class="foot">{foot}</p>
</main>
<script>{JS}</script>
</body>
</html>
"""
    (out / "index.html").write_text(page)
    size = sum(f.stat().st_size for f in out.rglob("*") if f.is_file())
    print(f"{out / 'index.html'}  {len(metas)} films  {total / 60:.1f} min  {size / 1e6:.1f} MB")


if __name__ == "__main__":
    here = Path(__file__).resolve().parent
    root = here.parents[1]          # the project root, when this sits in <root>/scripts/journeys/
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--content", default=str(here / "tour_content.py"), help="the content module (a .py file)")
    ap.add_argument("--films", default=str(root / "build/tour/web"), help="the folder package.py wrote")
    ap.add_argument("--out", default=str(root / "build/review/anis-tour"))
    args = ap.parse_args()
    spec = importlib.util.spec_from_file_location("tour_content", args.content)
    content = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(content)
    build(Path(args.films), Path(args.out))
