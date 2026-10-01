.pragma library

const CAT_BIAS = { power: 3, system: 2, audio: 2, media: 2, widget: 2, mail: 2, timer: 2, claude: 1, capture: 1, wallpaper: 1, layout: 1, window: 2, workspace: 1, device: 2, project: 2, app: 0, setting: -2 }

function editWithin1(a, b) {
    if (a === b) return true
    let la = a.length, lb = b.length
    if (Math.abs(la - lb) > 1) return false
    let i = 0
    while (i < la && i < lb && a[i] === b[i]) i++
    if (la === lb) {
        if (i + 1 < la && a[i] === b[i + 1] && a[i + 1] === b[i]) return a.slice(i + 2) === b.slice(i + 2)
        return a.slice(i + 1) === b.slice(i + 1)
    }
    return la > lb ? a.slice(i + 1) === b.slice(i) : a.slice(i) === b.slice(i + 1)
}

function subseq(tok, label) {
    let hits = [], j = 0, gaps = 0, last = -1
    for (let i = 0; i < label.length && j < tok.length; i++) {
        if (label[i] === tok[j]) {
            if (last >= 0) gaps += i - last - 1
            hits.push(i); last = i; j++
        }
    }
    if (j < tok.length) return null
    return { hits: hits, gaps: gaps }
}

function wordStarts(label) {
    let out = []
    let re = /[a-z0-9]+/g, m
    while ((m = re.exec(label)) !== null) out.push({ w: m[0], at: m.index })
    return out
}

function prep(a) {
    let label = a.label.toLowerCase()
    a._label = label
    a._words = wordStarts(label)
    a._kw = (a.keywords || "").toLowerCase().split(/[^a-z0-9]+/).filter(w => w.length > 0).concat(a.cat)
}

function tokenScore(tok, a) {
    let best = 0, hits = [], word = -1
    for (let i = 0; i < a._words.length; i++) {
        let w = a._words[i].w, at = a._words[i].at, s = 0, h = []
        if (w === tok) s = 12
        else if (w.startsWith(tok)) s = 8 + 2 * tok.length / w.length
        else if (tok.length >= 4 && w[0] === tok[0] && editWithin1(tok, w)) s = 6
        else if (tok.length >= 4 && w[0] === tok[0] && w.length > tok.length && editWithin1(tok, w.slice(0, tok.length))) s = 5
        else if (tok.length >= 3 && w.indexOf(tok) >= 0) s = 4
        if (s > 0) {
            let off = w.indexOf(tok)
            let n = off >= 0 ? tok.length : Math.min(tok.length, w.length)
            off = Math.max(0, off)
            for (let k = 0; k < n; k++) h.push(at + off + k)
        }
        if (s > best) { best = s; hits = h; word = i }
    }
    for (let i = 0; i < a._kw.length; i++) {
        let w = a._kw[i], s = 0
        if (w === tok) s = 7
        else if (tok.length >= 2 && w.startsWith(tok)) s = 5
        else if (tok.length >= 6 && w[0] === tok[0] && editWithin1(tok, w)) s = 4
        if (s > best) { best = s; hits = []; word = -1 }
    }
    if (best === 0 && tok.length >= 3) {
        let sq = subseq(tok, a._label)
        let atStart = sq && (sq.hits[0] === 0 || /[^a-z0-9]/.test(a._label[sq.hits[0] - 1]))
        if (sq && atStart && sq.gaps <= tok.length) { best = Math.max(1.5, 4 - sq.gaps * 0.4); hits = sq.hits }
    }
    return { s: best, hits: hits, word: word }
}

function usage(h) {
    if (!h) return 0
    let age = (Date.now() / 1000 - (h.t || 0)) / 86400
    return Math.log(1 + h.n) * 2.2 + Math.max(0, 3 - age)
}

function match(a, q, raw, history) {
    if (!a._words) prep(a)
    let toks = q.split(/\s+/).filter(t => t.length > 0)
    let rawToks = raw.trim().split(/\s+/).filter(t => t.length > 0)
    let total = 0, matched = 0, unmatched = 0, hits = [], param = [], words = {}, nWords = 0
    let p = a.param
    for (let i = 0; i < toks.length; i++) {
        let t = toks[i]
        if (p && p.kind === "number" && /^\d+(\.\d+)?%?$/.test(t)) { param.push(t.replace("%", "")); continue }
        if (p && p.kind === "text" && param.length > 0) { param.push(rawToks[i] || t); continue }
        let r = tokenScore(t, a)
        if (r.s > 0) {
            total += r.s; matched++; hits = hits.concat(r.hits)
            if (r.word >= 0 && !words[r.word]) { words[r.word] = true; nWords++ }
        } else if (p && p.kind === "text" && matched > 0) {
            param.push(rawToks[i] || t)
        } else {
            unmatched++
        }
    }
    if (matched === 0) return null
    if (unmatched > 0 && unmatched >= matched) return null
    total -= unmatched * 7
    if (unmatched === 0) total += 4
    total += 7 * nWords / Math.max(1, a._words.length)
    if (a._label.startsWith(toks[0])) total += 5
    if (a._label.startsWith(q)) total += 8
    total += CAT_BIAS[a.cat] || 0
    total += a.bias || 0
    total += usage(history[a.id])
    total -= a._label.length * 0.02
    let seen = {}, uh = []
    for (let i = 0; i < hits.length; i++) if (!seen[hits[i]]) { seen[hits[i]] = true; uh.push(hits[i]) }
    return { score: total, hits: uh, param: param.join(" ") }
}

function rank(actions, raw, history, limit) {
    let q = raw.toLowerCase().trim()
    let out = []
    if (q === "") {
        for (let i = 0; i < actions.length; i++) {
            let u = usage(history[actions[i].id])
            if (u > 0) out.push({ a: actions[i], score: u, hits: [], param: "" })
        }
        out.sort((x, y) => y.score - x.score)
        return out.slice(0, limit)
    }
    for (let i = 0; i < actions.length; i++) {
        let m = match(actions[i], q, raw, history)
        if (m) out.push({ a: actions[i], score: m.score, hits: m.hits, param: m.param })
    }
    out.sort((x, y) => y.score - x.score)
    return out.slice(0, limit)
}
