/* Live onboarding scenes. Each one replays the real feature's motion in miniature.
   Loops reset through a fade; Reduce Motion settles on the final frame; the trust page plays once. */
(() => {
  'use strict';
  const { $, $$, ic, ring, setRing, snapRing, reduce } = window.CL;

  const lines = (ws, key = []) => ws.map((w, i) => `<div class="ln${key.includes(i) ? ' k' : ''}" style="width:${w}%"></div>`).join('');

  async function fadeReset(sc, s, reset) {
    const stage = $('.stage', sc);
    stage.style.transition = 'opacity .3s ease';
    stage.style.opacity = 0;
    await s.nap(340);
    reset();
    stage.style.opacity = 1;
    await s.nap(260);
  }

  const SCENES = {
    /* 1. Capture: brackets lock onto a page, a scan sweeps, key lines get highlighted, cards pop out. */
    capture: {
      html: () => `<div class="stage" style="position:absolute;inset:0">
        <div class="capwrap" style="position:absolute;left:17%;right:17%;top:7%;height:64%;transform:rotate(-2deg)">
          <div class="paper" style="inset:0;padding:16px 14px;overflow:hidden">
            <div class="ln h"></div>
            ${lines([94, 86, 90], [1])}
            <div style="display:flex;gap:6px;margin:9px 0 11px">${[0, 1, 2, 3].map(() => '<div style="flex:1;aspect-ratio:1;border-radius:50%;background:#E8EEF7;border:2px solid #C9D6EA"></div>').join('')}</div>
            ${lines([88, 70, 92, 64, 80], [2, 3])}
            <div class="scanline" style="top:-40px"></div>
          </div>
          <span class="bracket tl" style="left:-10px;top:-10px;transform:translate(-14px,-14px)"></span>
          <span class="bracket tr" style="right:-10px;top:-10px;transform:translate(14px,-14px)"></span>
          <span class="bracket bl" style="left:-10px;bottom:-10px;transform:translate(-14px,14px)"></span>
          <span class="bracket br" style="right:-10px;bottom:-10px;transform:translate(14px,14px)"></span>
        </div>
        <div class="mini-card" style="bottom:96px"><span>What does mitosis make?</span><span class="chip src">p. 87</span></div>
        <div class="mini-card" style="bottom:53px"><span>Name the 4 phases in order</span><span class="chip src">p. 87</span></div>
        <div class="mini-card" style="bottom:10px"><span>What is cytokinesis?</span><span class="chip src">p. 87</span></div>
      </div>`,
      async run(sc, s) {
        const br = $$('.bracket', sc), scan = $('.scanline', sc), keys = $$('.ln.k', sc), cards = $$('.mini-card', sc);
        const reset = () => {
          br.forEach((b) => { b.style.opacity = 0; b.style.transform = b.dataset.t0 || (b.dataset.t0 = b.style.transform); });
          scan.style.transition = 'none'; scan.style.top = '-40px'; scan.style.opacity = 0;
          keys.forEach((k) => k.classList.remove('mark'));
          cards.forEach((c) => c.classList.remove('on'));
        };
        const final = () => { br.forEach((b) => { b.style.opacity = 1; b.style.transform = 'none'; }); keys.forEach((k) => k.classList.add('mark')); cards.forEach((c) => c.classList.add('on')); };
        reset();
        if (reduce) { final(); return; }
        for (;;) {
          await s.nap(450);
          br.forEach((b) => { b.style.opacity = 1; b.style.transform = 'none'; });
          await s.nap(650);
          scan.style.opacity = 1;
          void scan.offsetHeight;
          scan.style.transition = 'top 1.1s ease-in-out, opacity .3s';
          scan.style.top = '100%';
          await s.nap(1100);
          scan.style.opacity = 0;
          for (const k of keys) { k.classList.add('mark'); await s.nap(240); }
          await s.nap(250);
          for (const c of cards) { c.classList.add('on'); await s.nap(170); }
          await s.nap(2400);
          await fadeReset(sc, s, reset);
        }
      }
    },

    /* 2. Grade: an answer types itself, the highlighter marks the key ideas, the gap is named. */
    grade: {
      html: () => `<div class="stage" style="position:absolute;inset:0;padding:18px;display:flex;flex-direction:column;gap:12px">
        <div class="row between"><span class="qtype">${ic('pen-line', 's')} In your own words</span><span class="pill sun pop" data-score>2 of 3 · Almost</span></div>
        <div style="font:700 19px/1.25 var(--f-ui);letter-spacing:-.015em">Why do cells divide by mitosis?</div>
        <div class="answer-out" style="font-size:16px;min-height:92px" data-ans></div>
        <div class="ideas" style="margin-top:2px">
          <div class="idea ok rise">${ic('circle-check')}<span>Growth and repair</span></div>
          <div class="idea ok rise">${ic('circle-check')}<span>Genetically identical cells</span></div>
          <div class="idea no rise">${ic('circle-x')}<span>Missing: same number of chromosomes</span></div>
        </div>
      </div>`,
      async run(sc, s) {
        const ans = $('[data-ans]', sc), score = $('[data-score]', sc), ideas = $$('.idea', sc);
        const text = 'So the body can grow and repair tissue, making two identical cells.';
        const marked = 'So the body can <mark class="hl">grow and repair tissue</mark>, making two <mark class="hl">identical cells</mark>.';
        const reset = () => { ans.innerHTML = '<span class="caret"></span>'; score.classList.remove('on'); ideas.forEach((i) => i.classList.remove('on')); };
        const final = () => { ans.innerHTML = marked; $$('mark', ans).forEach((m) => m.classList.add('on')); ideas.forEach((i) => i.classList.add('on')); score.classList.add('on'); };
        reset();
        if (reduce) { final(); return; }
        for (;;) {
          await s.nap(500);
          for (let i = 1; i <= text.length; i++) { ans.innerHTML = text.slice(0, i) + '<span class="caret"></span>'; await s.nap(34); }
          await s.nap(450);
          ans.innerHTML = marked;
          for (const m of $$('mark', ans)) { await s.nap(120); m.classList.add('on'); await s.nap(380); }
          for (const i of ideas) { i.classList.add('on'); await s.nap(260); }
          score.classList.add('on');
          await s.nap(2600);
          await fadeReset(sc, s, reset);
        }
      }
    },

    /* 3. Ready: the readiness ring climbs as topics fill; the weak spot gets named. */
    ready: {
      html: () => `<div class="stage" style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;padding:18px 20px">
        <div data-ring>${ring(148, 14, 38, { sub: 'ready' })}</div>
        <div class="center"><div class="h3">Bio 101 Midterm</div><div class="muted" style="font-size:14px;margin-top:2px">Fri, Nov 14 · 23 days to go</div></div>
        <div style="width:100%;display:grid;gap:9px">
          ${[['Cell cycle', 92, 'c-mint'], ['Meiosis', 71, 'c-sun'], ['Genetics', 54, 'c-rose']].map(([n, v, c], i) => `
            <div style="display:grid;grid-template-columns:78px 1fr 64px;align-items:center;gap:10px;font-size:13px;font-weight:600">
              <span>${n}</span><div class="bar"><i class="${c}" data-w="${v}"></i></div>
              <span style="text-align:right">${i === 2 ? '<span class="pill rose pop" data-weak>Weak</span>' : `<span class="num">${v}%</span>`}</span></div>`).join('')}
        </div>
      </div>`,
      async run(sc, s) {
        const r = $('.ring', sc), bars = $$('.bar i', sc), weak = $('[data-weak]', sc);
        const reset = () => { snapRing(r, 38); bars.forEach((b) => { b.style.transition = 'none'; b.style.width = '8%'; void b.offsetWidth; b.style.transition = ''; }); weak.classList.remove('on'); };
        reset();
        if (reduce) { snapRing(r, 82); bars.forEach((b) => { b.style.width = b.dataset.w + '%'; }); weak.classList.add('on'); return; }
        for (;;) {
          await s.nap(500);
          setRing(r, 82, { from: 38, ms: 1700 });
          for (const b of bars) { b.style.width = b.dataset.w + '%'; await s.nap(260); }
          await s.nap(900);
          weak.classList.add('on');
          await s.nap(2600);
          await fadeReset(sc, s, reset);
        }
      }
    },

    /* 4. Plan: a missed day gets absorbed by the rest of the week; the reminder lands. */
    plan: {
      html: () => {
        const days = [['M', 15], ['T', 15], ['W', 15], ['T', 15], ['F', 10], ['S', 0], ['S', 20]];
        return `<div class="stage" style="position:absolute;inset:0">
          <div class="notif glass"><img src="../img/icon-cramless-capy.webp" alt=""><div class="grow"><div class="row between"><b style="font-size:14px">Cramless</b><span class="faint" style="font-size:12px">7:30 PM</span></div><div style="font-size:14px;line-height:1.3">22 minutes tonight and you're done. Your streak is safe.</div></div></div>
          <div style="position:absolute;left:16px;right:16px;bottom:18px">
            <div class="row between" style="margin-bottom:12px"><b style="font-size:16px">This week</b><span class="pill tang">Midterm in 23 days</span></div>
            <div class="week">${days.map(([d, m], i) => `<div class="d">${d}<div class="p ${m ? 'on' : 'rest'}${i === 2 ? ' today' : ''}" data-i="${i}" data-m="${m}">${m ? m + 'm' : 'rest'}</div></div>`).join('')}</div>
            <div class="feedback sun rise" style="font-size:14px;margin-top:14px">Missed Wednesday? No problem. Thursday and Friday absorbed it.</div>
          </div>
        </div>`;
      },
      async run(sc, s) {
        const ps = $$('.p', sc), msg = $('.feedback', sc), note = $('.notif', sc);
        const reset = () => {
          ps.forEach((p) => { const m = +p.dataset.m; p.className = 'p ' + (m ? 'on' : 'rest') + (p.dataset.i === '2' ? ' today' : ''); p.textContent = m ? m + 'm' : 'rest'; p.style.transform = ''; });
          msg.classList.remove('on'); note.classList.remove('on');
        };
        const final = () => { ps[2].className = 'p missed'; ps[2].textContent = '15m'; ps[3].textContent = '22m'; ps[4].textContent = '18m'; ps[3].className = 'p today'; msg.classList.add('on'); note.classList.add('on'); };
        reset();
        if (reduce) { final(); return; }
        for (;;) {
          await s.nap(900);
          ps[2].className = 'p missed';
          await s.nap(700);
          for (const [i, v] of [[3, '22m'], [4, '18m']]) { ps[i].textContent = v; ps[i].style.transform = 'scale(1.12)'; ps[i].classList.add('today'); await s.nap(220); ps[i].style.transform = ''; }
          ps[4].classList.remove('today');
          await s.nap(300);
          msg.classList.add('on');
          await s.nap(700);
          note.classList.add('on');
          await s.nap(2800);
          await fadeReset(sc, s, reset);
        }
      }
    },

    /* 5. Tutor + trust: a cited answer, then the privacy line settles. Plays once and rests. */
    tutor: {
      html: () => `<div class="stage" style="position:absolute;inset:0;padding:16px;display:flex;flex-direction:column;justify-content:flex-end;gap:10px">
        <div class="bub me" data-q hidden>Why does anaphase matter?</div>
        <div class="typing-dots" data-dots hidden><i></i><i></i><i></i></div>
        <div class="bub cap" data-a hidden style="font-size:15px">It's the moment the sister chromatids are pulled apart, so each new cell gets a full set of chromosomes.
          <div class="chips mt8"><span class="chip src pop">${ic('book-open', 's')} Textbook p. 87</span><span class="chip src pop">${ic('mic', 's')} Lecture 6 · 12:05</span></div></div>
        <div class="row pop" data-lock style="justify-content:center;gap:8px;margin-top:8px;font:600 13px/1.3 var(--f-ui);color:var(--fg-2);text-align:center">${ic('lock', 's')}<span>Private by default. Your notes never train AI models.</span></div>
      </div>`,
      async run(sc, s) {
        const q = $('[data-q]', sc), dots = $('[data-dots]', sc), a = $('[data-a]', sc), chips = $$('.chip', a), lock = $('[data-lock]', sc);
        if (reduce) { q.hidden = false; a.hidden = false; chips.forEach((c) => c.classList.add('on')); lock.classList.add('on'); return; }
        q.hidden = true; dots.hidden = true; a.hidden = true; chips.forEach((c) => c.classList.remove('on')); lock.classList.remove('on');
        await s.nap(450); q.hidden = false;
        await s.nap(600); dots.hidden = false;
        await s.nap(1100); dots.hidden = true; a.hidden = false;
        await s.nap(450);
        for (const c of chips) { c.classList.add('on'); await s.nap(150); }
        await s.nap(700); lock.classList.add('on');
      }
    }
  };

  window.CL.SCENES = SCENES;
})();
