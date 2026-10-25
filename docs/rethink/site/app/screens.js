/* Cramless prototype screens. */
(() => {
  'use strict';
  const CL = window.CL, D = window.DATA;
  const { S, SCREENS, ACTIONS, $, $$, esc, ic, icons, go, back, refresh, sheet, closeSheet, toast, ring, setRing, snapRing, reduce, play } = CL;
  const IMG = '../img/';
  const bio = D.exams[0];

  const navBar = (title = '', { left = 'back', right = '' } = {}) => `<div class="nav">
    ${left === 'back' ? `<button class="icon-btn glass" data-back aria-label="Back">${ic('chevron-left')}</button>` : left === 'close' ? `<button class="icon-btn glass" data-back aria-label="Close">${ic('x')}</button>` : '<span class="spacer"></span>'}
    <div class="ttl">${title}</div>${right || '<span class="spacer"></span>'}</div>`;
  const pct = (n) => `<span class="num">${n}%</span>`;
  const barC = (m) => (m >= 80 ? 'c-mint' : m >= 50 ? 'c-sun' : 'c-rose');

  /* ================= welcome ================= */
  SCREENS.welcome = {
    cls: 'welcome fixed', sb: 'night',
    render: () => `<div class="art"><img src="${IMG}cap-wave.webp" alt="Cap the capybara waving hello"></div>
      <div class="foot">
        <h1 class="word brand">cramless</h1>
        <p class="tag">A little every day.<br>Ready on exam day.</p>
        <button class="btn dark block mt24" data-act="start">Get started</button>
        <button class="btn ghost block" data-act="signin">I already have an account</button>
      </div>`
  };
  ACTIONS.start = () => go('onb', {}, 'push');
  ACTIONS.signin = () => { toast('Sign-in is skipped in the prototype', 'info'); go('onb'); };

  /* ================= onboarding pager ================= */
  const PAGES = [
    { scene: 'capture', bg: 'var(--sky-soft)', title: 'Snap a page. Get a study set.', body: 'Photos, PDFs, slides or a lecture. Every question links back to the page it came from.' },
    { scene: 'grade', bg: 'var(--mint-soft)', title: 'Answer in your own words.', body: 'No more flip-and-guess. Type or say it, and see exactly what you nailed and what’s missing.' },
    { scene: 'ready', bg: 'var(--sun-soft)', title: 'Know how ready you are.', body: 'A readiness score for every exam, built from what you actually remember.' },
    { scene: 'plan', bg: 'var(--tang-soft)', title: 'A plan that bends with your week.', body: 'Short daily sessions until exam day. Miss one and the rest of the week quietly absorbs it.' },
    { scene: 'tutor', bg: 'var(--sky-soft)', title: 'A tutor that knows your notes.', body: 'Stuck? Ask Cap. Answers cite your own material, and it nudges you to think before it tells.' }
  ];
  SCREENS.onb = {
    cls: 'onb fixed', edge: false,
    render: () => `<div class="onb-bg" style="background:${PAGES[0].bg}"></div>
      <div class="onb-top"><span class="brand" style="font-size:22px">cramless</span><button class="btn ghost sm" data-act="onb-skip">Skip</button></div>
      <div class="pager">${PAGES.map((p, i) => `<div class="page" data-i="${i}">
        <div class="scene" data-scene="${p.scene}">${CL.SCENES[p.scene].html()}</div>
        <h2>${p.title}</h2><p>${p.body}</p></div>`).join('')}</div>
      <div class="onb-foot"><div class="dots">${PAGES.map((_, i) => `<i class="${i ? '' : 'on'}"></i>`).join('')}</div>
        <button class="btn primary block" data-act="onb-next"><span class="xfade">Continue</span></button></div>`,
    mount(el, p, ctx) {
      const pager = $('.pager', el), dots = $$('.dots i', el), bg = $('.onb-bg', el), label = $('.xfade', el), skip = $('[data-act="onb-skip"]', el);
      const scenes = $$('.scene', el);
      let cur = -1, active = null;
      const activate = (i) => {
        if (i === cur) return;
        cur = i;
        if (active) active.alive = false;
        dots.forEach((d, k) => d.classList.toggle('on', k === i));
        bg.style.background = PAGES[i].bg;
        label.style.opacity = 0;
        setTimeout(() => { label.textContent = i === PAGES.length - 1 ? 'Let’s go' : 'Continue'; label.style.opacity = 1; }, 160);
        skip.style.visibility = i === PAGES.length - 1 ? 'hidden' : '';
        active = ctx.script();
        const sc = scenes[i];
        play(active, (s) => CL.SCENES[PAGES[i].scene].run(sc, s));
      };
      let raf;
      pager.onscroll = () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(() => activate(Math.round(pager.scrollLeft / pager.clientWidth))); };
      el._next = () => { if (cur < PAGES.length - 1) pager.scrollTo({ left: (cur + 1) * pager.clientWidth, behavior: reduce ? 'auto' : 'smooth' }); else go('quiz', { q: 0 }); };
      cur = -1;
      activate(Math.round(pager.scrollLeft / Math.max(1, pager.clientWidth)));
    }
  };
  ACTIONS['onb-next'] = (t) => { const el = t.closest('.screen'); el._next && el._next(); };
  ACTIONS['onb-skip'] = () => go('quiz', { q: 0 });

  /* ================= personalisation ================= */
  const QUIZ = [
    { key: 'goal', title: 'What are you studying for?', sub: 'We’ll shape your plan around it.', opts: [
      ['clipboard-check', 'Tests and midterms', 'A class you’re taking now'], ['graduation-cap', 'Finals', 'End-of-term exams'], ['award', 'AP or IB exams'],
      ['pencil-ruler', 'SAT or ACT'], ['stethoscope', 'MCAT, LSAT or another big test'], ['languages', 'A language'] ] },
    { key: 'when', title: 'When’s your next big exam?', sub: 'Cramless plans backwards from that date.', opts: [
      ['zap', 'This week'], ['calendar', 'In about two weeks'], ['calendar-range', 'In about a month'], ['calendar-days', 'Pick a date', 'Fri, Nov 14 · Bio 101 Midterm'] ] },
    { key: 'mins', title: 'How much time can you give it a day?', sub: 'Little and often beats cramming. You can change this anytime.', opts: [
      ['coffee', '5 minutes', 'Light'], ['timer', '10 minutes', 'Steady'], ['flame', '15 minutes', 'Serious'], ['rocket', '25 minutes', 'All in'] ] },
    { key: 'sources', multi: true, title: 'Where do your notes live?', sub: 'Pick all that apply. Cramless can use every one of them.', opts: [
      ['book-open', 'Textbooks and handouts'], ['presentation', 'Slides and PDFs'], ['mic', 'Lectures'], ['pen-line', 'Handwritten notes'],
      ['layers', 'Quizlet or Anki sets', 'Import them in one tap'], ['sparkles', 'Nothing yet'] ] }
  ];
  SCREENS.quiz = {
    render: ({ q }) => {
      const Q = QUIZ[q], val = S.onb[Q.key];
      const isOn = (i) => (Q.multi ? (val || []).includes(i) : val === i);
      const ready = Q.multi ? (val || []).length > 0 : val != null;
      return `<div class="wrap notab">
        <div class="nav"><button class="icon-btn glass" data-back aria-label="Back">${ic('chevron-left')}</button>
          <div class="progress-top"><i style="width:${((q + 1) / 6) * 100}%"></i></div><span class="spacer"></span></div>
        <h1 class="ltitle" style="font:800 30px/1.1 var(--f-brand);letter-spacing:-.03em">${Q.title}</h1>
        <p class="lsub">${Q.sub}</p>
        <div class="stack mt24">${Q.opts.map(([icn, t, s], i) => `
          <button class="q-opt${isOn(i) ? ' on' : ''}" data-act="q-pick" data-i="${i}">
            <span class="badge-ic bg-sky">${ic(icn)}</span><span class="grow">${t}${s ? `<small>${s}</small>` : ''}</span>
            <span class="check">${ic('check')}</span></button>`).join('')}</div>
        <div class="foot-fixed"><button class="btn primary block" data-act="q-next" ${ready ? '' : 'disabled'}>Continue</button></div>
      </div>`;
    }
  };
  ACTIONS['q-pick'] = (t) => {
    const top = S.stack[S.stack.length - 1], Q = QUIZ[top.params.q], i = +t.dataset.i;
    if (Q.multi) { const a = S.onb[Q.key] || []; S.onb[Q.key] = a.includes(i) ? a.filter((x) => x !== i) : a.concat(i); }
    else S.onb[Q.key] = i;
    refresh();
    if (!Q.multi) setTimeout(() => { const s = S.stack[S.stack.length - 1]; if (s.name === 'quiz' && s.params.q === top.params.q) ACTIONS['q-next'](); }, 380);
  };
  ACTIONS['q-next'] = () => {
    const top = S.stack[S.stack.length - 1];
    if (top.params.q < QUIZ.length - 1) go('quiz', { q: top.params.q + 1 }); else go('firstset');
  };

  SCREENS.firstset = {
    render: () => `<div class="wrap notab">
      <div class="nav"><button class="icon-btn glass" data-back aria-label="Back">${ic('chevron-left')}</button><div class="progress-top"><i style="width:100%"></i></div><span class="spacer"></span></div>
      <h1 class="ltitle" style="font:800 30px/1.1 var(--f-brand);letter-spacing:-.03em">Let's make your first set</h1>
      <p class="lsub">Snap any page from your notes or textbook. It takes about 20 seconds.</p>
      <div class="card tap mt24" data-go="camera" data-how="up" data-params='{"flow":"onb"}' style="background:var(--night);color:#fff;padding:22px">
        <div class="row between"><span class="badge-ic" style="background:var(--tang);color:#fff;width:48px;height:48px;border-radius:16px">${ic('camera')}</span>${ic('arrow-right')}</div>
        <div class="h2 mt16" style="color:#fff">Scan a page</div><div style="opacity:.7;margin-top:4px;font-size:15px">Point your camera at a textbook, handout or your own notes</div>
      </div>
      <div class="list mt16">
        <div class="li" data-go="camera" data-how="up" data-params='{"flow":"onb"}'><span class="badge-ic bg-sky">${ic('image')}</span><div class="grow"><div class="t">Use our sample page</div><div class="s">A biology page about mitosis</div></div>${ic('chevron-right', 'm')}</div>
        <div class="li" data-act="soon" data-msg="Quizlet and Anki import"><span class="badge-ic bg-mint">${ic('layers')}</span><div class="grow"><div class="t">Import from Quizlet or Anki</div><div class="s">Bring every set you already have</div></div>${ic('chevron-right', 'm')}</div>
        <div class="li" data-act="soon" data-msg="PDF import"><span class="badge-ic bg-tang">${ic('file-up')}</span><div class="grow"><div class="t">Upload a PDF or slides</div><div class="s">From Files, Drive or email</div></div>${ic('chevron-right', 'm')}</div>
      </div>
    </div>`
  };
  ACTIONS.soon = (t) => toast(`${t.dataset.msg || 'This'} is in the full app`, 'info');

  /* ================= camera ================= */
  const QUAD_LOOSE = '14,12 86,10 90,78 11,82';
  const QUAD_PAGE = '4.6,3.4 95.2,4.4 97.6,85.6 3.4,86.4';
  SCREENS.camera = {
    cls: 'camera fixed', sb: 'white',
    render: () => `<div class="cam-view" style="top:calc(var(--sat) + 56px);bottom:auto;aspect-ratio:2/3;height:auto">
        <img src="${IMG}textbook.webp" alt="Camera view of a biology textbook page about mitosis">
        <svg class="cam-quad" viewBox="0 0 100 100" preserveAspectRatio="none"><polygon points="${QUAD_LOOSE}" style="opacity:.0"/></svg>
      </div>
      <div class="cam-top"><button class="icon-btn glass-dark" data-back aria-label="Close">${ic('x')}</button>
        <div class="chip glass-dark">${ic('scan-line', 's')} Auto capture</div>
        <button class="icon-btn glass-dark" aria-label="Flash off">${ic('zap-off')}</button></div>
      <div class="cam-hint" data-hint>Looking for a page…</div>
      <div class="cam-bottom">
        <div class="thumb" data-thumb style="visibility:hidden"><img src="${IMG}textbook.webp" alt=""><b>1</b></div>
        <button class="shutter" data-act="shoot" aria-label="Take photo"><i></i></button>
        <button class="btn white sm" data-act="cam-done" disabled>Done</button>
      </div>
      <div class="flash"></div>`,
    mount(el, p, ctx) {
      const poly = $('polygon', el), hint = $('[data-hint]', el);
      el._shot = false;
      play(ctx.script(), async (s) => {
        await s.nap(300); poly.style.opacity = 1;
        await s.nap(500); poly.setAttribute('points', '10,8 90,7 94,83 7,86');
        await s.nap(650); poly.setAttribute('points', QUAD_PAGE); hint.textContent = 'Page found · hold still';
        await s.nap(1300); if (!el._shot) ACTIONS.shoot(el);
      });
    }
  };
  ACTIONS.shoot = (t) => {
    const el = t.closest ? t.closest('.screen') : t;
    if (el._shot) return;
    el._shot = true;
    const f = $('.flash', el); f.classList.remove('go'); void f.offsetWidth; f.classList.add('go');
    $('[data-thumb]', el).style.visibility = 'visible';
    $('[data-hint]', el).textContent = 'Page 1 captured · add more or tap Done';
    $('polygon', el).setAttribute('points', QUAD_PAGE);
    $('[data-act="cam-done"]', el).disabled = false;
  };
  ACTIONS['cam-done'] = () => { const top = S.stack[S.stack.length - 1]; go('processing', { flow: top.params.flow }, 'replace'); };

  /* ================= processing ================= */
  SCREENS.processing = {
    render: () => `<div class="wrap notab" style="padding-top:calc(var(--sat) + 40px)">
      <div class="proc-page"><img src="${IMG}textbook.webp" alt=""><div class="sweep"></div></div>
      <h1 class="h2 center mt24">Making your study set</h1>
      <p class="lsub center">1 page · Biology</p>
      <div class="mt24">
        <div class="step active" data-s="0"><span class="dot"><span class="spin"></span></span><div><div class="t">Reading the page</div><div class="s">Text and diagram, on your iPhone</div></div></div>
        <div class="step wait" data-s="1"><span class="dot">${ic('check')}</span><div class="grow"><div class="t">Finding the key ideas</div><div class="chips mt8" data-concepts></div></div></div>
        <div class="step wait" data-s="2"><span class="dot">${ic('check')}</span><div><div class="t">Writing questions</div><div class="s"><span class="num" data-count>0</span> of 14</div></div></div>
        <div class="step wait" data-s="3"><span class="dot">${ic('check')}</span><div><div class="t">Checking each one against your page</div><div class="s" data-check>So nothing made up gets through</div></div></div>
      </div></div>`,
    mount(el, p, ctx) {
      const steps = $$('.step', el);
      const set = (i, state) => { const st = steps[i]; st.className = 'step ' + state; $('.dot', st).innerHTML = state === 'active' ? '<span class="spin"></span>' : CL.ic('check'); icons(); };
      play(ctx.script(), async (s) => {
        await s.nap(1100); set(0, 'done'); set(1, 'active');
        const box = $('[data-concepts]', el);
        for (const c of D.generated.concepts) { box.insertAdjacentHTML('beforeend', `<span class="chip pop">${c}</span>`); const ch = box.lastElementChild; await s.nap(30); ch.classList.add('on'); await s.nap(260); }
        await s.nap(300); set(1, 'done'); set(2, 'active');
        const cnt = $('[data-count]', el);
        for (let i = 1; i <= 14; i++) { cnt.textContent = i; await s.nap(70); }
        set(2, 'done'); set(3, 'active');
        await s.nap(900); $('[data-check]', el).textContent = '14 of 14 match the page'; set(3, 'done');
        await s.nap(700); go('review', { flow: p.flow }, 'replace');
      });
    }
  };

  /* ================= review generated set ================= */
  const TYPES = ['All', 'Recall', 'Multiple choice', 'Fill in', 'Diagram'];
  SCREENS.review = {
    render: (p) => {
      const g = D.generated, f = p.filter || 'All';
      const off = p.off || [];
      const count = g.items.length - off.length;
      return `<div class="wrap notab" style="padding-bottom:0">
        ${navBar('', { left: 'close', right: `<button class="link" data-act="soon" data-msg="Editing">Edit</button>` })}
        <h1 class="ltitle">${g.title}</h1><p class="lsub">${g.items.length} questions from your ${g.source}</p>
        <div class="ai-note mt16">${ic('sparkles', 'm')}<span>Made by AI from your page. Each question shows where it came from. Untick anything you don't want.</span></div>
        <div class="chips scroll mt16">${g.concepts.map((c) => `<span class="chip">${c}</span>`).join('')}</div>
        <div class="seg mt16" style="overflow-x:auto;scrollbar-width:none">${TYPES.map((t) => `<button class="${t === f ? 'on' : ''}" data-act="rv-filter" data-f="${t}">${t === 'All' ? `All ${g.items.length}` : t}</button>`).join('')}</div>
        <div class="list mt16">${g.items.map((it, i) => (f !== 'All' && it.t !== f) ? '' : `
          <div class="item${off.includes(i) ? ' off' : ''}">
            <button class="tick${off.includes(i) ? '' : ' on'}" data-act="rv-tick" data-i="${i}" aria-label="Include question">${ic('check')}</button>
            <div class="grow"><div class="q">${esc(it.q)}</div><div class="a">${esc(it.a)}</div>
              <div class="meta"><span class="pill sky">${it.t}</span><span class="chip src">${ic('book-open', 's')} ${it.src}</span></div></div></div>`).join('')}</div>
        <div class="foot-fixed"><button class="btn primary block" data-act="rv-add">Add ${count} to Bio 101 Midterm</button></div>
      </div>`;
    }
  };
  ACTIONS['rv-filter'] = (t) => { S.stack[S.stack.length - 1].params.filter = t.dataset.f; refresh(); };
  ACTIONS['rv-tick'] = (t) => {
    const p = S.stack[S.stack.length - 1].params, i = +t.dataset.i;
    p.off = (p.off || []).includes(i) ? p.off.filter((x) => x !== i) : (p.off || []).concat(i);
    refresh();
  };
  ACTIONS['rv-add'] = () => {
    const p = S.stack[S.stack.length - 1].params, n = D.generated.items.length - (p.off || []).length;
    toast(`Added ${n} questions to Bio 101 Midterm`);
    if (p.flow === 'onb') go('session', { mode: 'mini' }, 'replace');
    else go('today', {}, 'root');
  };

  /* ================= study session ================= */
  function sessionItems(mode) {
    if (mode === 'mini') return [D.session[1], D.session[0]];
    if (mode === 'fix') return [D.session[0], D.session[5]];
    return D.session;
  }
  function grade(text, ideas) {
    const ranges = [], hits = ideas.map(() => false);
    ideas.forEach((idea, k) => {
      const re = new RegExp(idea.re, 'gi'); let m;
      while ((m = re.exec(text))) { hits[k] = true; ranges.push([m.index, m.index + m[0].length]); if (!m[0].length) re.lastIndex++; }
    });
    ranges.sort((a, b) => a[0] - b[0]);
    const merged = [];
    ranges.forEach((r) => { const l = merged[merged.length - 1]; if (l && r[0] <= l[1] + 1) l[1] = Math.max(l[1], r[1]); else merged.push(r.slice()); });
    let html = '', pos = 0;
    merged.forEach(([a, b]) => { html += esc(text.slice(pos, a)) + `<mark class="hl">${esc(text.slice(a, b))}</mark>`; pos = b; });
    html += esc(text.slice(pos));
    return { hits, html, n: hits.filter(Boolean).length };
  }
  const diagramSVG = () => `<svg viewBox="0 0 240 150" width="100%" height="150" role="img" aria-label="A cell with chromosomes lined up across its middle" style="margin-top:14px">
      <ellipse cx="120" cy="75" rx="108" ry="66" fill="var(--sky-soft)" stroke="var(--sky)" stroke-width="2.5"/>
      ${[30, 52, 75, 98, 120].map((y) => `<path d="M22 75 Q70 ${y} 120 ${y}" fill="none" stroke="var(--sun)" stroke-width="1.6" opacity=".9"/><path d="M218 75 Q170 ${y} 120 ${y}" fill="none" stroke="var(--sun)" stroke-width="1.6" opacity=".9"/>`).join('')}
      <circle cx="20" cy="75" r="6" fill="var(--tang)"/><circle cx="220" cy="75" r="6" fill="var(--tang)"/>
      ${[38, 62, 88, 112].map((y) => `<g transform="translate(120 ${y})" stroke="#6E56CF" stroke-width="6" stroke-linecap="round"><line x1="-9" y1="-8" x2="9" y2="8"/><line x1="-9" y1="8" x2="9" y2="-8"/></g>`).join('')}
    </svg>`;

  SCREENS.session = {
    cls: 'sess fixed',
    render: (p) => {
      const items = sessionItems(p.mode), i = p.i || 0, res = p.res || [];
      return `<div class="sess-top"><button class="icon-btn" data-act="sess-close" aria-label="End session" style="background:var(--surface-3)">${ic('x')}</button>
        <div class="segs">${items.map((_, k) => `<i class="${res[k] || (k === i ? 'cur' : '')}"></i>`).join('')}</div>
        <span class="num" style="font-weight:700;font-size:14px;color:var(--fg-2);min-width:30px;text-align:right">${i + 1}/${items.length}</span></div>
        <div class="sess-body" data-body></div>
        <div class="sess-foot" data-foot></div>`;
    },
    mount(el, p) { renderQ(el, p); }
  };
  function nextQ(el, p, result) {
    const items = sessionItems(p.mode);
    p.res = (p.res || []).slice(); p.res[p.i || 0] = result;
    if ((p.i || 0) + 1 >= items.length) { go(p.mode === 'mini' ? 'readiness' : 'summary', { mode: p.mode, res: p.res }, 'replace'); return; }
    p.i = (p.i || 0) + 1;
    refresh();
  }
  function renderQ(el, p) {
    const items = sessionItems(p.mode), it = items[p.i || 0];
    const body = $('[data-body]', el), foot = $('[data-foot]', el);
    const src = (s) => `<span class="chip src">${ic('book-open', 's')} ${s}</span>`;
    const set = (b, f) => { if (b != null) body.innerHTML = b; foot.innerHTML = f; icons(); };

    if (it.type === 'recall') {
      set(`<div class="qcard"><div class="qtype">${ic(it.apply ? 'lightbulb' : 'pen-line', 's')} ${it.apply ? 'Apply it' : 'In your own words'} · ${it.concept}</div>
          <div class="qtext">${esc(it.q)}</div>
          <div class="mt16" data-zone><textarea class="answer" id="ans-${p.i || 0}" rows="4" placeholder="Type your answer…"></textarea>
          <div class="row mt8 between"><button class="chip" data-x="example">${ic('wand-sparkles', 's')} Use an example answer</button><button class="mic" data-x="mic" aria-label="Answer out loud">${ic('mic', 'm')}</button></div></div>
          <div data-result></div></div>`,
        `<button class="btn primary block" data-x="check" disabled>Check my answer</button><button class="btn ghost block" data-x="idk">I don't know yet</button>`);
      const ta = $('textarea', body), checkBtn = $('[data-x="check"]', foot);
      ta.oninput = () => { checkBtn.disabled = !ta.value.trim(); };
      const typeIn = async (txt) => { ta.value = ''; for (let k = 1; k <= txt.length; k++) { ta.value = txt.slice(0, k); await CL.sleep(reduce ? 0 : 22); } ta.oninput(); };
      $('[data-x="example"]', body).onclick = () => typeIn(it.example);
      $('[data-x="mic"]', body).onclick = async (e) => {
        const b = e.currentTarget; b.classList.add('live'); await CL.sleep(1300); b.classList.remove('live'); typeIn(it.example);
      };
      const reveal = (txt) => {
        const g = grade(txt, it.ideas), all = g.n === it.ideas.length, none = g.n === 0;
        $('[data-zone]', body).innerHTML = `<div class="row between" style="margin-bottom:8px"><span class="eyebrow">Your answer</span><span class="pill ${all ? 'mint' : none ? 'rose' : 'sun'} pop" data-score>${g.n} of ${it.ideas.length} key ideas</span></div>
          <div class="answer-out">${txt ? g.html : '<span class="faint">No answer</span>'}</div>
          <div class="ideas">${it.ideas.map((idea, k) => `<div class="idea ${g.hits[k] ? 'ok' : 'no'} rise">${ic(g.hits[k] ? 'circle-check' : 'circle-x')}<span>${g.hits[k] ? idea.label : 'Missing: ' + idea.label.toLowerCase()}</span></div>`).join('')}</div>`;
        $('[data-result]', body).innerHTML = `<div class="feedback ${all ? 'mint' : none ? 'rose' : 'sun'} rise"><b>${all ? 'Nailed it.' : none ? 'Not yet.' : 'Almost.'}</b> ${all ? 'Every key idea is there.' : esc(it.fix)}<div class="mt8">${src(it.src)}</div></div>`;
        set(null, `<button class="btn primary block" data-x="next">Continue</button>
          <div class="row" style="gap:10px"><button class="btn soft md grow" data-x="explain">${ic('message-circle', 'm')} Explain it</button><button class="btn soft md grow" data-x="regrade">${ic('flag', 'm')} Grade again</button></div>`);
        icons();
        play(CL.script(), async (s) => {
          for (const m of $$('mark', body)) { await s.nap(160); m.classList.add('on'); await s.nap(260); }
          for (const r of $$('.rise', body)) { r.classList.add('on'); await s.nap(140); }
          $('[data-score]', body).classList.add('on');
        });
        foot.onclick = (e) => {
          const x = e.target.closest('[data-x]'); if (!x) return;
          if (x.dataset.x === 'next') nextQ(el, p, all ? 'done' : none ? 'miss' : 'part');
          if (x.dataset.x === 'explain') explainSheet(it);
          if (x.dataset.x === 'regrade') toast(all || none ? 'A second check agrees with the grade' : 'A second check agrees: one key idea is missing', 'badge-check');
        };
      };
      foot.onclick = (e) => {
        const x = e.target.closest('[data-x]'); if (!x) return;
        if (x.dataset.x === 'check') reveal(ta.value.trim());
        if (x.dataset.x === 'idk') reveal('');
      };
      return;
    }

    if (it.type === 'mcq' || it.type === 'diagram') {
      set(`<div class="qcard"><div class="qtype">${ic(it.type === 'diagram' ? 'image' : 'list-checks', 's')} ${it.type === 'diagram' ? 'Diagram' : 'Multiple choice'} · ${it.concept}</div>
          <div class="qtext">${esc(it.q)}</div>${it.type === 'diagram' ? diagramSVG() : ''}
          <div class="opts">${it.options.map((o, k) => `<button class="opt" data-k="${k}"><span class="k">${'ABCD'[k]}</span>${o}</button>`).join('')}</div>
          <div data-result></div></div>`, '');
      $('.opts', body).onclick = (e) => {
        const b = e.target.closest('.opt'); if (!b || body._answered) return;
        body._answered = true;
        const k = +b.dataset.k, ok = k === it.correct;
        $$('.opt', body).forEach((o, j) => { if (j === it.correct) o.classList.add('right'); else if (j === k) o.classList.add('wrong'); else o.classList.add('dim'); });
        $('[data-result]', body).innerHTML = `<div class="feedback ${ok ? 'mint' : 'rose'} rise on"><b>${ok ? 'Right.' : 'Not quite.'}</b> ${esc(it.why)}<div class="mt8">${src(it.src)}</div></div>`;
        set(null, `<button class="btn primary block" data-x="next">Continue</button>${ok ? '' : `<button class="btn soft md block" data-x="explain">${ic('message-circle', 'm')} Explain it</button>`}`);
        foot.onclick = (ev) => { const x = ev.target.closest('[data-x]'); if (!x) return; if (x.dataset.x === 'next') nextQ(el, p, ok ? 'done' : 'miss'); else explainSheet(it); };
      };
      return;
    }

    if (it.type === 'flip') {
      set(`<div class="qtype" style="margin:4px 4px 10px">${ic('layers', 's')} Flashcard · ${it.concept}</div>
        <div class="flip" data-flip><div class="flip-in">
          <div class="face"><div class="big">${esc(it.front)}</div><div class="faint mt16" style="font-size:14px">Say the definition, then tap to check</div></div>
          <div class="face back"><div class="def">${esc(it.back)}</div><div class="mt16">${src(it.src)}</div></div></div></div>`,
        `<button class="btn primary block" data-x="flip">Show answer</button>`);
      const flip = $('[data-flip]', body);
      const showRate = () => {
        flip.classList.add('on');
        set(null, `<div class="faint center" style="font-size:13px;font-weight:600">How well did you know it?</div>
          <div class="rate"><button data-r="miss" style="background:var(--rose-soft);color:var(--rose)">Again<small>10 min</small></button>
          <button data-r="part" style="background:var(--sun-soft);color:#A87700">Hard<small>2 days</small></button>
          <button data-r="done" style="background:var(--mint-soft);color:var(--mint)">Good<small>4 days</small></button>
          <button data-r="done" style="background:var(--sky-soft);color:var(--sky-ink)">Easy<small>9 days</small></button></div>`);
        foot.onclick = (e) => { const r = e.target.closest('[data-r]'); if (r) nextQ(el, p, r.dataset.r); };
      };
      flip.onclick = showRate;
      foot.onclick = (e) => { if (e.target.closest('[data-x="flip"]')) showRate(); };
      return;
    }

    if (it.type === 'cloze') {
      set(`<div class="qcard"><div class="qtype">${ic('type', 's')} Fill in the blank · ${it.concept}</div>
          <div class="cloze-line">${esc(it.before)} <input id="cloze-${p.i}" class="answer-in" autocomplete="off" autocapitalize="off" spellcheck="false" aria-label="Missing word"> ${esc(it.after)}</div>
          <div data-result></div></div>`,
        `<button class="btn primary block" data-x="check" disabled>Check</button><button class="btn ghost block" data-x="hint">${ic('lightbulb', 'm')} Give me a hint</button>`);
      const inp = $('input', body), chk = $('[data-x="check"]', foot);
      inp.oninput = () => { chk.disabled = !inp.value.trim(); };
      inp.onkeydown = (e) => { if (e.key === 'Enter' && inp.value.trim()) chk.click(); };
      foot.onclick = (e) => {
        const x = e.target.closest('[data-x]'); if (!x) return;
        if (x.dataset.x === 'hint') { inp.placeholder = 'telo…'; toast('Hint: it starts with "telo"', 'lightbulb'); return; }
        if (x.dataset.x !== 'check') return;
        const v = inp.value.trim().toLowerCase(), ok = it.accept.includes(v);
        inp.outerHTML = `<span class="filled" style="background:${ok ? 'var(--mint-soft)' : 'var(--rose-soft)'}">${ok ? esc(it.answer) : `<s style="opacity:.6">${esc(v)}</s> ${esc(it.answer)}`}</span>`;
        $('[data-result]', body).innerHTML = `<div class="feedback ${ok ? 'mint' : 'rose'} rise on"><b>${ok ? 'Right.' : 'The answer is telophase.'}</b> ${ok ? 'Telophase is prophase in reverse: the nuclear envelopes come back.' : 'Think "telo" = end: it is the last phase, when the nuclear envelopes re-form.'}<div class="mt8">${src(it.src)}</div></div>`;
        set(null, `<button class="btn primary block" data-x="next">Continue</button>`);
        foot.onclick = (ev) => { if (ev.target.closest('[data-x="next"]')) nextQ(el, p, ok ? 'done' : 'miss'); };
      };
    }
  }
  function explainSheet(it) {
    sheet(`<div class="sheet-h"><div class="row"><span class="face-sm" style="width:40px;height:40px;border-radius:13px;overflow:hidden;background:var(--sky);display:block"><img src="${IMG}icon-cramless-capy.webp" alt="" style="width:100%;height:100%"></span><div><div class="h3">Cap explains</div><div class="faint" style="font-size:13px">From your textbook and Lecture 6</div></div></div><button class="icon-btn" style="background:var(--surface-3)" data-act="close-sheet" aria-label="Close">${ic('x')}</button></div>
      <div class="chat">
        <div class="bub cap" style="max-width:100%">Think of it this way: mitosis is a photocopier for cells. The copy has to be <b>complete</b>, so each new cell gets the same number of chromosomes as the original: 46 in a human body cell.
          <div class="chips mt8"><span class="chip src">${ic('book-open', 's')} Textbook p. 87</span><span class="chip src">${ic('mic', 's')} Lecture 6 · 12:05</span></div></div>
        <div class="bub cap" style="max-width:100%">Quick check: a skin cell with 46 chromosomes divides. How many does each new cell have?
          <div class="quiz-chips" data-qc><button data-v="23">23</button><button data-v="46">46</button><button data-v="92">92</button></div></div>
      </div>
      <button class="btn soft block mt16" data-act="close-sheet">Back to my session</button>`, {
      onMount(layer) {
        $('[data-qc]', layer).onclick = (e) => {
          const b = e.target.closest('button'); if (!b) return;
          const ok = b.dataset.v === '46';
          b.classList.add(ok ? 'right' : 'wrong');
          if (ok) { $('.chat', layer).insertAdjacentHTML('beforeend', `<div class="bub cap" style="max-width:100%">Exactly. I'll bring this back tomorrow so it sticks.</div>`); }
          else toast('Close. Copies are complete, so the number stays the same.', 'lightbulb');
        };
      }
    });
  }
  ACTIONS['sess-close'] = () => {
    sheet(`<div class="h2 center" style="margin-top:6px">End this session?</div><p class="lsub center">Your answers so far are saved, and the rest move to tomorrow.</p>
      <button class="btn primary block mt24" data-act="close-sheet">Keep going</button><button class="btn ghost block" data-act="sess-end">End session</button>`);
  };
  ACTIONS['sess-end'] = () => { closeSheet(); const top = S.stack[S.stack.length - 1]; if (top.params.mode === 'mini') go('readiness', {}, 'replace'); else back(); };

  /* ================= summary ================= */
  SCREENS.summary = {
    render: (p) => {
      const res = p.res || [], ok = res.filter((r) => r === 'done').length, n = sessionItems(p.mode).length;
      return `<div class="wrap notab celebrate" style="padding-top:calc(var(--sat) + 10px)">
        <img src="${IMG}cap-celebrate.webp" alt="Cap the capybara celebrating">
        <h1 class="ltitle" style="font:800 32px/1.05 var(--f-brand);letter-spacing:-.03em">Session done</h1>
        <p class="lsub">${n} questions in about ${Math.max(2, n + 1)} minutes</p>
        <div class="stat3 mt24"><div><b>${ok}/${n}</b><span>right first time</span></div><div><b style="color:var(--mint)">+4%</b><span>readiness</span></div><div><b style="color:var(--tang)">13</b><span>day streak</span></div></div>
        <div class="card mt16" style="text-align:left"><div class="row" style="gap:16px">${ring(92, 10, 64)}
          <div class="grow"><div class="h3">Bio 101 Midterm</div><div class="muted" style="font-size:14px;margin-top:3px">64% → 68% ready · 23 days left</div><div class="pill mint mt8">${ic('trending-up', 's')} On track for 90%</div></div></div></div>
        <div class="list mt16" style="text-align:left">
          <div class="li"><span class="badge-ic bg-mint">${ic('circle-check')}</span><div class="grow"><div class="t">Phases of mitosis</div><div class="s">Strong. Next review in 4 days</div></div></div>
          <div class="li"><span class="badge-ic bg-sun">${ic('rotate-ccw')}</span><div class="grow"><div class="t">Chromosome number</div><div class="s">Back tomorrow with a new question</div></div></div>
          <div class="li"><span class="badge-ic bg-sky">${ic('bell')}</span><div class="grow"><div class="t">Next session</div><div class="s">Tomorrow 7:30 PM · 12 minutes</div></div></div>
        </div>
        <div class="foot-fixed"><button class="btn primary block" data-act="sum-done">Done</button><button class="btn ghost block" data-act="sum-more">5 more questions</button></div>
      </div>`;
    },
    mount(el) { const r = $('.ring', el); snapRing(r, 64); setTimeout(() => setRing(r, 68), 500); }
  };
  ACTIONS['sum-done'] = () => go('today', {}, 'root');
  ACTIONS['sum-more'] = () => go('session', { mode: 'fix' }, 'replace');

  /* ================= onboarding result: readiness + plan ================= */
  SCREENS.readiness = {
    render: () => `<div class="wrap notab" style="padding-top:calc(var(--sat) + 20px)">
      <div class="center"><div data-ring style="display:inline-block">${ring(150, 15, 0, { sub: 'ready' })}</div></div>
      <h1 class="ltitle center" style="font:800 28px/1.1 var(--f-brand);letter-spacing:-.03em;margin-top:18px">You're 31% ready for your Bio 101 Midterm</h1>
      <p class="lsub center">Normal for 23 days out. Here's how you get to 90% by Fri, Nov 14.</p>
      <div class="card mt24">
        <div class="eyebrow">Building your plan</div>
        <div class="mt8">${[
          ['Mapped 6 topics from your page and syllabus', 'map'],
          ['15 minutes a day, rest on Saturdays', 'calendar-check'],
          ['Practice test on Mon, Nov 10', 'clipboard-check'],
          ['Reminder every evening at 7:30 PM', 'bell']
        ].map(([t]) => `<div class="step wait" style="padding:9px 0"><span class="dot">${ic('check')}</span><div class="t" style="font-size:15px">${t}</div></div>`).join('')}</div>
      </div>
      <div class="card mt16" data-chart style="opacity:0;transition:opacity .5s">
        <div class="row between"><div class="h3">Your path to 90%</div><span class="pill mint">${ic('target', 's')} Nov 14</span></div>
        <svg viewBox="0 0 300 120" width="100%" height="120" style="margin-top:10px" role="img" aria-label="Readiness rising from 31 percent today to 90 percent on exam day">
          <line x1="0" y1="22" x2="300" y2="22" stroke="var(--mint)" stroke-dasharray="4 5" stroke-width="1.5"/>
          <text x="296" y="16" text-anchor="end" font-size="10" font-weight="700" fill="var(--mint)">90% goal</text>
          <path d="M8 96 C 70 86, 120 64, 170 48 S 260 26, 292 22" fill="none" stroke="var(--tang)" stroke-width="3.5" stroke-linecap="round" data-path/>
          <circle cx="8" cy="96" r="5" fill="var(--tang)"/><circle cx="292" cy="22" r="5" fill="var(--mint)"/>
          <text x="8" y="116" font-size="10" fill="var(--fg-3)">Today 31%</text><text x="292" y="116" text-anchor="end" font-size="10" fill="var(--fg-3)">Exam day</text>
        </svg>
      </div>
      <div class="foot-fixed"><button class="btn primary block" data-act="to-paywall">Start my plan</button></div>
    </div>`,
    mount(el, p, ctx) {
      const r = $('.ring', el);
      snapRing(r, 0);
      play(ctx.script(), async (s) => {
        await s.nap(300); setRing(r, 31, { from: 0 });
        await s.nap(900);
        for (const st of $$('.step', el)) { st.className = 'step active'; $('.dot', st).innerHTML = '<span class="spin"></span>'; await s.nap(420); st.className = 'step done'; $('.dot', st).innerHTML = ic('check'); icons(); await s.nap(120); }
        const ch = $('[data-chart]', el); ch.style.opacity = 1;
        const path = $('[data-path]', el), L = path.getTotalLength();
        path.style.strokeDasharray = L; path.style.strokeDashoffset = L; void path.getBoundingClientRect();
        path.style.transition = 'stroke-dashoffset 1.2s ease'; path.style.strokeDashoffset = 0;
      });
    }
  };
  ACTIONS['to-paywall'] = () => go('paywall', { flow: 'onb' }, 'up');

  /* ================= paywall ================= */
  SCREENS.paywall = {
    cls: 'paywall', sb: 'white',
    render: (p) => {
      const P = D.prices, sel = S.plan, cur = P[sel];
      const cta = sel === 'monthly' ? `Subscribe for ${cur.price}/month` : sel === 'squad' ? 'Start the Squad free week' : 'Start my free week';
      const fine = sel === 'monthly' ? `${cur.price} a month. Cancel anytime in Settings, in two taps.` : `Free for 7 days, then ${cur.price} a year. We'll remind you 2 days before it ends. Cancel anytime in two taps.`;
      const stars = Array.from({ length: 14 }, (_, i) => `<i style="left:${(i * 37) % 100}%;top:${(i * 53) % 70 + 6}%;animation-delay:${(i % 5) * 0.6}s"></i>`).join('');
      return `<div class="pw-hero"><div class="stars">${stars}</div><img src="${IMG}cap-sleep.webp" alt="Cap asleep on a stack of index cards">
          <button class="icon-btn glass-dark" data-act="pw-close" aria-label="Close" style="position:absolute;left:14px;top:calc(var(--sat) + 4px);z-index:2">${ic('x')}</button></div>
        <div class="wrap notab" style="padding-top:22px">
          <h1 style="font:800 29px/1.08 var(--f-brand);letter-spacing:-.03em;margin:0;text-wrap:balance">Sleep the night before. You'll be ready.</h1>
          <p class="lsub">Your Bio 101 plan is set: 15 minutes a day until Nov 14.</p>
          <div class="stack mt16" style="gap:11px">
            ${[['camera', 'Unlimited scans, PDFs and lectures'], ['pen-line', 'Answers graded in your own words'], ['message-circle', 'A tutor that knows your notes'], ['target', 'Exam plans, practice tests and readiness']].map(([i, t]) => `<div class="benefit"><span class="badge-ic bg-tang" style="width:30px;height:30px;border-radius:9px">${ic(i, 's')}</span>${t}</div>`).join('')}
          </div>
          <div class="stack mt24" style="gap:14px">
            ${['yearly', 'monthly', 'squad'].map((k) => { const x = P[k]; return `<button class="plan${k === sel ? ' on' : ''}" data-act="pw-plan" data-k="${k}">
              ${x.badge ? `<span class="flag${k === 'squad' ? ' sky' : ''}">${x.trial ? '7 days free · ' : ''}${x.badge}</span>` : ''}
              <span class="radio"></span><span class="grow"><span class="nm">${x.label}</span><span class="sb2" style="display:block">${x.sub}</span></span>
              <span class="pr">${x.price}<small>per ${x.unit}</small></span></button>`; }).join('')}
          </div>
          <button class="btn primary block mt24" data-act="pw-buy">${cta}</button>
          <p class="legal mt8">${fine}</p>
          ${sel !== 'monthly' ? `<div class="card flat mt16"><div class="timeline">
            <div class="tl"><span class="nd" style="background:var(--tang);color:#fff">${ic('lock-open', 's')}</span><div><div class="t">Today</div><div class="s">Everything unlocks. Your plan starts.</div></div></div>
            <div class="tl"><span class="nd bg-sun">${ic('bell', 's')}</span><div><div class="t">Day 5</div><div class="s">We remind you the trial is ending.</div></div></div>
            <div class="tl"><span class="nd bg-sky">${ic('calendar-check', 's')}</span><div><div class="t">Day 7</div><div class="s">Billing starts, unless you cancel before.</div></div></div></div></div>` : ''}
          <button class="btn ghost block mt8" data-act="pw-close">Not now, keep the free plan</button>
          <p class="legal">Free includes unlimited flashcard reviews, 3 scans a week and 20 graded answers a day.<br>Restore purchases · Terms · Privacy</p>
        </div>`;
    }
  };
  ACTIONS['pw-plan'] = (t) => { S.plan = t.dataset.k; refresh(); };
  ACTIONS['pw-buy'] = () => { S.pro = true; go('purchased', {}, 'replace'); };
  ACTIONS['pw-close'] = () => {
    const top = S.stack[S.stack.length - 1];
    if (top.params.flow === 'onb') { go('today', {}, 'root'); setTimeout(() => toast('You’re on the free plan. Upgrade anytime.', 'info'), 600); }
    else back();
  };
  SCREENS.purchased = {
    render: () => `<div class="wrap notab celebrate" style="padding-top:calc(var(--sat) + 40px)">
      <img src="${IMG}cap-celebrate.webp" alt="Cap celebrating">
      <h1 class="ltitle" style="font:800 32px/1.05 var(--f-brand);letter-spacing:-.03em">You're in.</h1>
      <p class="lsub">${S.plan === 'monthly' ? 'Cramless Pro is on.' : 'Your free week has started. We’ll remind you on Oct 27, two days before it ends.'}</p>
      ${S.plan === 'squad' ? `<div class="card mt24" style="text-align:left"><div class="h3">Invite your squad</div><p class="muted" style="font-size:14px;margin:4px 0 12px">Three friends get Pro free. You'll see when they study.</p><button class="btn soft block" data-act="soon" data-msg="Squad invites">${ic('user-plus', 'm')} Invite friends</button></div>` : ''}
      <div class="foot-fixed"><button class="btn primary block" data-act="sum-done">Start today's session</button></div></div>`
  };

  /* ================= TODAY ================= */
  SCREENS.today = {
    render: () => `<div class="wrap">
      <div class="row between" style="align-items:flex-end;padding-top:8px">
        <div><div class="eyebrow">${D.todayLabel}</div><h1 class="ltitle">Today</h1></div>
        <div class="row" style="gap:8px;margin-bottom:2px"><span class="streak glass">${ic('flame', 'm')} 12</span><button class="avatar av-tang" data-go="settings" aria-label="Profile and settings" style="border:0;cursor:pointer">${D.user.initials}</button></div>
      </div>
      <div class="session-card mt16"><img class="cap" src="${IMG}cap-study.webp" alt="">
        <div class="eyebrow">Today's session</div>
        <div class="big num">15<small>min</small></div>
        <div style="opacity:.75;margin-top:6px;font-size:15px;max-width:62%">18 reviews · 6 new · 2 weak spots</div>
        <div class="chips mt16" style="max-width:66%"><span class="chip">Meiosis I vs II</span><span class="chip">Chromosome number</span></div>
        <button class="btn primary mt16" data-go="session" data-how="up" data-params='{"mode":"full"}' style="height:50px">${ic('play', 'm')} Start</button>
      </div>
      <div class="card tap mt16" data-go="exam"><div class="hero-exam">${ring(86, 10, bio.ready)}
        <div class="grow"><div class="eyebrow">Next exam</div><div class="h3" style="margin-top:4px">${bio.name}</div>
          <div class="muted" style="font-size:14px;margin-top:2px">${bio.date} · ${bio.days} days</div>
          <div class="pill mint mt8">${ic('trending-up', 's')} +${bio.delta}% this week</div></div>${ic('chevron-right', 'm')}</div></div>
      <div class="card mt16"><div class="capnote"><span class="face-sm"><img src="${IMG}icon-cramless-capy.webp" alt=""></span>
        <div class="grow"><div class="h3" style="font-size:16px">You keep mixing up anaphase I and anaphase II.</div>
          <div class="muted" style="font-size:14px;margin-top:3px">Missed 3 of the last 4 times. Want a 2-minute fix?</div>
          <div class="row mt16"><button class="btn dark sm" data-go="session" data-how="up" data-params='{"mode":"fix"}'>Fix it now</button><button class="btn ghost sm" data-act="later">Later</button></div></div></div></div>
      <div class="section-h"><h3>Other exams</h3><a data-go="progress" data-how="fade">See all</a></div>
      <div class="list">${D.exams.slice(1).map((e) => `<div class="li" data-act="soon" data-msg="${e.name}">
        ${ring(40, 5, e.ready, { label: false })}<div class="grow"><div class="t">${e.name}</div><div class="s">${e.date} · ${e.ready}% ready${e.days <= 3 ? ' · <b style="color:var(--rose)">soon</b>' : ''}</div></div>${ic('chevron-right', 'm')}</div>`).join('')}</div>
      <div class="section-h"><h3>Add material</h3></div>
      <div class="quick">
        <button data-go="camera" data-how="up">${ic('camera')}<span>Scan</span></button>
        <button data-act="soon" data-msg="PDF import">${ic('file-up')}<span>PDF</span></button>
        <button data-go="record" data-how="up">${ic('mic')}<span>Lecture</span></button>
        <button data-act="soon" data-msg="Paste text">${ic('clipboard')}<span>Paste</span></button>
      </div>
      <div class="card tap mt16" data-go="class"><div class="row between">
        <div><div class="eyebrow">Bio 101 · Fall '26</div><div class="h3" style="margin-top:6px">Priya, Jordan and Sam are studying now</div></div>
        <div class="avs">${D.classmates.filter((c) => c.now).map((c) => `<span class="avatar av-${c.c}">${c.i}</span>`).join('')}</div></div></div>
    </div>`
  };
  ACTIONS.later = () => toast('Cap will bring it up tomorrow', 'clock');

  /* ================= capture sheet ================= */
  ACTIONS.capture = () => {
    sheet(`<div class="sheet-h"><div class="h2">Add material</div><button class="icon-btn" style="background:var(--surface-3)" data-act="close-sheet" aria-label="Close">${ic('x')}</button></div>
      <div class="list" style="box-shadow:none;background:var(--surface-2)">
        ${[['camera', 'Scan pages', 'Textbooks, handouts, your notes', 'bg-tang', 'cap-scan'],
           ['mic', 'Record a lecture', 'Transcribed on your iPhone, works offline', 'bg-rose', 'cap-rec'],
           ['file-up', 'PDF or slides', 'From Files, Drive or email', 'bg-sky', ''],
           ['youtube', 'YouTube or a web page', 'Paste a link', 'bg-rose', ''],
           ['layers', 'Import Quizlet or Anki', 'Keep every set you have', 'bg-mint', ''],
           ['clipboard', 'Paste text', 'From anywhere', 'bg-night', ''],
           ['pen-line', 'Make cards yourself', 'Always free, no limits', 'bg-sun', '']]
          .map(([i, t, s, c, a]) => `<div class="li" data-act="${a || 'soon'}" data-msg="${t}"><span class="badge-ic ${c}">${ic(i)}</span><div class="grow"><div class="t">${t}</div><div class="s">${s}</div></div>${ic('chevron-right', 'm')}</div>`).join('')}
      </div>`);
  };
  ACTIONS['cap-scan'] = () => { closeSheet(true); go('camera', {}, 'up'); };
  ACTIONS['cap-rec'] = () => { closeSheet(true); go('record', {}, 'up'); };

  /* ================= LIBRARY ================= */
  SCREENS.library = {
    render: () => `<div class="wrap">
      <h1 class="ltitle" style="padding-top:8px">Library</h1>
      <div class="row mt16" style="background:var(--surface-3);border-radius:14px;height:42px;padding:0 12px;color:var(--fg-3)">${ic('search', 'm')}<span style="font-size:16px">Search cards, notes and lectures</span></div>
      <div class="section-h"><h3>Courses</h3><a data-act="soon" data-msg="New course">New</a></div>
      <div class="stack">${D.courses.map((c) => `<div class="card tap" ${c.name === 'Bio 101' ? 'data-go="exam"' : `data-act="soon" data-msg="${c.name}"`} style="padding:16px">
        <div class="row"><span class="badge-ic bg-${c.color}" style="width:44px;height:44px;border-radius:14px">${ic(c.color === 'sun' ? 'languages' : c.color === 'mint' ? 'brain' : c.color === 'tang' ? 'flask-conical' : 'microscope')}</span>
          <div class="grow"><div class="h3">${c.name}</div><div class="muted" style="font-size:14px;margin-top:2px">${c.exam}</div></div><span class="num" style="font-weight:800;font-size:18px">${c.m}%</span></div>
        <div class="bar mt16"><i class="${barC(c.m)}" style="width:${c.m}%"></i></div>
        <div class="row mt8 faint" style="font-size:13px;font-weight:600;gap:14px"><span>${c.sources} sources</span><span>${c.cards} cards</span></div></div>`).join('')}</div>
      <div class="section-h"><h3>Shared with you</h3></div>
      <div class="list"><div class="li" data-go="class"><span class="badge-ic bg-sky">${ic('users')}</span><div class="grow"><div class="t">Bio 101 · Fall '26</div><div class="s">34 classmates · 12 shared sets</div></div>${ic('chevron-right', 'm')}</div></div>
      <div class="section-h"><h3>Bring your stuff</h3></div>
      <div class="list">${[['layers', 'Import from Quizlet', 'Paste a link or your exported text', 'bg-mint'], ['download', 'Import from Anki', '.apkg decks, scheduling kept', 'bg-sky'], ['file-up', 'Upload PDFs or slides', 'Up to 300 pages at once', 'bg-tang']]
        .map(([i, t, s, c]) => `<div class="li" data-act="soon" data-msg="${t}"><span class="badge-ic ${c}">${ic(i)}</span><div class="grow"><div class="t">${t}</div><div class="s">${s}</div></div>${ic('chevron-right', 'm')}</div>`).join('')}</div>
    </div>`
  };

  /* ================= ASK (tutor) ================= */
  const compareBubble = () => `<div class="bub cap">Short version: <b>mitosis copies a cell</b>. <b>Meiosis makes egg and sperm cells</b> with half the chromosomes.
    <table class="cmp"><tr><th></th><th>Mitosis</th><th>Meiosis</th></tr>
      <tr><td>Purpose</td><td>Growth, repair</td><td>Sex cells</td></tr><tr><td>Divisions</td><td>1</td><td>2</td></tr>
      <tr><td>New cells</td><td>2, identical</td><td>4, all different</td></tr><tr><td>Chromosomes</td><td>46 → 46</td><td>46 → 23</td></tr></table>
    <div class="chips mt8"><span class="chip src">${ic('book-open', 's')} Textbook p. 87</span><span class="chip src">${ic('mic', 's')} Lecture 6 · 03:12</span></div></div>
    <div class="bub cap">Quick check before we go on: how many cells does meiosis end with?<div class="quiz-chips" data-qc2><button data-v="2">2</button><button data-v="4">4</button><button data-v="8">8</button></div></div>`;
  function seedChat() {
    if (S.chat) return;
    S.chat = [{ who: 'me', html: esc(D.chatSeed[0].text) }, { who: 'raw', html: compareBubble() }];
  }
  const capReply = (q) => {
    const t = q.toLowerCase();
    if (/analog/.test(t)) return 'Mitosis is photocopying a whole recipe book: you get two complete copies. Meiosis is building a new book from one copy of each recipe, half from mom’s book and half from dad’s, with a few pages swapped. Half the size, and every book is different.';
    if (/anaphase|metaphase|prophase|telophase|phase/.test(t)) return S.hints ? 'Let’s work it out together. In which phase do the chromosomes line up in the middle, and what has to happen right after that?' : 'In order: prophase (chromosomes condense), metaphase (they line up in the middle), anaphase (chromatids pulled apart), telophase (nuclear envelopes re-form).';
    return S.hints ? 'Good question. Before I answer: what do your notes say happens to the chromosome number? Have a guess and I’ll check it against Lecture 6.' : 'Here’s what your material says: mitosis keeps the chromosome number the same (46 → 46), which is why it is used for growth and repair.';
  };
  SCREENS.ask = {
    cls: 'fixed',
    render: () => {
      seedChat();
      return `<div class="scroller" data-scroll><div class="wrap" style="padding-bottom:calc(var(--sab) + 160px)">
        <div class="row between" style="padding-top:8px;align-items:flex-end"><h1 class="ltitle">Ask Cap</h1>
          <button class="chip" data-act="soon" data-msg="Switching material">${ic('book-open', 's')} Bio 101 · 4 sources</button></div>
        <div class="seg mt16"><button class="${S.hints ? 'on' : ''}" data-act="hints" data-v="1">Hints first</button><button class="${S.hints ? '' : 'on'}" data-act="hints" data-v="0">Just explain</button></div>
        <div class="chat mt16" data-chat>${S.chat.map((m) => (m.who === 'raw' ? m.html : `<div class="bub ${m.who}">${m.html}</div>`)).join('')}</div>
        <div class="chips mt16" data-sugg>${['Quiz me on this', 'Explain with an analogy', 'Make cards from this'].map((s) => `<button class="chip" data-act="sugg" data-v="${s}">${s}</button>`).join('')}</div>
      </div></div>
      <div class="composer glass"><button class="icon-btn" style="background:var(--surface-3)" data-act="soon" data-msg="Attaching a photo" aria-label="Attach">${ic('plus', 'm')}</button>
        <input id="ask-input" placeholder="Ask about your material…" autocomplete="off"><button class="icon-btn send" data-act="send" aria-label="Send">${ic('arrow-up', 'm')}</button></div>`;
    },
    mount(el) {
      const inp = $('#ask-input', el);
      inp.onkeydown = (e) => { if (e.key === 'Enter') ACTIONS.send(); };
      const qc = $('[data-qc2]', el);
      if (qc) qc.onclick = (e) => {
        const b = e.target.closest('button'); if (!b || qc._done) return;
        const ok = b.dataset.v === '4'; b.classList.add(ok ? 'right' : 'wrong');
        if (ok) { qc._done = true; addMsg('cap', 'Yes: four cells, each with 23 chromosomes. That halving is the whole point, so egg + sperm gets back to 46.'); }
        else toast('Not quite. Meiosis divides twice.', 'lightbulb');
      };
      const sc = $('[data-scroll]', el);
      requestAnimationFrame(() => { sc.scrollTop = sc.scrollHeight; });
    }
  };
  function addMsg(who, text, delay = 900) {
    const top = S.stack[S.stack.length - 1].el, el = $('[data-scroll]', top) || top, chat = $('[data-chat]', top);
    if (who === 'me') { S.chat.push({ who, html: esc(text) }); chat.insertAdjacentHTML('beforeend', `<div class="bub me">${esc(text)}</div>`); el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' }); return; }
    chat.insertAdjacentHTML('beforeend', '<div class="typing-dots" data-typing><i></i><i></i><i></i></div>');
    el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' });
    setTimeout(() => {
      const t = $('[data-typing]', chat); t && t.remove();
      const html = `${esc(text)}<div class="chips mt8"><span class="chip src">${ic('book-open', 's')} Textbook p. 87</span></div>`;
      S.chat.push({ who: 'cap', html });
      chat.insertAdjacentHTML('beforeend', `<div class="bub cap">${html}</div>`);
      icons();
      el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' });
    }, delay);
  }
  ACTIONS.send = () => { const inp = $('#ask-input'); const v = inp && inp.value.trim(); if (!v) return; inp.value = ''; addMsg('me', v); addMsg('cap', capReply(v)); };
  ACTIONS.hints = (t) => { S.hints = t.dataset.v === '1'; refresh(); };
  ACTIONS.sugg = (t) => {
    const v = t.dataset.v;
    if (v === 'Quiz me on this') { go('session', { mode: 'fix' }, 'up'); return; }
    addMsg('me', v);
    if (v === 'Make cards from this') addMsg('cap', 'Done. I added 4 cards to Bio 101 Midterm: mitosis vs meiosis purpose, number of divisions, number of new cells, and chromosome count. They show up in tomorrow’s session.');
    else addMsg('cap', capReply(v));
  };

  /* ================= PROGRESS ================= */
  SCREENS.progress = {
    render: () => {
      const heat = Array.from({ length: 84 }, (_, i) => { const v = (i * 7 + (i % 5) * 3) % 11; return i > 71 ? 'l' + (1 + (i % 4)) : v < 2 ? '' : v < 5 ? 'l1' : v < 8 ? 'l2' : v < 10 ? 'l3' : 'l4'; });
      const due = [18, 22, 9, 0, 26, 14, 17];
      return `<div class="wrap">
        <h1 class="ltitle" style="padding-top:8px">Progress</h1>
        <div class="card mt16">
          <div class="eyebrow">Bio 101 Midterm · Nov 14</div>
          <div class="row between" style="margin-top:8px;align-items:flex-end"><div class="row" style="gap:10px;align-items:baseline"><span style="font:800 44px/1 var(--f-round);letter-spacing:-.03em">B+</span><span class="muted" style="font-weight:600">projected today</span></div>
            <span class="pill mint" style="margin-bottom:6px">${ic('trending-up', 's')} A− on Nov 14</span></div>
          <svg viewBox="0 0 300 110" width="100%" height="110" style="margin-top:12px" role="img" aria-label="Readiness over the last two weeks and the projection to exam day">
            ${[30, 55, 80].map((y) => `<line x1="0" x2="300" y1="${y}" y2="${y}" stroke="var(--hair)"/>`).join('')}
            <path d="M0 92 L20 88 L40 86 L60 80 L80 81 L100 74 L120 70 L140 66 L160 62 L180 58" fill="none" stroke="var(--tang)" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
            <path d="M180 58 C 220 44, 250 32, 296 22" fill="none" stroke="var(--tang)" stroke-width="3" stroke-dasharray="5 6" stroke-linecap="round" opacity=".55"/>
            <circle cx="180" cy="58" r="5" fill="var(--tang)"/>
            <text x="180" y="44" text-anchor="middle" font-size="11" font-weight="700" fill="var(--fg)">64%</text>
            <text x="0" y="108" font-size="10" fill="var(--fg-3)">Oct 8</text><text x="180" y="108" text-anchor="middle" font-size="10" fill="var(--fg-3)">Today</text><text x="300" y="108" text-anchor="end" font-size="10" fill="var(--fg-3)">Nov 14</text>
          </svg>
          <p class="faint" style="font-size:12.5px;margin:8px 0 0">A projection from your recall history, not a promise.</p>
        </div>
        <div class="section-h"><h3>Mastery</h3><a data-go="exam">By topic</a></div>
        <div class="tiles">${bio.topics.map((t) => t.m == null
          ? `<div class="tile none"><div class="n">${t.name}</div><div class="faint" style="font-size:13px;font-weight:600">No material yet · <span class="link" data-act="soon" data-msg="Adding material">Add</span></div></div>`
          : `<div class="tile"><span class="fill ${barC(t.m)}" style="height:${t.m}%"></span><div class="n">${t.name}</div><div class="v">${t.m}%</div></div>`).join('')}</div>
        <div class="section-h"><h3>Memory</h3></div>
        <div class="card"><div class="row between"><div><div class="h3">You remember 91% of what you review</div><div class="muted" style="font-size:14px;margin-top:3px">Target 90% · cards come back right before you'd forget them</div></div></div>
          <div class="eyebrow mt24" style="margin-bottom:10px">Reviews due, next 7 days</div>
          <div class="bars7">${due.map((v, i) => `<div><b style="height:${Math.max(4, v * 3)}px;${v ? '' : 'background:var(--surface-3)'}"></b><span>${['Th', 'Fr', 'Sa', 'Su', 'Mo', 'Tu', 'We'][i]}</span></div>`).join('')}</div></div>
        <div class="section-h"><h3>Streak</h3></div>
        <div class="card"><div class="row between" style="margin-bottom:14px"><div class="row" style="gap:8px"><span style="color:var(--tang)">${ic('flame')}</span><b style="font:800 20px/1 var(--f-round)">12 days</b></div><span class="faint" style="font-size:13px;font-weight:600">Best: 21 · 2 freezes saved</span></div>
          <div class="heat">${heat.map((c) => `<i class="${c}"></i>`).join('')}</div></div>
      </div>`;
    }
  };

  /* ================= EXAM DETAIL ================= */
  SCREENS.exam = {
    render: () => `<div class="wrap notab">
      ${navBar(bio.name, { right: `<button class="icon-btn glass" data-act="soon" data-msg="Exam settings" aria-label="More">${ic('ellipsis')}</button>` })}
      <div class="center mt8">${ring(170, 16, bio.ready, { sub: 'ready' })}</div>
      <h1 class="h2 center mt16">${bio.date}</h1>
      <p class="lsub center">${bio.days} days to go · projected ${bio.projected} · ${bio.format}</p>
      <div class="card flat mt24"><div class="row" style="align-items:flex-start"><span class="badge-ic bg-sun">${ic('info')}</span>
        <div class="grow"><div class="h3" style="font-size:16px">5 of 7 topics have material</div><div class="muted" style="font-size:14px;margin-top:3px">Your syllabus lists DNA replication, and you haven't added anything for it yet.</div>
        <button class="btn dark sm mt16" data-act="capture">${ic('plus', 's')} Add material</button></div></div></div>
      <div class="section-h"><h3>Topics</h3></div>
      <div class="list">${bio.topics.map((t) => `<div class="li noicon" style="display:block"><div class="row between"><span class="t" style="font-size:15px">${t.name}</span>${t.m == null ? '<span class="pill rose">No material</span>' : pct(t.m)}</div>
        ${t.m == null ? '' : `<div class="bar mt8"><i class="${barC(t.m)}" style="width:${t.m}%"></i></div>`}</div>`).join('')}</div>
      <div class="section-h"><h3>Your plan</h3><a data-act="soon" data-msg="Plan settings">Adjust</a></div>
      <div class="card"><div class="week">${bio.plan.map((d) => `<div class="d">${d.d}<div class="p ${d.today ? 'today' : d.min ? 'on' : 'rest'}">${d.min ? d.min + 'm' : 'rest'}</div></div>`).join('')}</div></div>
      <div class="list mt16">
        <div class="li"><span class="badge-ic bg-tang">${ic('clipboard-check')}</span><div class="grow"><div class="t">Practice test · Mon, Nov 10</div><div class="s">40 min, in your professor's format</div></div><button class="btn soft sm" data-act="soon" data-msg="Practice tests">Preview</button></div>
        <div class="li"><span class="badge-ic bg-night">${ic('moon')}</span><div class="grow"><div class="t">Night before · Thu, Nov 13</div><div class="s">A 20-minute review of weak spots, then sleep</div></div></div>
      </div>
      <div class="section-h"><h3>Materials</h3></div>
      <div class="list">${bio.materials.map((m) => `<div class="li"><span class="badge-ic bg-sky">${ic(m.icon)}</span><div class="grow"><div class="t">${m.name}</div><div class="s">${m.meta}</div></div></div>`).join('')}</div>
    </div>`
  };

  /* ================= RECORD LECTURE ================= */
  SCREENS.record = {
    cls: 'rec', sb: 'white',
    render: () => `<div class="wrap notab" style="padding-bottom:calc(var(--sab) + 140px)">
      <div class="nav"><button class="icon-btn glass-dark" data-back aria-label="Close">${ic('x')}</button><div class="ttl"><span class="pill rose" style="background:rgba(255,90,120,.18)"><span style="width:8px;height:8px;border-radius:50%;background:var(--rose);display:inline-block"></span> Recording</span></div><span class="spacer"></span></div>
      <div class="center" style="color:#fff"><div class="eyebrow" style="color:#8A97AE">Bio 101 · Lecture 7</div>
        <div class="num" data-timer style="font:800 56px/1 var(--f-round);letter-spacing:-.03em;margin-top:10px">12:41</div></div>
      <div class="wave mt16" data-wave>${Array.from({ length: 34 }, () => '<i style="height:8px"></i>').join('')}</div>
      <div class="row" style="justify-content:center;gap:8px;color:#8A97AE;font-size:13px;font-weight:600">${ic('smartphone', 's')} Transcribed on your iPhone. Works offline.</div>
      <div class="mt24" data-lines></div>
      <div style="position:absolute;left:0;right:0;bottom:0;padding:16px 24px calc(var(--sab) + 18px);display:flex;align-items:center;justify-content:space-between;background:linear-gradient(transparent,#0B1220 30%)">
        <button class="btn soft sm" data-act="rec-flag">${ic('flag', 's')} Confusing</button>
        <button class="stop" data-act="rec-stop" aria-label="Stop recording"><i></i></button>
        <button class="btn soft sm" data-act="soon" data-msg="Pausing">${ic('pause', 's')} Pause</button></div>
    </div>`,
    mount(el, p, ctx) {
      const timer = $('[data-timer]', el), bars = $$('[data-wave] i', el), box = $('[data-lines]', el);
      let secs = 761;
      play(ctx.script(), async (s) => { for (;;) { await s.nap(1000); secs++; timer.textContent = `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`; } });
      play(ctx.script(), async (s) => { for (;;) { bars.forEach((b, i) => { b.style.height = (8 + Math.abs(Math.sin(Date.now() / 300 + i * 0.7)) * 50 * Math.random()) + 'px'; }); await s.nap(160); } });
      play(ctx.script(), async (s) => {
        for (const l of D.lecture) {
          await s.nap(1500);
          box.insertAdjacentHTML('beforeend', `<div class="tline${l.flag ? ' flag' : ''}"><span class="ts">${l.t}</span>${esc(l.text)}${l.flag ? `<div class="mt8"><span class="pill tang">${ic('star', 's')} Said: on the midterm</span></div>` : ''}</div>`);
          icons();
          el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' });
        }
      });
    }
  };
  ACTIONS['rec-flag'] = () => toast('Marked at 12:58. Cap will explain it later.', 'flag');
  ACTIONS['rec-stop'] = () => go('lecnotes', {}, 'replace');
  SCREENS.lecnotes = {
    render: () => `<div class="wrap notab">
      ${navBar('', { left: 'close' })}
      <div class="eyebrow">Bio 101 · Lecture 7 · 52 min</div>
      <h1 class="ltitle">Cell division, part 2</h1>
      <div class="ai-note mt16">${ic('sparkles', 'm')}<span>Notes from your transcript. Tap a time to hear that moment.</span></div>
      <div class="card mt16" style="border:2px solid var(--tang)"><div class="row" style="gap:8px;color:var(--tang);font-weight:700;font-size:14px">${ic('star', 's')} Your professor said this will be on the midterm</div>
        <div class="h3 mt8">Anaphase: sister chromatids are pulled apart to opposite poles.</div><span class="chip src mt8">${ic('play', 's')} 12:05</span></div>
      <div class="list mt16">${[['03:12', 'Prophase: chromatin condenses into visible chromosomes'], ['05:40', 'Nuclear envelope breaks down; the spindle forms from the centrosomes'], ['07:40', 'Metaphase: chromosomes line up on the metaphase plate'], ['15:20', 'Telophase is prophase in reverse: the nuclear envelopes re-form'], ['12:58', 'You marked this as confusing: why the spindle attaches at the centromere']]
        .map(([t, s], i) => `<div class="li noicon" style="align-items:flex-start"><span class="chip src" style="flex:none">${ic('play', 's')} ${t}</span><div class="grow" style="font-size:15px;${i === 4 ? 'color:var(--rose);font-weight:600' : ''}">${s}</div></div>`).join('')}</div>
      <div class="foot-fixed"><button class="btn primary block" data-act="lec-add">Add 12 questions to Bio 101 Midterm</button></div>
    </div>`
  };
  ACTIONS['lec-add'] = () => { go('today', {}, 'root'); setTimeout(() => toast('Added 12 questions from Lecture 7'), 500); };

  /* ================= CLASS SPACE ================= */
  SCREENS['class'] = {
    render: () => `<div class="wrap notab">
      ${navBar('', { right: `<button class="icon-btn glass" data-act="soon" data-msg="Inviting classmates" aria-label="Invite">${ic('user-plus')}</button>` })}
      <div class="eyebrow">Class space</div><h1 class="ltitle">Bio 101 · Fall '26</h1><p class="lsub">34 classmates · Prof. Alvarez · invite-only</p>
      <div class="card mt16" style="background:var(--night);color:#fff"><div class="row between"><div><div class="h3" style="color:#fff">Live quiz battle</div><div style="opacity:.7;font-size:14px;margin-top:3px">10 questions from the class's shared sets</div></div>${ic('swords', 'l')}</div>
        <button class="btn primary block mt16" data-act="soon" data-msg="Live battles">Challenge the class</button></div>
      <div class="section-h"><h3>This week</h3><span class="faint" style="font-size:13px;font-weight:600">Minutes studied · opt-in</span></div>
      <div class="list">${D.classmates.map((c, i) => `<div class="li"><span class="num faint" style="width:16px;font-weight:700">${i + 1}</span><span class="avatar av-${c.c}" style="width:34px;height:34px;font-size:12px">${c.i}</span>
        <div class="grow"><div class="t">${c.n}${c.now ? ' <span class="pill mint" style="height:20px;font-size:11px;margin-left:4px">studying now</span>' : ''}</div></div><span class="num" style="font-weight:700${c.me ? ';color:var(--tang)' : ''}">${c.min} min</span></div>`).join('')}</div>
      <div class="section-h"><h3>Shared sets</h3></div>
      <div class="list">${[['Unit 3: Cell biology', 'Priya · 52 saves'], ['Lab safety quiz', 'Jordan · 31 saves'], ['Lecture 7 questions', 'You · 9 saves']]
        .map(([t, s]) => `<div class="li" data-act="soon" data-msg="${t}"><span class="badge-ic bg-sky">${ic('layers')}</span><div class="grow"><div class="t">${t}</div><div class="s">${s}</div></div>${ic('chevron-right', 'm')}</div>`).join('')}</div>
    </div>`
  };

  /* ================= SETTINGS ================= */
  SCREENS.settings = {
    render: () => {
      const tog = (k, on) => `<button class="tog" data-act="tog" data-k="${k}" role="switch" aria-checked="${on}" style="width:51px;height:31px;border-radius:999px;border:0;padding:2px;background:${on ? 'var(--mint)' : 'var(--surface-3)'};cursor:pointer;transition:background .2s;flex:none"><span style="display:block;width:27px;height:27px;border-radius:50%;background:#fff;box-shadow:0 2px 5px rgba(0,0,0,.2);transform:translateX(${on ? 20 : 0}px);transition:transform .25s var(--spring)"></span></button>`;
      S.toggles = S.toggles || { cloud: true, photos: true, device: true, hints: true, remind: true };
      const T = S.toggles;
      return `<div class="wrap notab">
        ${navBar('Profile')}
        <div class="card"><div class="row"><span class="avatar av-tang" style="width:56px;height:56px;font-size:20px">${D.user.initials}</span>
          <div class="grow"><div class="h3">${D.user.first} R.</div><div class="muted" style="font-size:14px">${S.pro ? 'Cramless Pro · free week ends Oct 29' : 'Free plan'}</div></div>
          ${S.pro ? '' : '<button class="btn primary sm" data-go="paywall" data-how="up">Go Pro</button>'}</div></div>
        <div class="section-h"><h3>Study</h3></div>
        <div class="list">
          <div class="li noicon"><div class="grow t">Daily goal</div><span class="muted">15 min</span></div>
          <div class="li noicon"><div class="grow t">Evening reminder</div><span class="muted">7:30 PM</span>${tog('remind', T.remind)}</div>
          <div class="li noicon" data-go="lock" data-how="fade"><div class="grow t">Widgets and Lock Screen</div>${ic('chevron-right', 'm')}</div>
        </div>
        <div class="section-h"><h3>AI and privacy</h3></div>
        <div class="list">
          <div class="li noicon"><div class="grow"><div class="t">Use cloud AI</div><div class="s">Reads your material, writes questions, grades answers</div></div>${tog('cloud', T.cloud)}</div>
          <div class="li noicon"><div class="grow"><div class="t">Send photos to AI</div><div class="s">Needed for diagrams and handwriting</div></div>${tog('photos', T.photos)}</div>
          <div class="li noicon"><div class="grow"><div class="t">On-device first</div><div class="s">Use your iPhone's own AI whenever it can do the job</div></div>${tog('device', T.device)}</div>
          <div class="li noicon"><div class="grow"><div class="t">Tutor gives hints first</div><div class="s">Cap asks a question before it explains</div></div>${tog('hints', T.hints)}</div>
          <div class="li noicon" data-act="soon" data-msg="Deleting AI data"><div class="grow t" style="color:var(--rose)">Delete everything sent to AI</div></div>
        </div>
        <p class="faint" style="font-size:13px;margin:10px 4px 0">Your notes are never used to train AI models. Cloud requests go through our server, never straight from your phone to an AI company.</p>
        <div class="section-h"><h3>Appearance</h3></div>
        <div class="seg">${['system', 'light', 'dark'].map((t) => `<button class="${S.theme === t ? 'on' : ''}" data-act="theme" data-v="${t}">${t[0].toUpperCase() + t.slice(1)}</button>`).join('')}</div>
        <div class="section-h"><h3>Prototype</h3></div>
        <div class="list"><div class="li noicon" data-act="restart"><div class="grow t">Restart from the welcome screen</div>${ic('rotate-ccw', 'm')}</div></div>
      </div>`;
    }
  };
  ACTIONS.tog = (t) => { S.toggles[t.dataset.k] = !S.toggles[t.dataset.k]; if (t.dataset.k === 'hints') S.hints = S.toggles.hints; refresh(); };
  ACTIONS.theme = (t) => {
    S.theme = t.dataset.v;
    if (S.theme === 'system') document.documentElement.removeAttribute('data-theme'); else document.documentElement.setAttribute('data-theme', S.theme);
    refresh();
  };
  ACTIONS.restart = () => { S.onb = { goal: null, when: null, mins: null, sources: [] }; S.chat = null; S.pro = false; go('welcome', {}, 'root'); };

  /* ================= LOCK SCREEN (widgets + Live Activity) ================= */
  SCREENS.lock = {
    cls: 'lock fixed', sb: 'white', clock: false,
    render: () => `<div style="padding:0 16px">
      <div class="date">Wednesday, October 22</div><div class="clock">7:31</div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:18px">
        <div class="lw"><div class="row" style="gap:6px;font-size:12px;font-weight:700;opacity:.85">${ic('flame', 's')} CRAMLESS</div><div style="font:800 26px/1.1 var(--f-round);margin-top:6px">18 due</div><div style="font-size:13px;opacity:.85">15 min keeps your streak</div></div>
        <div class="lw"><div class="row" style="gap:6px;font-size:12px;font-weight:700;opacity:.85">${ic('target', 's')} BIO MIDTERM</div><div style="font:800 26px/1.1 var(--f-round);margin-top:6px">64%</div><div style="font-size:13px;opacity:.85">23 days · +5 this week</div></div>
      </div>
      <div style="position:absolute;left:12px;right:12px;bottom:calc(var(--sab) + 60px);display:flex;flex-direction:column;gap:10px">
        <div class="live-act"><img src="${IMG}icon-cramless-capy.webp" alt="" style="width:44px;height:44px;border-radius:12px"><div class="grow"><div style="font-weight:700">Session in progress</div><div style="font-size:13px;opacity:.75">Question 9 of 18 · 6 min left</div><div class="bar mt8" style="background:rgba(255,255,255,.2)"><i class="c-tang" style="width:50%"></i></div></div></div>
        <div class="live-act" style="background:rgba(255,255,255,.88);color:#14213D"><img src="${IMG}icon-cramless-capy.webp" alt="" style="width:38px;height:38px;border-radius:10px"><div class="grow"><div class="row between"><b style="font-size:14px">Cramless</b><span style="font-size:12px;opacity:.6">now</span></div><div style="font-size:14px">15 minutes tonight and your 12-day streak is safe.</div></div></div>
      </div>
      <button class="btn glass-dark sm" data-back style="position:absolute;left:50%;transform:translateX(-50%);bottom:calc(var(--sab) + 12px)">Back to the app</button>
    </div>`
  };

  /* ================= prototype menu ================= */
  const MENU = [['welcome', 'Welcome', 'root'], ['onb', 'Onboarding, live demos', 'root'], ['quiz', 'Personalisation questions', 'root', { q: 0 }], ['camera', 'Scan a page', 'up', { flow: 'onb' }], ['review', 'Review a generated set', 'push', {}],
    ['session', 'Study session', 'up', { mode: 'full' }], ['readiness', 'Readiness and plan', 'push', {}], ['paywall', 'Paywall', 'up', {}], ['today', 'Today', 'root'], ['library', 'Library', 'root'], ['ask', 'Ask Cap (tutor)', 'root'],
    ['progress', 'Progress', 'root'], ['exam', 'Exam detail', 'push'], ['record', 'Record a lecture', 'up'], ['class', 'Class space', 'push'], ['settings', 'Profile, AI and privacy', 'push'], ['lock', 'Widgets and Lock Screen', 'fade']];
  document.getElementById('protobtn').onclick = () => {
    sheet(`<div class="sheet-h"><div><div class="h2">Prototype screens</div><div class="faint" style="font-size:13px;margin-top:2px">Jump anywhere. Tap the top of the screen to reopen this.</div></div><button class="icon-btn" style="background:var(--surface-3)" data-act="close-sheet" aria-label="Close">${ic('x')}</button></div>
      <div class="list menu-list" style="box-shadow:none;background:var(--surface-2)">${MENU.map(([n, t], i) => `<div class="li noicon" data-act="menu-go" data-i="${i}"><div class="grow t">${t}</div>${ic('chevron-right', 'm')}</div>`).join('')}</div>`);
  };
  ACTIONS['menu-go'] = (t) => {
    const [n, , how, params] = MENU[+t.dataset.i];
    closeSheet(true);
    if (how !== 'root' && !S.stack.some((e) => TAB(e.name))) go('today', {}, 'root');
    go(n, params || {}, how);
  };
  const TAB = (n) => ['today', 'library', 'ask', 'progress'].includes(n);

  /* ================= boot ================= */
  const start = (location.hash.match(/screen=([a-z]+)/) || [])[1];
  if (start && SCREENS[start]) { if (!TAB(start) && start !== 'welcome') go('today', {}, 'root'); go(start, start === 'quiz' ? { q: 0 } : {}, TAB(start) || start === 'welcome' ? 'root' : 'push'); }
  else go('welcome', {}, 'root');
})();
