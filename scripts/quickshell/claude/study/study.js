"use strict";

// ---------------------------------------------------------------- bootstrap

const qs = new URLSearchParams(location.search);
const slug = qs.get("p") || "";
const $ = (id) => document.getElementById(id);

async function boot() {
  if (!slug) {
    $("loadMsg").textContent = "No study page specified — open this via its generated link (?p=<slug>).";
    return;
  }
  let spec;
  try {
    const res = await fetch("/study/data/" + encodeURIComponent(slug) + ".json", { cache: "no-store" });
    if (!res.ok) throw new Error("HTTP " + res.status);
    spec = await res.json();
  } catch (e) {
    $("loadMsg").textContent = "Couldn't load this study page (" + e.message + ").";
    return;
  }
  $("loadMsg").hidden = true;
  render(spec);
}

function render(spec) {
  document.title = spec.title || "Study";
  $("pageTitle").textContent = spec.title || "Study";
  $("pageSubject").textContent = spec.subject || "";

  const sections = [];
  if (spec.flashcards && spec.flashcards.length) sections.push(["flashcards", "Flashcards", initFlashcards]);
  if (spec.quiz && spec.quiz.length) sections.push(["quiz", "Quiz", initQuiz]);
  if (spec.walkthroughs && spec.walkthroughs.length) sections.push(["walk", "Walkthroughs", initWalkthroughs]);
  if (spec.diagram && DIAGRAMS[spec.diagram.type]) sections.push(["diagram", "Diagram", initDiagram]);

  if (!sections.length) {
    $("loadMsg").hidden = false;
    $("loadMsg").textContent = "This study page has no content.";
    return;
  }

  const tabs = $("tabs");
  sections.forEach(([id, label], i) => {
    const btn = document.createElement("button");
    btn.textContent = label;
    btn.dataset.target = id;
    if (i === 0) btn.classList.add("active");
    btn.addEventListener("click", () => switchTab(id));
    tabs.appendChild(btn);
  });

  sections.forEach(([id, , initFn], i) => {
    const el = $("sec-" + id);
    el.hidden = i !== 0;
    initFn(spec);
  });
}

function switchTab(id) {
  document.querySelectorAll("#tabs button").forEach((b) => b.classList.toggle("active", b.dataset.target === id));
  document.querySelectorAll("main > section.view").forEach((s) => {
    s.hidden = s.id !== "sec-" + id;
  });
}

// ---------------------------------------------------------------- flashcards

function initFlashcards(spec) {
  let cards = spec.flashcards.slice();
  let i = 0;
  let flipped = false;

  const card = $("flipCard");
  const front = $("cardFront");
  const back = $("cardBack");
  const counter = $("cardCounter");

  function show() {
    front.textContent = cards[i].front;
    back.textContent = cards[i].back;
    flipped = false;
    card.classList.remove("flipped");
    counter.textContent = (i + 1) + " / " + cards.length;
  }

  function flip() {
    flipped = !flipped;
    card.classList.toggle("flipped", flipped);
  }

  function go(delta) {
    i = (i + delta + cards.length) % cards.length;
    show();
  }

  card.addEventListener("click", flip);
  card.addEventListener("keydown", (e) => {
    if (e.key === " " || e.key === "Enter") { e.preventDefault(); flip(); }
    else if (e.key === "ArrowRight") go(1);
    else if (e.key === "ArrowLeft") go(-1);
  });
  $("cardPrev").addEventListener("click", () => go(-1));
  $("cardNext").addEventListener("click", () => go(1));
  $("cardShuffle").addEventListener("click", () => {
    for (let k = cards.length - 1; k > 0; k--) {
      const j = Math.floor(Math.random() * (k + 1));
      [cards[k], cards[j]] = [cards[j], cards[k]];
    }
    i = 0;
    show();
  });

  document.addEventListener("keydown", (e) => {
    if ($("sec-flashcards").hidden) return;
    if (document.activeElement === card) return; // already handled above
    if (e.key === "ArrowRight") go(1);
    else if (e.key === "ArrowLeft") go(-1);
    else if (e.key === " ") { e.preventDefault(); flip(); }
  });

  // pointer-based swipe (touch + mouse + pen alike)
  let dragging = false, startX = 0, dx = 0;
  card.addEventListener("pointerdown", (e) => {
    dragging = true; startX = e.clientX; dx = 0;
    card.classList.add("dragging");
    card.setPointerCapture(e.pointerId);
  });
  card.addEventListener("pointermove", (e) => {
    if (!dragging) return;
    dx = e.clientX - startX;
    card.style.transform = `translateX(${dx}px) rotate(${dx / 30}deg)`;
  });
  function endDrag() {
    if (!dragging) return;
    dragging = false;
    card.classList.remove("dragging");
    card.style.transform = "";
    if (Math.abs(dx) > 70) go(dx < 0 ? 1 : -1);
    else if (Math.abs(dx) < 6) flip();
    dx = 0;
  }
  card.addEventListener("pointerup", endDrag);
  card.addEventListener("pointercancel", endDrag);

  show();
}

// ---------------------------------------------------------------- quiz

function normAnswer(s) {
  return (s || "")
    .toString()
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9.,%+\-]/g, "")
    .trim();
}

// small Levenshtein distance for lenient short-answer matching
function levenshtein(a, b) {
  const m = a.length, n = b.length;
  if (!m) return n;
  if (!n) return m;
  const d = Array.from({ length: m + 1 }, (_, i) => [i, ...Array(n).fill(0)]);
  for (let j = 0; j <= n; j++) d[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      d[i][j] = a[i - 1] === b[j - 1]
        ? d[i - 1][j - 1]
        : 1 + Math.min(d[i - 1][j], d[i][j - 1], d[i - 1][j - 1]);
    }
  }
  return d[m][n];
}

function answersMatch(given, expected) {
  const g = normAnswer(given), e = normAnswer(expected);
  if (!g) return false;
  if (g === e) return true;
  const maxLen = Math.max(g.length, e.length);
  if (maxLen <= 2) return g === e;
  const dist = levenshtein(g, e);
  return dist / maxLen <= 0.2;
}

function initQuiz(spec) {
  const items = spec.quiz;
  let i = 0, score = 0, answered = false;

  const qEl = $("quizQ"), choicesEl = $("quizChoices"), fbEl = $("quizFeedback");
  const counter = $("quizCounter"), scoreEl = $("quizScore"), nextBtn = $("quizNext");

  function renderQ() {
    answered = false;
    fbEl.hidden = true;
    nextBtn.hidden = true;
    const q = items[i];
    qEl.textContent = q.q;
    counter.textContent = (i + 1) + " / " + items.length;
    scoreEl.textContent = "Score: " + score;
    choicesEl.innerHTML = "";

    if (q.type === "mc") {
      q.choices.forEach((choice, idx) => {
        const b = document.createElement("button");
        b.className = "quiz-choice";
        b.textContent = choice;
        b.addEventListener("click", () => submitMc(idx));
        choicesEl.appendChild(b);
      });
    } else {
      const wrap = document.createElement("div");
      wrap.className = "quiz-short";
      const input = document.createElement("input");
      input.type = "text";
      input.placeholder = "Type your answer…";
      input.addEventListener("keydown", (e) => { if (e.key === "Enter") submitShort(input.value); });
      const btn = document.createElement("button");
      btn.className = "btn-primary";
      btn.textContent = "Check";
      btn.addEventListener("click", () => submitShort(input.value));
      wrap.appendChild(input);
      wrap.appendChild(btn);
      choicesEl.appendChild(wrap);
      input.focus();
    }
  }

  function feedback(correct, explain) {
    fbEl.hidden = false;
    fbEl.className = "quiz-feedback " + (correct ? "good" : "bad");
    fbEl.innerHTML = `<p class="verdict ${correct ? "good-text" : "bad-text"}">${correct ? "Correct" : "Not quite"}</p><p>${explain || ""}</p>`;
    nextBtn.hidden = false;
    if (correct) score++;
    scoreEl.textContent = "Score: " + score;
  }

  function submitMc(idx) {
    if (answered) return;
    answered = true;
    const q = items[i];
    [...choicesEl.children].forEach((b, bi) => {
      b.disabled = true;
      if (bi === q.answer) b.classList.add("correct");
      else if (bi === idx) b.classList.add("wrong");
    });
    feedback(idx === q.answer, q.explain);
  }

  function submitShort(value) {
    if (answered) return;
    answered = true;
    const q = items[i];
    choicesEl.querySelectorAll("input,button").forEach((el) => (el.disabled = true));
    const ok = answersMatch(value, q.answer);
    feedback(ok, (ok ? "" : "Expected: " + q.answer + ". ") + (q.explain || ""));
  }

  nextBtn.addEventListener("click", () => {
    i++;
    if (i >= items.length) finish();
    else renderQ();
  });

  function finish() {
    document.querySelector(".quiz-card").hidden = true;
    const done = $("quizDone");
    done.hidden = false;
    $("quizDoneText").textContent = `Done — ${score} / ${items.length} correct.`;
  }

  $("quizRestart").addEventListener("click", () => {
    i = 0; score = 0;
    $("quizDone").hidden = true;
    document.querySelector(".quiz-card").hidden = false;
    renderQ();
  });

  renderQ();
}

// ---------------------------------------------------------------- walkthroughs

function initWalkthroughs(spec) {
  const list = $("walkList"), detail = $("walkDetail"), stepsEl = $("walkSteps"), titleEl = $("walkTitle");

  spec.walkthroughs.forEach((w, idx) => {
    const btn = document.createElement("button");
    btn.className = "walk-item";
    btn.innerHTML = `<span>${w.title}</span><span class="n">${w.steps.length} steps</span>`;
    btn.addEventListener("click", () => open(idx));
    list.appendChild(btn);
  });

  function open(idx) {
    const w = spec.walkthroughs[idx];
    titleEl.textContent = w.title;
    stepsEl.innerHTML = "";
    let revealed = 0;

    function draw() {
      stepsEl.innerHTML = "";
      w.steps.forEach((text, si) => {
        const li = document.createElement("li");
        const isRevealed = si < revealed;
        const isNext = si === revealed;
        li.className = "walk-step" + (isRevealed || isNext ? "" : " locked");
        const label = document.createElement("p");
        label.className = "label";
        label.textContent = "STEP " + (si + 1);
        li.appendChild(label);
        if (isRevealed) {
          const p = document.createElement("p");
          p.className = "text";
          p.textContent = text;
          li.appendChild(p);
        } else if (isNext) {
          const b = document.createElement("button");
          b.className = "reveal-btn";
          b.textContent = "Reveal step " + (si + 1) + " →";
          b.addEventListener("click", () => { revealed++; draw(); });
          li.appendChild(b);
        }
        stepsEl.appendChild(li);
      });
    }
    draw();
    list.hidden = true;
    detail.hidden = false;
  }

  $("walkBack").addEventListener("click", () => { detail.hidden = true; list.hidden = false; });
}

// ---------------------------------------------------------------- diagrams

function initDiagram(spec) {
  const root = $("diagramRoot");
  root.innerHTML = "";
  const def = spec.diagram;
  DIAGRAMS[def.type](root, def.params || {});
}

function card(root) {
  const c = document.createElement("div");
  c.className = "diagram-card";
  root.appendChild(c);
  return c;
}

function sliderRow(parent, label, { min, max, step, value, unit, onChange }) {
  const row = document.createElement("div");
  row.className = "ctrl-row";
  const lab = document.createElement("label");
  lab.textContent = label;
  const input = document.createElement("input");
  input.type = "range";
  input.min = min; input.max = max; input.step = step; input.value = value;
  const val = document.createElement("span");
  val.className = "val";
  const fmt = (v) => Number(v).toLocaleString(undefined, { maximumFractionDigits: 3 }) + (unit || "");
  val.textContent = fmt(value);
  let frame = null;
  input.addEventListener("input", () => {
    val.textContent = fmt(input.value);
    if (frame) cancelAnimationFrame(frame);
    frame = requestAnimationFrame(() => onChange(Number(input.value)));
  });
  row.appendChild(lab); row.appendChild(input); row.appendChild(val);
  parent.appendChild(row);
  return input;
}

function resultGrid(parent, entries) {
  const grid = document.createElement("div");
  grid.className = "result-grid";
  parent.appendChild(grid);
  function set(vals) {
    grid.innerHTML = "";
    vals.forEach(([k, v]) => {
      const chip = document.createElement("div");
      chip.className = "result-chip";
      chip.innerHTML = `<div class="k">${k}</div><div class="v">${v}</div>`;
      grid.appendChild(chip);
    });
  }
  set(entries);
  return set;
}

function fmtNum(v, sig = 4) {
  if (!isFinite(v)) return "—";
  const a = Math.abs(v);
  if (a !== 0 && (a < 1e-3 || a >= 1e6)) return v.toExponential(2);
  return Number(v.toPrecision(sig)).toString();
}

// -- 1. capacitor_plates ------------------------------------------------
function diagramCapacitor(root, p) {
  const EPS0 = 8.854e-12;
  const state = {
    d: p.distance_mm ?? 5,
    A: p.area_cm2 ?? 100,
    er: p.epsilon_r ?? 1,
    U: p.voltage_v ?? 100,
  };
  const c = card(root);
  const canvas = document.createElement("canvas");
  canvas.width = 640; canvas.height = 260;
  c.appendChild(canvas);
  const ctx = canvas.getContext("2d");

  sliderRow(c, "Plate separation d", { min: 0.5, max: 50, step: 0.5, value: state.d, unit: " mm", onChange: (v) => { state.d = v; update(); } });
  sliderRow(c, "Plate area A", { min: 1, max: 1000, step: 1, value: state.A, unit: " cm²", onChange: (v) => { state.A = v; update(); } });
  sliderRow(c, "Relative permittivity εᵣ", { min: 1, max: 10, step: 0.1, value: state.er, unit: "", onChange: (v) => { state.er = v; update(); } });
  sliderRow(c, "Voltage U", { min: 0, max: 2000, step: 10, value: state.U, unit: " V", onChange: (v) => { state.U = v; update(); } });

  const setResults = resultGrid(c, []);

  function draw() {
    const w = canvas.width, h = canvas.height;
    ctx.clearRect(0, 0, w, h);
    const gap = Math.max(30, Math.min(260, state.d * 6));
    const plateH = 150;
    const cx = w / 2;
    const leftX = cx - gap / 2, rightX = cx + gap / 2;
    ctx.fillStyle = "#8ab4ff";
    ctx.fillRect(leftX - 10, h / 2 - plateH / 2, 10, plateH);
    ctx.fillRect(rightX, h / 2 - plateH / 2, 10, plateH);
    ctx.strokeStyle = "#c3a6ff88";
    ctx.lineWidth = 1.5;
    const lines = 7;
    for (let i = 0; i < lines; i++) {
      const y = h / 2 - plateH / 2 + (plateH / (lines - 1)) * i;
      ctx.beginPath();
      ctx.moveTo(leftX, y);
      ctx.lineTo(rightX, y);
      ctx.stroke();
      // arrowhead
      ctx.beginPath();
      ctx.moveTo(rightX - 8, y - 4);
      ctx.lineTo(rightX, y);
      ctx.lineTo(rightX - 8, y + 4);
      ctx.stroke();
    }
    ctx.fillStyle = "#9a9cb5";
    ctx.font = "13px system-ui";
    ctx.textAlign = "center";
    ctx.fillText("d = " + fmtNum(state.d) + " mm", cx, h / 2 + plateH / 2 + 24);
  }

  function update() {
    const d_m = state.d / 1000;
    const A_m2 = state.A / 10000;
    const C = (state.er * EPS0 * A_m2) / d_m;
    const E = state.U / d_m;
    const Q = C * state.U;
    const W = 0.5 * C * state.U * state.U;
    setResults([
      ["Capacitance C", fmtNum(C) + " F"],
      ["Field E", fmtNum(E) + " V/m"],
      ["Charge Q", fmtNum(Q) + " C"],
      ["Energy W", fmtNum(W) + " J"],
    ]);
    draw();
  }
  update();
}

// -- 2. coulomb_force -----------------------------------------------------
function diagramCoulomb(root, p) {
  const K = 8.99e9;
  const state = {
    q1: p.q1_uC ?? 5,
    q2: p.q2_uC ?? -5,
    r: p.distance_cm ?? 10,
  };
  const c = card(root);
  const canvas = document.createElement("canvas");
  canvas.width = 640; canvas.height = 220;
  c.appendChild(canvas);
  const ctx = canvas.getContext("2d");

  sliderRow(c, "Charge q₁", { min: -20, max: 20, step: 0.5, value: state.q1, unit: " µC", onChange: (v) => { state.q1 = v; update(); } });
  sliderRow(c, "Charge q₂", { min: -20, max: 20, step: 0.5, value: state.q2, unit: " µC", onChange: (v) => { state.q2 = v; update(); } });
  sliderRow(c, "Distance r", { min: 1, max: 100, step: 1, value: state.r, unit: " cm", onChange: (v) => { state.r = v; update(); } });

  const setResults = resultGrid(c, []);

  function draw() {
    const w = canvas.width, h = canvas.height, midY = h / 2;
    ctx.clearRect(0, 0, w, h);
    const gap = Math.max(60, Math.min(520, state.r * 4));
    const cx = w / 2;
    const x1 = cx - gap / 2, x2 = cx + gap / 2;
    const attract = (state.q1 >= 0) !== (state.q2 >= 0);

    [[x1, state.q1], [x2, state.q2]].forEach(([x, q]) => {
      ctx.beginPath();
      ctx.arc(x, midY, 22, 0, Math.PI * 2);
      ctx.fillStyle = q >= 0 ? "#ef7a7a" : "#8ab4ff";
      ctx.fill();
      ctx.fillStyle = "#0e1020";
      ctx.font = "bold 16px system-ui";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(q >= 0 ? "+" : "−", x, midY + 1);
    });

    // force arrows
    const F = K * Math.abs(state.q1 * 1e-6 * state.q2 * 1e-6) / Math.pow(Math.max(state.r, 1) / 100, 2);
    const arrowLen = Math.min(60, 14 + 10 * Math.log10(1 + F));
    ctx.strokeStyle = "#f2c572";
    ctx.lineWidth = 3;
    ctx.textBaseline = "alphabetic";
    function arrow(fromX, dir) {
      const toX = fromX + dir * arrowLen;
      const y = midY - 48;
      ctx.beginPath(); ctx.moveTo(fromX, y); ctx.lineTo(toX, y); ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(toX, y);
      ctx.lineTo(toX - dir * 8, y - 5);
      ctx.lineTo(toX - dir * 8, y + 5);
      ctx.closePath();
      ctx.fillStyle = "#f2c572";
      ctx.fill();
    }
    arrow(x1, attract ? 1 : -1);
    arrow(x2, attract ? -1 : 1);
    ctx.fillStyle = "#9a9cb5";
    ctx.font = "13px system-ui";
    ctx.textAlign = "center";
    ctx.fillText(attract ? "attractive" : "repulsive", cx, midY - 60);
    ctx.fillText("r = " + fmtNum(state.r) + " cm", cx, midY + 48);
  }

  function update() {
    const r_m = Math.max(state.r, 1) / 100;
    const F = K * Math.abs(state.q1 * 1e-6 * state.q2 * 1e-6) / (r_m * r_m);
    setResults([
      ["Force F", fmtNum(F) + " N"],
      ["Direction", (state.q1 >= 0) !== (state.q2 >= 0) ? "attractive" : "repulsive"],
    ]);
    draw();
  }
  update();
}

// -- 3. vector_mod_n --------------------------------------------------------
function diagramVectorModN(root, p) {
  const n = Math.max(2, Math.round(p.n ?? 5));
  let a = (p.vector_a && p.vector_a.length ? p.vector_a : [1, 2, 3]).map((v) => ((v % n) + n) % n);
  let b = (p.vector_b && p.vector_b.length ? p.vector_b : [1, 1, 1]).slice(0, a.length);
  while (b.length < a.length) b.push(0);
  b = b.map((v) => ((v % n) + n) % n);

  const c = card(root);
  const opRow = document.createElement("div");
  opRow.className = "ctrl-row";
  const opLabel = document.createElement("label");
  opLabel.textContent = "Operation";
  const sel = document.createElement("select");
  [["add", "a + b"], ["sub", "a − b"], ["scalar", "2·a"]].forEach(([v, t]) => {
    const o = document.createElement("option"); o.value = v; o.textContent = t; sel.appendChild(o);
  });
  opRow.appendChild(opLabel); opRow.appendChild(sel);
  c.appendChild(opRow);

  const vecA = document.createElement("div"); vecA.className = "vec-row";
  const vecB = document.createElement("div"); vecB.className = "vec-row";
  const vecR = document.createElement("div"); vecR.className = "vec-row";
  [["a", vecA], ["b", vecB], ["= ", vecR]].forEach(([lbl, row]) => {
    const l = document.createElement("span"); l.className = "vec-label"; l.textContent = lbl;
    row.prepend(l);
  });
  c.appendChild(document.createElement("div")).className = "";
  c.appendChild(vecA);
  c.appendChild(vecB);
  c.appendChild(vecR);

  function buildEditable(container, vec, onChange) {
    container.querySelectorAll(".vec-comp").forEach((e) => e.remove());
    vec.forEach((val, idx) => {
      const comp = document.createElement("div");
      comp.className = "vec-comp";
      const up = document.createElement("button"); up.textContent = "+";
      const num = document.createElement("span"); num.className = "n"; num.textContent = val;
      const down = document.createElement("button"); down.textContent = "−";
      up.addEventListener("click", () => { vec[idx] = (vec[idx] + 1) % n; num.textContent = vec[idx]; onChange(); });
      down.addEventListener("click", () => { vec[idx] = (vec[idx] - 1 + n) % n; num.textContent = vec[idx]; onChange(); });
      comp.appendChild(up); comp.appendChild(num); comp.appendChild(down);
      container.appendChild(comp);
    });
  }

  function renderResult() {
    vecR.querySelectorAll(".vec-comp").forEach((e) => e.remove());
    const op = sel.value;
    const result = a.map((av, i) => {
      const bv = b[i];
      const raw = op === "add" ? av + bv : op === "sub" ? av - bv : 2 * av;
      return ((raw % n) + n) % n;
    });
    result.forEach((val) => {
      const comp = document.createElement("div");
      comp.className = "vec-comp";
      const num = document.createElement("span"); num.className = "n"; num.textContent = val;
      comp.appendChild(num);
      vecR.appendChild(comp);
    });
  }

  buildEditable(vecA, a, renderResult);
  buildEditable(vecB, b, renderResult);
  sel.addEventListener("change", renderResult);
  renderResult();

  const note = document.createElement("p");
  note.className = "hint";
  note.style.textAlign = "left";
  note.style.marginTop = "14px";
  note.textContent = `Working in Z_${n} — every component wraps back into 0..${n - 1}. Click + / − on a or b to change it; the result updates live.`;
  c.appendChild(note);
}

// -- 4. logic_gate_truth_table ---------------------------------------------
const GATES = {
  BUFFER: { inputs: 1, fn: (a) => a, expr: "X = A" },
  NOT: { inputs: 1, fn: (a) => 1 - a, expr: "X = Ā" },
  AND: { inputs: 2, fn: (a, b) => a & b, expr: "X = A · B" },
  NAND: { inputs: 2, fn: (a, b) => 1 - (a & b), expr: "X = (A · B)̄" },
  OR: { inputs: 2, fn: (a, b) => a | b, expr: "X = A + B" },
  NOR: { inputs: 2, fn: (a, b) => 1 - (a | b), expr: "X = (A + B)̄" },
  XOR: { inputs: 2, fn: (a, b) => a ^ b, expr: "X = A ⊕ B" },
  XNOR: { inputs: 2, fn: (a, b) => 1 - (a ^ b), expr: "X = (A ⊕ B)̄" },
};

function diagramLogicGate(root, p) {
  const c = card(root);
  const row = document.createElement("div");
  row.className = "ctrl-row";
  const lab = document.createElement("label");
  lab.textContent = "Gate";
  const sel = document.createElement("select");
  Object.keys(GATES).forEach((g) => {
    const o = document.createElement("option"); o.value = g; o.textContent = g; sel.appendChild(o);
  });
  sel.value = GATES[p.default_gate] ? p.default_gate : "AND";
  row.appendChild(lab); row.appendChild(sel);
  c.appendChild(row);

  const toggleRow = document.createElement("div");
  toggleRow.className = "ctrl-row";
  c.appendChild(toggleRow);

  const exprEl = document.createElement("p");
  exprEl.style.fontSize = "18px";
  exprEl.style.margin = "14px 0";
  c.appendChild(exprEl);

  const canvas = document.createElement("canvas");
  canvas.width = 300; canvas.height = 140;
  c.appendChild(canvas);
  const ctx = canvas.getContext("2d");

  const outChip = document.createElement("div");
  outChip.className = "result-grid";
  c.appendChild(outChip);

  const table = document.createElement("table");
  table.className = "tt-table";
  c.appendChild(table);

  let inputs = { A: 0, B: 0 };

  function buildToggles() {
    toggleRow.innerHTML = "";
    const g = GATES[sel.value];
    const names = g.inputs === 1 ? ["A"] : ["A", "B"];
    names.forEach((name) => {
      const lbl = document.createElement("label");
      lbl.style.width = "auto";
      const cb = document.createElement("input");
      cb.type = "checkbox";
      cb.checked = !!inputs[name];
      cb.addEventListener("change", () => { inputs[name] = cb.checked ? 1 : 0; update(); });
      lbl.appendChild(cb);
      lbl.append(" " + name);
      toggleRow.appendChild(lbl);
    });
  }

  function drawSymbol(g) {
    const w = canvas.width, h = canvas.height;
    ctx.clearRect(0, 0, w, h);
    ctx.strokeStyle = "#8ab4ff";
    ctx.fillStyle = "#1d1f2b";
    ctx.lineWidth = 2.5;
    const cx = w / 2, cy = h / 2;
    ctx.beginPath();
    ctx.roundRect ? ctx.roundRect(cx - 50, cy - 35, 100, 70, 14) : ctx.rect(cx - 50, cy - 35, 100, 70);
    ctx.fill(); ctx.stroke();
    ctx.fillStyle = "#e6e6f0";
    ctx.font = "bold 16px system-ui";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(sel.value, cx, cy);
    const names = g.inputs === 1 ? ["A"] : ["A", "B"];
    names.forEach((name, idx) => {
      const y = g.inputs === 1 ? cy : cy - 18 + idx * 36;
      ctx.beginPath(); ctx.moveTo(cx - 90, y); ctx.lineTo(cx - 50, y); ctx.stroke();
      ctx.font = "12px system-ui";
      ctx.fillText(name + "=" + inputs[name], cx - 108, y);
    });
    ctx.beginPath(); ctx.moveTo(cx + 50, cy); ctx.lineTo(cx + 90, cy); ctx.stroke();
    ctx.font = "12px system-ui";
    ctx.fillText("X", cx + 104, cy);
  }

  function buildTable(g) {
    const names = g.inputs === 1 ? ["A"] : ["A", "B"];
    const rowsN = g.inputs === 1 ? 2 : 4;
    let head = "<tr>" + names.map((n) => "<th>" + n + "</th>").join("") + "<th>X</th></tr>";
    let body = "";
    for (let i = 0; i < rowsN; i++) {
      const a = g.inputs === 1 ? i : (i >> 1) & 1;
      const b = g.inputs === 1 ? null : i & 1;
      const out = g.inputs === 1 ? g.fn(a) : g.fn(a, b);
      const isCurrent = g.inputs === 1 ? inputs.A === a : inputs.A === a && inputs.B === b;
      body += `<tr class="${isCurrent ? "current-row" : ""}"><td>${a}</td>${g.inputs === 2 ? `<td>${b}</td>` : ""}<td>${out}</td></tr>`;
    }
    table.innerHTML = head + body;
  }

  function update() {
    const g = GATES[sel.value];
    exprEl.textContent = g.expr;
    drawSymbol(g);
    const out = g.inputs === 1 ? g.fn(inputs.A) : g.fn(inputs.A, inputs.B);
    outChip.innerHTML = `<div class="result-chip"><div class="k">Output X</div><div class="v">${out}</div></div>`;
    buildTable(g);
  }

  sel.addEventListener("change", () => { inputs = { A: 0, B: 0 }; buildToggles(); update(); });
  buildToggles();
  update();
}

const DIAGRAMS = {
  capacitor_plates: diagramCapacitor,
  coulomb_force: diagramCoulomb,
  vector_mod_n: diagramVectorModN,
  logic_gate_truth_table: diagramLogicGate,
};

boot();
