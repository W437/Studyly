/* Cramless prototype core: helpers, navigation stack, tab bar, sheets, toasts. */
(() => {
  'use strict';
  const app = document.getElementById('app');
  const embed = location.hash.indexOf('embed') !== -1;
  const framed = !embed && window.innerWidth >= 600 && window.innerHeight >= 760;
  document.documentElement.classList.toggle('framed', framed);
  document.documentElement.classList.toggle('embed', embed);

  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const ic = (n, c = '') => `<i data-lucide="${n}" class="ic ${c}"></i>`;
  const icons = () => { try { window.lucide && window.lucide.createIcons(); } catch (e) { /* icons are decoration */ } };
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const CANCEL = { cancelled: true };

  /* A script is a cancellable sequence of beats (see live-onboarding: sleeps must throw). */
  function script() {
    const s = { alive: true, async nap(ms) { await sleep(ms); if (!s.alive) throw CANCEL; } };
    return s;
  }
  async function play(s, fn) { try { await fn(s); } catch (e) { if (e !== CANCEL) console.error(e); } }

  const S = {
    stack: [], tab: 'today', plan: 'yearly', pro: false, hints: true, theme: 'system',
    onb: { goal: null, when: null, mins: null, sources: [] },
    chat: null, flow: null
  };

  const SCREENS = {};
  const TAB_ROOTS = ['today', 'library', 'ask', 'progress'];

  /* ---------- chrome: status bar, home indicator, tab bar, toast ---------- */
  app.insertAdjacentHTML('beforeend', `
    <div class="sb" id="sb"><span>9:41</span><div class="island"></div>
      <div class="right">
        <svg width="18" height="12" viewBox="0 0 18 12" fill="currentColor"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg>
        <svg width="16" height="12" viewBox="0 0 16 12" fill="currentColor"><path d="M8 11.5 5.6 9a3.4 3.4 0 0 1 4.8 0L8 11.5Zm-4.3-4.4L2.3 5.6a8 8 0 0 1 11.4 0l-1.4 1.5a6 6 0 0 0-8.6 0ZM.6 3.9-.8 2.4a10.3 10.3 0 0 1 17.6 0l-1.4 1.5a8.3 8.3 0 0 0-14.8 0Z"/></svg>
        <svg width="27" height="13" viewBox="0 0 27 13" fill="none"><rect x=".5" y=".5" width="23" height="12" rx="3.5" stroke="currentColor" opacity=".4"/><rect x="2" y="2" width="18" height="9" rx="2" fill="currentColor"/><path d="M25 4.5v4c.8-.3 1.3-1.1 1.3-2s-.5-1.7-1.3-2Z" fill="currentColor" opacity=".5"/></svg>
      </div></div>
    <div class="home-ind" id="homeind"></div>
    <div class="edge-top" id="edgetop"></div>
    <nav class="tabbar" id="tabbar" hidden>
      <div class="tabs glass"><span class="tab-lens" id="lens"></span>
        <button class="tab" data-tab="today">${ic('sun')}<span>Today</span></button>
        <button class="tab" data-tab="library">${ic('library')}<span>Library</span></button>
        <button class="tab" data-tab="ask">${ic('message-circle')}<span>Ask</span></button>
        <button class="tab" data-tab="progress">${ic('chart-column')}<span>Progress</span></button>
      </div>
      <button class="fab glass" data-act="capture" aria-label="Add material"><span class="plus">${ic('plus')}</span></button>
    </nav>
    <div class="toast glass" id="toast" role="status"></div>
    <button class="proto-btn glass" id="protobtn" aria-label="Prototype screens" title="Prototype screens">${ic('ellipsis-vertical')}</button>`);

  const sb = $('#sb'), homeInd = $('#homeind'), tabbar = $('#tabbar'), lens = $('#lens'), toastEl = $('#toast'), edge = $('#edgetop');

  function chrome(def) {
    const tone = def.sb || 'auto';
    sb.style.color = tone === 'white' ? '#fff' : tone === 'night' ? '#14213D' : '';
    homeInd.style.background = tone === 'white' ? '#fff' : tone === 'night' ? '#14213D' : '';
    edge.hidden = tone !== 'auto' || def.edge === false;
    sb.firstElementChild.style.visibility = def.clock === false ? 'hidden' : '';
  }

  function showTabbar(name) {
    const on = TAB_ROOTS.includes(name);
    tabbar.hidden = !on;
    if (!on) return;
    S.tab = name;
    $$('.tab', tabbar).forEach((t) => t.classList.toggle('on', t.dataset.tab === name));
    requestAnimationFrame(() => {
      const t = $(`.tab[data-tab="${name}"]`, tabbar);
      if (!t) return;
      lens.style.left = t.offsetLeft + 'px';
      lens.style.width = t.offsetWidth + 'px';
    });
  }

  let toastTimer;
  function toast(msg, icon = 'check') {
    toastEl.innerHTML = `${ic(icon, 'm')}<span>${msg}</span>`;
    icons();
    toastEl.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.remove('show'), 2600);
  }

  /* ---------- screens ---------- */
  function build(name, params) {
    const def = SCREENS[name];
    const el = document.createElement('section');
    el.className = 'screen ' + (def.cls || '');
    el.dataset.name = name;
    el.innerHTML = def.render(params || {});
    app.insertBefore(el, sb);
    const ctx = { el, params: params || {}, scripts: [], script() { const s = script(); ctx.scripts.push(s); return s; } };
    el._ctx = ctx;
    icons();
    return el;
  }
  function start(entry) {
    const def = SCREENS[entry.name];
    chrome(def);
    showTabbar(entry.name);
    if (def.mount) def.mount(entry.el, entry.params || {}, entry.el._ctx);
  }
  function stop(entry) {
    const ctx = entry.el._ctx;
    ctx.scripts.forEach((s) => { s.alive = false; });
    ctx.scripts = [];
  }
  function kill(entry) { stop(entry); entry.el.remove(); }
  function after(el, cls, fn) {
    el.classList.add(cls);
    const done = () => { el.classList.remove(cls); fn && fn(); };
    if (reduce) { done(); return; }
    setTimeout(done, 520);
  }

  /* how: push (slide), up (modal), fade, root (replace all), replace (swap top) */
  function go(name, params = {}, how = 'push') {
    const top = S.stack[S.stack.length - 1];
    const el = build(name, params);
    const entry = { name, params, el, how };
    if (how === 'root') {
      const old = S.stack.slice();
      S.stack = [entry];
      start(entry);
      after(el, 'in-fade');
      old.forEach((e) => { stop(e); after(e.el, 'out-fade', () => e.el.remove()); });
      return;
    }
    if (how === 'replace' && top) {
      S.stack[S.stack.length - 1] = entry;
      entry.how = top.how;
      start(entry);
      after(el, 'in-fade');
      stop(top);
      after(top.el, 'out-fade', () => top.el.remove());
      return;
    }
    S.stack.push(entry);
    if (top) stop(top);
    start(entry);
    if (how === 'up') {
      after(el, 'in-up', () => { if (top) top.el.style.visibility = 'hidden'; });
    } else if (how === 'fade') {
      after(el, 'in-fade', () => { if (top) top.el.style.visibility = 'hidden'; });
    } else {
      after(el, 'in-push');
      if (top) after(top.el, 'out-push', () => { top.el.style.visibility = 'hidden'; });
    }
  }

  function back() {
    if (S.stack.length < 2) return;
    const top = S.stack.pop();
    const prev = S.stack[S.stack.length - 1];
    prev.el.style.visibility = '';
    stop(top);
    if (top.how === 'up') {
      after(top.el, 'out-down', () => top.el.remove());
    } else if (top.how === 'fade') {
      after(top.el, 'out-fade', () => top.el.remove());
    } else {
      after(top.el, 'out-pop', () => top.el.remove());
      after(prev.el, 'in-pop');
    }
    start(prev);
  }

  /* Re-render the top screen in place (used when state changes). */
  function refresh() {
    const top = S.stack[S.stack.length - 1];
    if (!top) return;
    stop(top);
    const scroll = top.el.scrollTop;
    top.el.innerHTML = SCREENS[top.name].render(top.params || {});
    icons();
    top.el.scrollTop = scroll;
    start(top);
  }

  /* ---------- sheets ---------- */
  function sheet(html, { onMount } = {}) {
    closeSheet(true);
    const layer = document.createElement('div');
    layer.className = 'sheet-layer';
    layer.innerHTML = `<div class="scrim" data-act="close-sheet"></div><div class="sheet" role="dialog" aria-modal="true"><div class="grabber"></div>${html}</div>`;
    app.insertBefore(layer, toastEl);
    icons();
    onMount && onMount(layer);
    return layer;
  }
  function closeSheet(instant) {
    const layer = $('.sheet-layer', app);
    if (!layer) return;
    if (instant || reduce) { layer.remove(); return; }
    $('.sheet', layer).classList.add('closing');
    $('.scrim', layer).classList.add('closing');
    setTimeout(() => layer.remove(), 320);
  }

  /* ---------- shared widgets ---------- */
  function ringColor(p) { return p >= 80 ? 'var(--mint)' : p >= 50 ? 'var(--sun)' : 'var(--rose)'; }
  function ring(size, stroke, pct, { label = true, sub = '' } = {}) {
    const r = (size - stroke) / 2, c = 2 * Math.PI * r;
    return `<div class="ring" style="width:${size}px;height:${size}px" data-c="${c}">
      <svg width="${size}" height="${size}"><circle class="track" cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke-width="${stroke}"/>
      <circle class="val" cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke-width="${stroke}" stroke="${ringColor(pct)}" stroke-dasharray="${c}" stroke-dashoffset="${c * (1 - pct / 100)}"/></svg>
      ${label ? `<div class="lbl"><div><div class="pct" style="font-size:${Math.round(size * 0.24)}px"><span data-pct>${pct}</span><small>%</small></div>${sub ? `<div style="font-size:11px;font-weight:600;color:var(--fg-2);margin-top:3px">${sub}</div>` : ''}</div></div>` : ''}
    </div>`;
  }
  /* Animate a ring (and its number) from one value to another. */
  function setRing(el, to, { from, ms = 1300 } = {}) {
    const c = parseFloat(el.dataset.c), val = $('.val', el), num = $('[data-pct]', el);
    const start = from == null ? parseFloat(num ? num.textContent : 0) : from;
    val.style.stroke = ringColor(to);
    val.style.strokeDashoffset = c * (1 - to / 100);
    if (!num) return;
    if (reduce) { num.textContent = to; return; }
    const t0 = performance.now();
    const tick = (t) => {
      const k = Math.min(1, (t - t0) / ms), e = 1 - Math.pow(1 - k, 3);
      num.textContent = Math.round(start + (to - start) * e);
      if (k < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }
  function snapRing(el, pct) {
    const c = parseFloat(el.dataset.c), val = $('.val', el), num = $('[data-pct]', el);
    val.style.transition = 'none';
    val.style.strokeDashoffset = c * (1 - pct / 100);
    val.style.stroke = ringColor(pct);
    if (num) num.textContent = pct;
    void val.getBoundingClientRect();
    val.style.transition = '';
  }

  /* ---------- delegated events ---------- */
  const ACTIONS = {};
  app.addEventListener('click', (e) => {
    const t = e.target.closest('[data-act],[data-go],[data-tab],[data-back]');
    if (!t || t.disabled) return;
    if (t.dataset.back !== undefined) { back(); return; }
    if (t.dataset.tab) { if (t.dataset.tab !== S.tab || S.stack.length > 1) go(t.dataset.tab, {}, 'root'); return; }
    if (t.dataset.go) { go(t.dataset.go, t.dataset.params ? JSON.parse(t.dataset.params) : {}, t.dataset.how || 'push'); return; }
    const fn = ACTIONS[t.dataset.act];
    if (fn) fn(t, e);
  });
  ACTIONS['close-sheet'] = () => closeSheet();

  window.addEventListener('resize', () => { const top = S.stack[S.stack.length - 1]; if (top) showTabbar(top.name); });

  window.CL = { app, S, SCREENS, ACTIONS, $, $$, esc, ic, icons, sleep, reduce, script, play, go, back, refresh, sheet, closeSheet, toast, ring, setRing, snapRing, ringColor, embed, framed };
})();
