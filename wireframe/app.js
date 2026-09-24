// NPO light, interactive wireframe.
//
// A sketch of the tvOS app in a browser: one 1920x1080 "television", driven by
// the keyboard or by the remote beside it. The behaviour follows the
// requirements in docs/requirements/; each focusable element names the
// identifiers it illustrates, and the panel shows them for whatever has focus.
// It is a design aid, not the specification: where the two disagree, the
// requirements win.
(function () {
  'use strict';

  const CAT = window.CATALOGUE;
  const REQS = window.REQUIREMENTS || {};
  const REPO = 'https://github.com/berendkleinhaneveld/npo-light/blob/master/docs/requirements/';
  const STORAGE_KEY = 'npo-light-wireframe-v1';

  // The constants the requirements name.
  const RECENT_CAP = 20; // FR-HOME-06
  const FINISHED_DAYS = 7; // FR-HOME-07
  const SEARCH_CAP = 10; // FR-SEARCH-04
  const STILL_GRACE_SECONDS = 30; // FR-PLAY-08: "a defined grace period"
  const NEXT_OVERLAY_SECONDS = 8; // FR-PLAY-05: "long enough to be used"
  const DAY = 24 * 60 * 60 * 1000;
  const HOLD_MS = 550;

  const SETTING_CHOICES = {
    kidsPause: [0, 5, 10, 15, 30],
    kidsStill: [1800, 3600, 5400, 7200],
    normalStill: [3600, 7200, 10800, 14400],
  };

  // ---------------------------------------------------------------- state

  let S = null; // persisted
  const T = { // transient
    stack: [],
    focus: null,
    fallback: [],
    menu: null,
    dialog: null,
    toast: null,
    toastTimer: null,
    player: null,
    tick: null,
    search: { query: '', status: 'idle', results: [], forQuery: '', timer: null, token: 0 },
    signinTimer: null,
  };

  function emptyMode() {
    return { pins: [], recent: [], later: [], searches: [], progress: {}, current: {} };
  }

  function seededState() {
    const now = Date.now();
    const h = 60 * 60 * 1000;
    const normal = emptyMode();
    normal.pins = [
      { id: 'polderpost', at: now - DAY },
      { id: 'storm', at: now - 3 * DAY },
      { id: 'wadden', at: now - 5 * DAY },
      { id: 'zeeland', at: now - 12 * DAY },
    ];
    normal.progress = {
      'polderpost-s1e1': { pos: 2700, watched: true, finishedAt: now - 3 * DAY },
      'polderpost-s1e2': { pos: 2700, watched: true, finishedAt: now - 2 * DAY },
      'polderpost-s1e3': { pos: 1200, watched: false, finishedAt: null },
      'wadden-s1e1': { pos: 3000, watched: true, finishedAt: now - 6 * DAY },
      'wadden-s1e2': { pos: 3000, watched: true, finishedAt: now - 5 * DAY },
      'wadden-s1e3': { pos: 3000, watched: true, finishedAt: now - 4 * DAY },
      'wadden-s1e4': { pos: 3000, watched: true, finishedAt: now - 2 * DAY },
      storm: { pos: 3840, watched: false, finishedAt: null },
      'kaas-s1e1': { pos: 1500, watched: true, finishedAt: now - 2 * DAY },
      'kaas-s1e2': { pos: 300, watched: false, finishedAt: null },
      veerpont: { pos: 5880, watched: true, finishedAt: now - 2 * DAY },
    };
    normal.current = { polderpost: 'polderpost-s1e3', wadden: 'wadden-s1e4', kaas: 'kaas-s1e2' };
    normal.recent = [
      { id: 'polderpost', at: now - 2 * h },
      { id: 'storm', at: now - DAY },
      { id: 'kaas', at: now - 2 * DAY },
      { id: 'veerpont', at: now - 2 * DAY - h },
      { id: 'wadden', at: now - 2 * DAY - 2 * h },
    ];
    normal.later = [
      { id: 'afsluitdijk', at: now - DAY },
      { id: 'bakfiets-s1e3', at: now - 2 * DAY },
      { id: 'sterren', at: now - 4 * DAY },
    ];
    normal.searches = [
      { term: 'Fl', picks: ['fleurwild'], at: now - h },
      { term: 'storm', picks: ['storm'], at: now - DAY },
      { term: 'kaas', picks: [], at: now - 3 * DAY },
    ];

    const kids = emptyMode();
    kids.pins = [{ id: 'bram', at: now - DAY }, { id: 'fleurtuin', at: now - 2 * DAY }];
    kids.progress = {
      'bram-s1e1': { pos: 600, watched: true, finishedAt: now - DAY },
      'bram-s1e2': { pos: 240, watched: false, finishedAt: null },
      'pim-s1e1': { pos: 900, watched: true, finishedAt: now - DAY },
    };
    kids.current = { bram: 'bram-s1e2', pim: 'pim-s1e1' };
    kids.recent = [{ id: 'bram', at: now - 3 * h }, { id: 'pim', at: now - DAY }];
    kids.later = [{ id: 'fietsje', at: now - DAY }];
    kids.searches = [{ term: 'Bram', picks: ['bram'], at: now - DAY }];

    return baseState({ normal, kids });
  }

  function emptyState() {
    return baseState({ normal: emptyMode(), kids: emptyMode() });
  }

  function baseState(modes) {
    return {
      version: 1,
      signedIn: true,
      mode: 'normal',
      modes,
      settings: { kidsPause: 5, kidsStill: 3600, normalStill: 10800 },
      scenario: { offline: false, slow: false, playbackFails: false, speed: 30 },
      clockOffset: 0,
      signin: null,
    };
  }

  function load() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (parsed && parsed.version === 1) return parsed;
      }
    } catch (error) {
      // Storage is a convenience here; without it the wireframe starts fresh.
    }
    return null;
  }

  function save() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(S));
    } catch (error) {
      // See load().
    }
  }

  // ---------------------------------------------------------------- model

  const now = () => Date.now() + S.clockOffset;
  const md = () => S.modes[S.mode];
  const isKids = () => S.mode === 'kids';
  const get = (id) => CAT.get(id);

  function visibleInMode(item) {
    return !isKids() || item.youth;
  }

  function progressOf(id) {
    return md().progress[id] || { pos: 0, watched: false, finishedAt: null };
  }

  function setProgress(id, value) {
    md().progress[id] = Object.assign({}, progressOf(id), value);
  }

  // FR-PLAY-04: the later of 95% and the point where 90 seconds remain.
  function threshold(duration) {
    return Math.max(duration * 0.95, duration - 90);
  }

  function seriesOf(playable) {
    return playable.seriesId ? get(playable.seriesId) : null;
  }

  // The thing a pin, a recently watched entry or a detail page is about.
  function itemOf(playable) {
    return seriesOf(playable) || playable;
  }

  // FR-HOME-04, FR-CONTENT-02: the episode a series tile offers.
  function nextEpisode(seriesItem) {
    const episodes = CAT.episodes(seriesItem);
    const currentId = md().current[seriesItem.id];
    let start = 0;
    if (currentId) {
      const index = episodes.findIndex((episode) => episode.id === currentId);
      if (index >= 0) {
        if (episodes[index].available && !progressOf(currentId).watched) return episodes[index];
        start = index + 1;
      }
    }
    for (let i = start; i < episodes.length; i += 1) {
      if (episodes[i].available && !progressOf(episodes[i].id).watched) return episodes[i];
    }
    return null;
  }

  // The episode that follows one that just finished, skipping unavailable ones.
  function followingEpisode(episode) {
    const episodes = CAT.episodes(seriesOf(episode));
    const index = episodes.findIndex((candidate) => candidate.id === episode.id);
    for (let i = index + 1; i < episodes.length; i += 1) {
      if (episodes[i].available) return episodes[i];
    }
    return null;
  }

  // What playing an item's tile would play right now, or null when there is
  // nothing left (a finished series) or the item is gone.
  function playableFor(item) {
    if (!item.available) return null;
    if (item.kind === 'series') return nextEpisode(item);
    return item;
  }

  function finishedAt(item) {
    if (item.kind === 'series') {
      if (nextEpisode(item)) return null;
      const times = CAT.episodes(item).map((episode) => progressOf(episode.id).finishedAt || 0);
      return Math.max(0, ...times) || now();
    }
    const progress = progressOf(item.id);
    return progress.watched ? (progress.finishedAt || now()) : null;
  }

  // FR-HOME-07: filtered on every read, never swept.
  function recentVisible() {
    return md().recent.filter((entry) => {
      const item = get(entry.id);
      if (!item) return false;
      const finished = finishedAt(item);
      if (finished === null) return true;
      const effective = Math.min(finished, now());
      return now() - effective < FINISHED_DAYS * DAY;
    });
  }

  function isPinned(item) {
    return md().pins.some((pin) => pin.id === item.id);
  }

  function isSaved(playable) {
    return md().later.some((entry) => entry.id === playable.id);
  }

  // FR-HOME-03: an episode of a series pins the series.
  function togglePin(item) {
    const target = itemOf(item);
    const pins = md().pins;
    if (isPinned(target)) {
      md().pins = pins.filter((pin) => pin.id !== target.id);
      toast(`${target.title} is losgemaakt`);
    } else {
      md().pins = [{ id: target.id, at: now() }].concat(pins);
      toast(`${target.title} is vastgezet`);
    }
    commit();
  }

  // FR-LATER-02: films and single episodes only.
  function toggleSaved(playable) {
    if (isSaved(playable)) {
      md().later = md().later.filter((entry) => entry.id !== playable.id);
      toast(`${displayTitle(playable)} is uit Later kijken gehaald`);
    } else {
      md().later = [{ id: playable.id, at: now() }].concat(md().later);
      toast(`${displayTitle(playable)} staat bij Later kijken`);
    }
    commit();
  }

  function removeFromRecent(item) {
    md().recent = md().recent.filter((entry) => entry.id !== item.id);
    // FR-HOME-08: removing discards the stored position.
    const playable = item.kind === 'series'
      ? get(md().current[item.id] || '') : item;
    if (playable) setProgress(playable.id, { pos: 0 });
    toast(`${item.title} is uit Recent bekeken gehaald`);
    commit();
  }

  // FR-HOME-06, FR-PLAY-09: playing puts the item at the front.
  function recordPlay(playable) {
    const item = itemOf(playable);
    const live = recentVisible().map((entry) => entry.id);
    md().recent = [{ id: item.id, at: now() }]
      .concat(md().recent.filter((entry) => entry.id !== item.id && live.includes(entry.id)))
      .slice(0, RECENT_CAP);
    if (item.kind === 'series') md().current[item.id] = playable.id;
  }

  function markWatched(playable) {
    setProgress(playable.id, { watched: true, finishedAt: now() });
    // FR-LATER-07: finishing a saved item takes it off the list.
    md().later = md().later.filter((entry) => entry.id !== playable.id);
  }

  // FR-SEARCH-05: a pick is stored against the exact term.
  function rememberSearch(term, pickId) {
    if (!term.trim()) return;
    const searches = md().searches;
    const existing = searches.find((entry) => entry.term === term);
    let picks = existing ? existing.picks.slice() : [];
    if (pickId) picks = [pickId].concat(picks.filter((id) => id !== pickId));
    md().searches = [{ term, picks, at: now() }]
      .concat(searches.filter((entry) => entry.term !== term))
      .slice(0, SEARCH_CAP);
  }

  function commit() {
    save();
    render();
  }

  // ---------------------------------------------------------------- text

  const esc = (value) => String(value)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

  function plural(n, one, many) {
    return `${n} ${n === 1 ? one : many}`;
  }

  function minutesText(seconds) {
    const minutes = Math.max(1, Math.round(seconds / 60));
    if (minutes < 60) return `${minutes} min`;
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return rest ? `${hours} u ${rest} min` : `${hours} u`;
  }

  function clock(seconds) {
    const s = Math.max(0, Math.floor(seconds));
    const hh = Math.floor(s / 3600);
    const mm = String(Math.floor((s % 3600) / 60)).padStart(hh ? 2 : 1, '0');
    const ss = String(s % 60).padStart(2, '0');
    return hh ? `${hh}:${mm}:${ss}` : `${mm}:${ss}`;
  }

  function durationSetting(seconds) {
    if (seconds === 0) return 'Geen';
    if (seconds < 60) return `${seconds} s`;
    const hours = seconds / 3600;
    if (hours >= 1) return `${String(hours).replace('.', ',')} uur`;
    return `${seconds / 60} min`;
  }

  const KIND = { series: 'Serie', film: 'Film', episode: 'Aflevering' };

  function episodeCode(episode) {
    return `S${episode.season} · A${episode.number}`;
  }

  function displayTitle(playable) {
    const parent = seriesOf(playable);
    return parent ? `${parent.title}: ${playable.title}` : playable.title;
  }

  // ---------------------------------------------------------------- render helpers

  let handlers = new Map();
  let menus = new Map();
  let reqs = new Map();
  let screenReqs = '';

  function focusable(id, options, inner) {
    handlers.set(id, options.onSelect || null);
    if (options.menu) menus.set(id, options.menu);
    reqs.set(id, options.req || '');
    const label = options.label ? ` aria-label="${esc(options.label)}"` : '';
    return `<button type="button" tabindex="-1" class="f ${options.cls || ''}" data-f="${esc(id)}"${label}>${inner}</button>`;
  }

  function art(item, extra) {
    const seed = [...item.id].reduce((sum, ch) => sum + ch.charCodeAt(0), 0);
    const initials = item.title.split(/\s+/).filter((w) => /^[A-Z0-9]/i.test(w)).slice(0, 2)
      .map((w) => w[0].toUpperCase()).join('');
    return `<div class="art${item.available ? '' : ' art-gone'}" style="--angle:${(seed * 37) % 180}deg" aria-hidden="true">
      <span class="art-initials">${esc(initials)}</span>
      <span class="art-kind">${KIND[item.kind]}</span>${extra || ''}</div>`;
  }

  function progressBar(progress, duration) {
    const pct = Math.min(100, Math.round((progress.pos / duration) * 100));
    return `<div class="bar" aria-hidden="true"><i style="width:${pct}%"></i></div>`;
  }

  // One tile shape for every row: artwork, title, a line of state, progress.
  function tile(id, options) {
    const { item, title, line, state, progress, duration, onSelect, menu, req, label } = options;
    const stateBadge = state ? `<span class="badge badge-${state.kind}">${state.text}</span>` : '';
    const bar = progress && progress.pos > 0 && !progress.watched ? progressBar(progress, duration) : '';
    return focusable(id, { cls: 'tile', onSelect, menu, req, label },
      `${art(item, stateBadge)}
      <span class="tile-meta">
        <span class="tile-title">${esc(title)}</span>
        <span class="tile-line">${line ? esc(line) : '&nbsp;'}</span>
        ${bar}
      </span>`);
  }

  function row(title, key, tiles, empty) {
    return `<section class="row" aria-label="${esc(title)}">
      <h2 class="row-title">${esc(title)}</h2>
      <div class="scroller" data-row="${key}">${tiles.length ? tiles.join('') : empty}</div>
    </section>`;
  }

  function icon(name) {
    const paths = {
      search: '<circle cx="10" cy="10" r="6.5"/><path d="M15 15l5 5"/>',
      gear: '<circle cx="12" cy="12" r="3.2"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"/>',
      star: '<path d="M12 3l2.6 5.6 6 .7-4.5 4.1 1.2 6L12 16.4 6.7 19.4l1.2-6L3.4 9.3l6-.7z"/>',
      person: '<circle cx="12" cy="8" r="4"/><path d="M4 21c1.2-4.2 4.3-6.3 8-6.3s6.8 2.1 8 6.3"/>',
      play: '<path d="M8 5l11 7-11 7z"/>',
      check: '<path d="M4.5 12.5l5 5 10-11"/>',
      plus: '<path d="M12 5v14M5 12h14"/>',
      pin: '<path d="M9 3h6l-1 6 4 4H6l4-4zM12 13v8"/>',
      back: '<path d="M15 5l-7 7 7 7"/>',
      del: '<path d="M9 6h11v12H9l-6-6z"/><path d="M12.5 9.5l5 5M17.5 9.5l-5 5"/>',
    };
    return `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${paths[name]}</svg>`;
  }

  // ---------------------------------------------------------------- screens

  const SCREENS = {
    signin: signinScreen,
    home: homeScreen,
    detail: detailScreen,
    search: searchScreen,
    player: playerScreen,
    settings: settingsScreen,
  };

  function modeBadge() {
    return isKids()
      ? `<div class="mode-badge" role="status">${icon('star')}<span>Kindermodus</span></div>`
      : '';
  }

  function offlineBanner() {
    return S.scenario.offline
      ? '<div class="offline" role="status">Geen verbinding. Je ziet wat deze Apple TV nog weet; zoeken en afspelen lukken pas weer met internet.</div>'
      : '';
  }

  // ---- sign-in (FR-AUTH-01, FR-AUTH-06, FR-AUTH-08)

  function newSignin() {
    const digits = Array.from({ length: 8 }, () => Math.floor(Math.random() * 10)).join('');
    S.signin = { phase: 'waiting', code: digits, expiresAt: Date.now() + 5 * 60 * 1000 };
  }

  function signinScreen() {
    screenReqs = 'FR-AUTH-01 FR-AUTH-06';
    const signin = S.signin;
    const code = `${signin.code.slice(0, 4)} ${signin.code.slice(4)}`;
    const remaining = Math.max(0, Math.round((signin.expiresAt - Date.now()) / 1000));
    let status = '';
    if (signin.phase === 'waiting') {
      status = `<p class="signin-wait"><span class="spinner" aria-hidden="true"></span>Wachten op goedkeuring. Deze tv gaat vanzelf verder. <span class="signin-expiry">De code verloopt over <b data-live="expiry">${clock(remaining)}</b>.</span></p>`;
    } else if (signin.phase === 'checking') {
      status = '<p class="signin-wait"><span class="spinner" aria-hidden="true"></span>Goedgekeurd. We controleren je NPO Plus-abonnement…</p>';
    } else {
      const copy = {
        expired: ['De code is verlopen.', 'Er is niet op tijd goedgekeurd. Vraag een nieuwe code aan en probeer het nog eens.', 'Nieuwe code'],
        denied: ['Inloggen is afgebroken.', 'Op de telefoon is het koppelen geweigerd of gestopt. Je kunt het opnieuw proberen.', 'Opnieuw beginnen'],
        error: ['Geen verbinding met NPO.', 'Deze tv kan NPO nu niet bereiken. Controleer het netwerk en probeer het opnieuw.', 'Opnieuw proberen'],
      }[signin.phase];
      status = `<div class="signin-problem" role="alert"><p><b>${copy[0]}</b> ${copy[1]}</p>
        ${focusable('signin:retry', { cls: 'btn btn-primary', req: 'FR-AUTH-06', onSelect: () => { newSignin(); commit(); } }, esc(copy[2]))}</div>`;
    }
    const faded = signin.phase === 'waiting' || signin.phase === 'checking' ? '' : ' is-stale';
    return `<div class="screen signin">
      <div class="signin-brand">NPO light</div>
      <h1>Log in met je NPO Plus-account</h1>
      <div class="signin-body${faded}">
        <ol class="signin-steps">
          <li>Scan de QR-code met je telefoon<br><span class="or">of ga naar</span> <b class="signin-url">id.npo.nl/koppel</b></li>
          <li>Vul deze code in:<div class="signin-code" aria-label="Code ${signin.code.split('').join(' ')}">${code}</div></li>
          <li>Log in bij NPO en keur de koppeling goed.</li>
        </ol>
        <figure class="qr"><canvas width="29" height="29" data-qr="${signin.code}" aria-hidden="true"></canvas>
          <figcaption>Wireframe: geen echte QR-code. De app maakt hem op het apparaat, met het volledige adres inclusief code.</figcaption></figure>
      </div>
      ${status}
    </div>`;
  }

  // ---- home (FR-HOME-*)

  function homeScreen() {
    screenReqs = 'FR-HOME-01 FR-MODE-03 NFR-A11Y-01';
    const mode = md();
    const pins = mode.pins.map((pin) => get(pin.id)).filter((item) => item && visibleInMode(item));
    const recent = recentVisible().map((entry) => get(entry.id));
    const later = mode.later.map((entry) => get(entry.id)).filter(Boolean);

    const emptyPinned = emptyState('pinned', 'Nog niets vastgezet.',
      'Zoek een serie of film en zet hem vast. Dan staat hij hier, met de volgende aflevering klaar.', 'FR-HOME-09');
    const emptyRecent = emptyState('recent', 'Nog niets bekeken.',
      'Wat je gaat kijken, komt hier te staan. Zoek iets om te beginnen.', 'FR-HOME-09');

    return `<div class="screen home">
      <header class="topbar">
        <div class="brand">NPO light</div>
        ${modeBadge()}
        <nav class="topnav" aria-label="Hoofdmenu">
          ${focusable('top:search', { cls: 'pill', req: 'FR-SEARCH-01', label: 'Zoeken', onSelect: openSearch }, `${icon('search')}<span>Zoeken</span>`)}
          ${focusable('top:mode', { cls: 'pill', req: 'FR-MODE-02 FR-MODE-03', onSelect: switchMode },
    isKids() ? `${icon('person')}<span>Naar gewone modus</span>` : `${icon('star')}<span>Naar kindermodus</span>`)}
          ${isKids() ? '' : focusable('top:settings', { cls: 'pill', req: 'FR-SET-01 FR-MODE-06', label: 'Instellingen', onSelect: () => push('settings') }, `${icon('gear')}<span>Instellingen</span>`)}
        </nav>
      </header>
      ${offlineBanner()}
      <div class="vscroll home-rows">
        ${row('Vastgezet', 'pinned', pins.map(pinnedTile), emptyPinned)}
        ${row('Recent bekeken', 'recent', recent.map(recentTile), emptyRecent)}
        ${later.length ? row('Later kijken', 'later', later.map(laterTile), '') : ''}
      </div>
      <footer class="hint">OK: kiezen · OK ingedrukt houden: meer opties · Menu: terug</footer>
    </div>`;
  }

  function emptyState(key, title, body, req) {
    return `<div class="empty"><p><b>${esc(title)}</b> ${esc(body)}</p>
      ${focusable(`${key}:empty`, { cls: 'btn', req, onSelect: openSearch }, `${icon('search')}<span>Zoeken</span>`)}</div>`;
  }

  function unavailableState() {
    return { kind: 'gone', text: 'Niet meer beschikbaar' };
  }

  function playLabel(playable) {
    const progress = progressOf(playable.id);
    return progress.pos > 0 && !progress.watched ? 'Verder kijken' : 'Afspelen';
  }

  function pinnedTile(item) {
    const id = `pinned:${item.id}`;
    const common = {
      item,
      title: item.title,
      req: 'FR-HOME-02 FR-HOME-04 FR-HOME-05',
      menu: () => [
        ...playMenuEntries(item),
        { label: 'Losmaken', run: () => removeWithFallback('pinned', item.id, () => togglePin(item)) },
      ],
    };
    if (!item.available) {
      return tile(id, Object.assign(common, {
        line: KIND[item.kind], state: unavailableState(), req: 'FR-CONTENT-05 FR-HOME-05',
        label: `${item.title}, ${KIND[item.kind].toLowerCase()}, niet meer beschikbaar`,
        onSelect: () => openDetail(item),
      }));
    }
    if (item.kind === 'series') {
      const next = nextEpisode(item);
      if (!next) {
        return tile(id, Object.assign(common, {
          line: 'Alle afleveringen gezien', state: { kind: 'done', text: `${icon('check')}Uitgekeken` },
          label: `${item.title}, serie, alle afleveringen gezien`,
          onSelect: () => openDetail(item),
        }));
      }
      const progress = progressOf(next.id);
      const left = next.duration - progress.pos;
      return tile(id, Object.assign(common, {
        line: `${episodeCode(next)} · ${next.title}${progress.pos > 0 ? ` · nog ${minutesText(left)}` : ''}`,
        progress, duration: next.duration,
        label: `${item.title}, serie. ${playLabel(next)}: seizoen ${next.season}, aflevering ${next.number}, ${next.title}${progress.pos > 0 ? `, nog ${minutesText(left)}` : ''}`,
        onSelect: () => play(next),
      }));
    }
    const progress = progressOf(item.id);
    return tile(id, Object.assign(common, {
      line: progress.pos > 0 && !progress.watched ? `${KIND[item.kind]} · nog ${minutesText(item.duration - progress.pos)}` : `${KIND[item.kind]} · ${minutesText(item.duration)}`,
      progress, duration: item.duration,
      label: `${item.title}, ${KIND[item.kind].toLowerCase()}`,
      onSelect: () => play(item),
    }));
  }

  function recentTile(item) {
    const id = `recent:${item.id}`;
    const finished = finishedAt(item) !== null;
    const playable = item.kind === 'series'
      ? (nextEpisode(item) || get(md().current[item.id] || ''))
      : item;
    const saveEntry = playable && playable.kind !== 'series' && item.available
      ? [{
        label: isSaved(playable) ? 'Uit Later kijken halen' : (item.kind === 'series' ? 'Deze aflevering later kijken' : 'Later kijken'),
        run: () => toggleSaved(playable),
      }]
      : [];
    const common = {
      item,
      title: item.title,
      req: 'FR-HOME-06 FR-HOME-07 FR-HOME-08 FR-LATER-03',
      menu: () => [
        ...playMenuEntries(item),
        ...saveEntry,
        { label: 'Verwijderen uit Recent bekeken', run: () => removeWithFallback('recent', item.id, () => removeFromRecent(item)) },
      ],
    };
    if (!item.available) {
      return tile(id, Object.assign(common, {
        line: KIND[item.kind], state: unavailableState(), onSelect: () => openDetail(item),
        label: `${item.title}, niet meer beschikbaar`,
      }));
    }
    if (finished) {
      return tile(id, Object.assign(common, {
        line: item.kind === 'series' ? 'Alle afleveringen gezien' : `${KIND[item.kind]} · gezien`,
        state: { kind: 'done', text: `${icon('check')}Uitgekeken` },
        label: `${item.title}, ${KIND[item.kind].toLowerCase()}, uitgekeken`,
        onSelect: () => openDetail(item),
      }));
    }
    const progress = progressOf(playable.id);
    const left = playable.duration - progress.pos;
    const code = item.kind === 'series' ? `${episodeCode(playable)} · ` : '';
    const line = progress.pos > 0 ? `${code}nog ${minutesText(left)}` : `${code}${playable.title}`;
    return tile(id, Object.assign(common, {
      line, progress, duration: playable.duration,
      label: `${item.title}, ${KIND[item.kind].toLowerCase()}. ${progress.pos > 0 ? `${Math.round((progress.pos / playable.duration) * 100)} procent gezien, nog ${minutesText(left)}` : `Volgende: ${playable.title}`}`,
      onSelect: () => play(playable),
    }));
  }

  function laterTile(playable) {
    const id = `later:${playable.id}`;
    const parent = seriesOf(playable);
    const available = playable.available && (!parent || parent.available);
    const progress = progressOf(playable.id);
    const common = {
      item: playable,
      title: parent ? parent.title : playable.title,
      req: 'FR-LATER-04 FR-LATER-05 FR-LATER-08 FR-LATER-09 FR-LATER-12',
      menu: () => [
        ...(available ? [{ label: playLabel(playable), run: () => play(playable) }] : []),
        { label: 'Details', run: () => openDetail(itemOf(playable)) },
        { label: 'Verwijderen uit Later kijken', run: () => removeWithFallback('later', playable.id, () => toggleSaved(playable)) },
      ],
    };
    if (!available) {
      return tile(id, Object.assign(common, {
        line: parent ? playable.title : KIND[playable.kind], state: unavailableState(),
        req: 'FR-LATER-11', onSelect: () => openDetail(itemOf(playable)),
        label: `${displayTitle(playable)}, niet meer beschikbaar`,
      }));
    }
    const line = parent
      ? `${episodeCode(playable)} · ${playable.title}`
      : `${KIND[playable.kind]} · ${progress.pos > 0 ? `nog ${minutesText(playable.duration - progress.pos)}` : minutesText(playable.duration)}`;
    return tile(id, Object.assign(common, {
      line, progress, duration: playable.duration,
      label: `${displayTitle(playable)}, ${KIND[playable.kind].toLowerCase()}`,
      onSelect: () => play(playable),
    }));
  }

  function playMenuEntries(item) {
    const playable = playableFor(item);
    const entries = [];
    if (playable && finishedAt(item) === null) entries.push({ label: playLabel(playable), run: () => play(playable) });
    entries.push({ label: 'Details', run: () => openDetail(item) });
    return entries;
  }

  // FR-HOME-10, NFR-A11Y-01: after a tile goes, focus lands on a neighbour.
  function removeWithFallback(rowKey, id, remove) {
    const ids = [...document.querySelectorAll(`[data-row="${rowKey}"] [data-f]`)].map((el) => el.dataset.f);
    const index = ids.indexOf(`${rowKey}:${id}`);
    T.fallback = [ids[index + 1], ids[index - 1]].filter(Boolean);
    T.fallback.push(`${rowKey}:empty`);
    ['pinned', 'recent', 'later'].filter((key) => key !== rowKey).forEach((key) => {
      const first = document.querySelector(`[data-row="${key}"] [data-f]`);
      if (first) T.fallback.push(first.dataset.f);
    });
    T.focus = null;
    remove();
  }

  // ---- detail (FR-CONTENT-03)

  function detailScreen(params) {
    const item = get(params.id);
    screenReqs = 'FR-CONTENT-03 FR-MODE-03';
    const actions = [];
    const playable = playableFor(item);
    if (!item.available) {
      screenReqs += ' FR-CONTENT-05';
    } else if (playable) {
      const progress = progressOf(playable.id);
      const sub = item.kind === 'series' ? `<small>${episodeCode(playable)} · ${esc(playable.title)}</small>` : '';
      actions.push(focusable('detail:play', { cls: 'btn btn-primary', req: 'FR-CONTENT-03 FR-PLAY-02 FR-HOME-04', onSelect: () => play(playable) },
        `${icon('play')}<span>${playLabel(playable)}${sub}</span>${progress.pos > 0 && !progress.watched ? progressBar(progress, playable.duration) : ''}`));
    }
    if (item.kind !== 'episode' || !item.seriesId) {
      const pinned = isPinned(item);
      actions.push(focusable('detail:pin', { cls: 'btn', req: 'FR-HOME-03 FR-HOME-05 FR-CONTENT-03', onSelect: () => togglePin(item) },
        pinned ? `${icon('check')}<span>Vastgezet<small>Kies om los te maken</small></span>` : `${icon('pin')}<span>Vastzetten</span>`));
    }
    if (item.kind !== 'series' && (item.available || isSaved(item))) {
      actions.push(saveButton('detail:save', item, 'btn', 'FR-LATER-02 FR-LATER-03 FR-LATER-09'));
    }
    const notice = !item.available
      ? '<p class="notice" role="alert"><b>Niet meer beschikbaar.</b> Dit programma is uit het aanbod van NPO gehaald. Je kunt het nog losmaken of van je lijst halen.</p>'
      : (item.kind === 'series' && !playable ? '<p class="notice"><b>Alle afleveringen gezien.</b> Kies hieronder een aflevering om hem opnieuw te kijken.</p>' : '');
    let meta = KIND[item.kind];
    if (item.kind === 'series') {
      const count = CAT.episodes(item).length;
      meta += ` · ${plural(item.seasons.length, 'seizoen', 'seizoenen')} · ${plural(count, 'aflevering', 'afleveringen')}`;
    } else {
      meta += ` · ${minutesText(item.duration)}`;
    }
    return `<div class="screen detail">
      ${modeBadge()}
      ${offlineBanner()}
      <div class="vscroll">
        <div class="detail-head">
          ${art(item, item.available ? '' : `<span class="badge badge-gone">Niet meer beschikbaar</span>`)}
          <div class="detail-info">
            <p class="eyebrow">${esc(meta)}</p>
            <h1>${esc(item.title)}</h1>
            <p class="desc">${esc(item.description)}</p>
            ${notice}
            <div class="actions">${actions.join('')}</div>
          </div>
        </div>
        ${item.kind === 'series' ? episodeList(item) : ''}
      </div>
    </div>`;
  }

  function saveButton(id, playable, cls, req) {
    const saved = isSaved(playable);
    return focusable(id, { cls, req, onSelect: () => toggleSaved(playable), label: saved ? `${displayTitle(playable)} uit Later kijken halen` : `${displayTitle(playable)} later kijken` },
      saved ? `${icon('check')}<span>Bij Later kijken<small>Kies om te verwijderen</small></span>` : `${icon('plus')}<span>Later kijken</span>`);
  }

  function episodeList(item) {
    return item.seasons.map((season) => `
      <section class="season" aria-label="Seizoen ${season.number}">
        <h2 class="row-title">Seizoen ${season.number}</h2>
        <div class="episodes">${season.episodes.map((episode) => episodeRow(episode)).join('')}</div>
      </section>`).join('');
  }

  function episodeRow(episode) {
    const progress = progressOf(episode.id);
    let state = '';
    let stateText = 'Niet gezien';
    if (!episode.available) {
      state = '<span class="ep-state is-gone">⊘ Niet beschikbaar</span>';
      stateText = 'Niet beschikbaar';
    } else if (progress.watched) {
      state = `<span class="ep-state is-done">${icon('check')}Gezien</span>`;
      stateText = 'Gezien';
    } else if (progress.pos > 0) {
      state = `<span class="ep-state is-part">◐ nog ${minutesText(episode.duration - progress.pos)}</span>`;
      stateText = `Half gezien, nog ${minutesText(episode.duration - progress.pos)}`;
    } else {
      state = '<span class="ep-state">○ Niet gezien</span>';
    }
    const main = focusable(`ep:${episode.id}`, {
      cls: `ep${episode.available ? '' : ' ep-gone'}`,
      req: episode.available ? 'FR-CONTENT-02 FR-CONTENT-03 NFR-A11Y-04' : 'FR-CONTENT-02 FR-CONTENT-05',
      label: `Aflevering ${episode.number}, ${episode.title}, ${minutesText(episode.duration)}, ${stateText}`,
      onSelect: () => play(episode),
    }, `<span class="ep-num">${episode.number}</span>
      <span class="ep-title">${esc(episode.title)}${progress.pos > 0 && !progress.watched ? progressBar(progress, episode.duration) : ''}</span>
      <span class="ep-dur">${minutesText(episode.duration)}</span>${state}`);
    const saver = episode.available || isSaved(episode)
      ? saveButton(`epsave:${episode.id}`, episode, 'btn btn-small', 'FR-LATER-02 FR-LATER-03')
      : '<span class="btn-spacer"></span>';
    return `<div class="ep-row">${main}${saver}</div>`;
  }

  // ---- search (FR-SEARCH-*)

  const KEYS = 'abcdefghijklmnopqrstuvwxyz'.split('');

  function searchScreen() {
    screenReqs = 'FR-SEARCH-01 FR-SEARCH-02 FR-SEARCH-03';
    const search = T.search;
    const keyboard = KEYS.map((key) => focusable(`kb:${key}`, { cls: 'key', req: 'FR-SEARCH-03', onSelect: () => typeText(key) }, key)).join('')
      + focusable('kb:space', { cls: 'key key-wide', req: 'FR-SEARCH-03', label: 'Spatie', onSelect: () => typeText(' ') }, 'spatie')
      + focusable('kb:del', { cls: 'key key-wide', req: 'FR-SEARCH-02', label: 'Wis teken', onSelect: deleteChar }, icon('del'))
      + focusable('kb:clear', { cls: 'key key-wide', req: 'FR-SEARCH-04', label: 'Veld leegmaken', onSelect: clearQuery }, 'leeg');
    const placeholder = isKids() ? 'Zoek in het aanbod voor kinderen' : 'Zoek naar series, films en afleveringen';
    return `<div class="screen search">
      ${modeBadge()}
      ${offlineBanner()}
      <div class="search-field${search.query ? '' : ' is-empty'}" role="textbox" aria-label="Zoekveld">
        ${icon('search')}<span data-live="query">${esc(search.query) || esc(placeholder)}</span><i class="caret" aria-hidden="true"></i>
      </div>
      <div class="keyboard" data-row="keyboard">${keyboard}</div>
      <div class="vscroll search-body">${search.query ? searchResults() : recentSearches()}</div>
    </div>`;
  }

  function recentSearches() {
    const searches = md().searches;
    if (!searches.length) {
      return '<p class="empty-line">Je hebt nog niet gezocht. Typ een paar letters; de resultaten verschijnen terwijl je typt.</p>';
    }
    const rows = searches.map((entry, index) => {
      const picks = entry.picks.map((id) => get(id)).filter((item) => item && visibleInMode(item));
      const term = focusable(`term:${index}`, {
        cls: 'term', req: 'FR-SEARCH-05 FR-SEARCH-06 FR-SEARCH-07',
        label: `Zoek opnieuw naar ${entry.term}`,
        onSelect: () => runTerm(entry.term),
        menu: () => [
          { label: `Zoek naar “${entry.term}”`, run: () => runTerm(entry.term) },
          { label: 'Verwijderen', run: () => deleteTerm(entry.term, index) },
        ],
      }, `${icon('search')}<span>${esc(entry.term)}</span>`);
      const pickTiles = picks.map((item) => focusable(`pick:${index}:${item.id}`, {
        cls: 'pick', req: 'FR-SEARCH-06', label: `${item.title}, ${KIND[item.kind].toLowerCase()}, direct openen`,
        onSelect: () => openDetail(item),
      }, `${art(item)}<span>${esc(item.title)}</span>`)).join('');
      return `<div class="recent-search" data-row="term-${index}">${term}${pickTiles || '<span class="no-picks">Nog niets gekozen</span>'}</div>`;
    }).join('');
    return `<h2 class="row-title">Recente zoekopdrachten</h2>
      <div class="recent-searches">${rows}</div>
      <div class="search-foot">${focusable('search:clearall', { cls: 'btn btn-small', req: 'FR-SEARCH-07', onSelect: confirmClearHistory }, 'Zoekgeschiedenis wissen')}
      <span class="foot-note">Houd OK ingedrukt op een zoekterm om hem te verwijderen.</span></div>`;
  }

  function searchResults() {
    const search = T.search;
    if (search.status === 'error') {
      return `<div class="state-msg" role="alert"><p><b>Zoeken lukt nu niet.</b> Er is geen verbinding met NPO. Wat je typte blijft staan.</p>
        ${focusable('search:retry', { cls: 'btn btn-primary', req: 'FR-SEARCH-09 NFR-REL-02', onSelect: () => scheduleSearch(0) }, 'Opnieuw proberen')}</div>`;
    }
    if (search.status !== 'done' || search.forQuery !== search.query) {
      return `<p class="loading-line"><span class="spinner" aria-hidden="true"></span>Zoeken naar “${esc(search.query)}”…</p>
        <div class="results">${'<div class="tile skeleton"><div class="art"></div></div>'.repeat(5)}</div>`;
    }
    if (!search.results.length) {
      return `<p class="empty-line" role="status">Niets gevonden voor “${esc(search.query)}”.${isKids() ? ' Je zoekt in het aanbod voor kinderen.' : ''}</p>`;
    }
    const tiles = search.results.map((item) => {
      const tileHtml = tile(`result:${item.id}`, {
        item, title: item.title, line: item.kind === 'series' ? `${KIND.series} · ${plural(CAT.episodes(item).length, 'aflevering', 'afleveringen')}` : `${KIND[item.kind]} · ${minutesText(item.duration)}`,
        state: item.available ? null : unavailableState(),
        req: 'FR-SEARCH-02 FR-SEARCH-05 FR-CONTENT-03',
        label: `${item.title}, ${KIND[item.kind].toLowerCase()}`,
        onSelect: () => { rememberSearch(search.query, item.id); save(); openDetail(item); },
      });
      const saver = item.kind !== 'series' && item.available
        ? saveButton(`rsave:${item.id}`, item, 'btn btn-small', 'FR-LATER-03')
        : '<span class="btn-spacer"></span>';
      return `<div class="result">${tileHtml}${saver}</div>`;
    }).join('');
    return `<h2 class="row-title">${plural(search.results.length, 'resultaat', 'resultaten')} voor “${esc(search.query)}”</h2>
      <div class="results">${tiles}</div>`;
  }

  // ---- player (FR-PLAY-*)

  function playerScreen() {
    screenReqs = 'FR-PLAY-01 FR-PLAY-02 FR-PLAY-03';
    const player = T.player;
    const playable = get(player.id);
    const parent = seriesOf(playable);
    let overlay = '';
    if (player.overlay) overlay = playerOverlay(player, playable);
    const pct = Math.min(100, (player.pos / player.duration) * 100);
    const mark = (threshold(player.duration) / player.duration) * 100;
    return `<div class="screen player${player.playing ? ' is-playing' : ''}">
      <div class="video" aria-hidden="true"><span>${esc(parent ? parent.title : playable.title)}</span></div>
      <div class="player-note">tvOS-systeemspeler · de app voegt geen eigen knoppen toe</div>
      ${modeBadge()}
      <div class="transport" aria-label="Voortgang">
        <div class="transport-title">${esc(parent ? `${parent.title} · ${episodeCode(playable)}` : KIND[playable.kind])}<b>${esc(playable.title)}</b></div>
        <div class="transport-bar"><i data-live="bar" style="width:${pct}%"></i><em style="left:${mark}%" title="Vanaf hier telt hij als gezien"></em></div>
        <div class="transport-times"><span data-live="elapsed">${clock(player.pos)}</span>
          <span class="transport-state" data-live="state">${player.playing ? '▶ Speelt' : '❚❚ Gepauzeerd'} · ${S.scenario.speed}× versneld</span>
          <span data-live="remaining">-${clock(player.duration - player.pos)}</span></div>
      </div>
      ${overlay}
    </div>`;
  }

  function playerOverlay(player, playable) {
    const overlay = player.overlay;
    if (overlay.type === 'next') {
      screenReqs += ' FR-PLAY-05 FR-PLAY-07';
      return `<div class="next-card layer" role="status">
        <p class="eyebrow">Volgende aflevering speelt</p>
        <p class="next-title">${episodeCode(playable)} · ${esc(playable.title)}</p>
        ${focusable('player:stop', { cls: 'btn btn-primary', req: 'FR-PLAY-05', onSelect: stopPlayback }, 'Stoppen')}
        <span class="next-hide" data-live="nexthide">${overlay.remaining}</span></div>`;
    }
    if (overlay.type === 'countdown') {
      screenReqs += ' FR-PLAY-06 NFR-A11Y-02';
      const next = get(overlay.nextId);
      return `<div class="countdown layer" role="alert" aria-live="assertive">
        <p class="countdown-lead">Zo meteen:</p>
        <p class="countdown-title">${esc(next.title)}</p>
        <div class="countdown-ring"><span data-live="countdown">${overlay.remaining}</span></div>
        <p class="countdown-sub">Nog <b data-live="countdown2">${plural(overlay.remaining, 'tel', 'tellen')}</b>, dan begint de volgende aflevering.</p>
        ${focusable('player:stop', { cls: 'btn btn-primary btn-big', req: 'FR-PLAY-06', onSelect: stopPlayback }, 'Stoppen')}</div>`;
    }
    if (overlay.type === 'still') {
      screenReqs += ' FR-PLAY-08';
      return `<div class="dialog layer" role="alertdialog" aria-label="Kijk je nog?">
        <h2>Kijk je nog?</h2>
        <p>Er is ${durationSetting(isKids() ? S.settings.kidsStill : S.settings.normalStill)} achter elkaar gekeken. Zonder antwoord stopt het afspelen over <b data-live="grace">${overlay.remaining}</b> seconden.</p>
        <div class="dialog-actions">
          ${focusable('player:continue', { cls: 'btn btn-primary', req: 'FR-PLAY-08', onSelect: continueWatching }, 'Doorkijken')}
          ${focusable('player:quit', { cls: 'btn', req: 'FR-PLAY-08', onSelect: stopPlayback }, 'Stoppen')}
        </div></div>`;
    }
    screenReqs += ' FR-PLAY-10';
    return `<div class="dialog layer" role="alertdialog" aria-label="Afspelen lukt niet">
      <h2>Afspelen lukt niet</h2>
      <p>${esc(displayTitle(playable))} wil nu niet starten. Je plek blijft bewaard, dus opnieuw proberen gaat verder waar je was.</p>
      <div class="dialog-actions">
        ${focusable('player:retry', { cls: 'btn btn-primary', req: 'FR-PLAY-10 FR-PLAY-11', onSelect: retryPlayback }, 'Opnieuw proberen')}
        ${focusable('player:back', { cls: 'btn', req: 'FR-PLAY-10', onSelect: stopPlayback }, 'Terug')}
      </div></div>`;
  }

  // ---- settings (FR-SET-*)

  function settingsScreen() {
    screenReqs = 'FR-SET-01 FR-SET-02 FR-MODE-06';
    const choices = (key, label, req) => `
      <div class="setting">
        <div class="setting-label">${esc(label)}</div>
        <div class="chips" data-row="set-${key}">${SETTING_CHOICES[key].map((value) => {
    const selected = S.settings[key] === value;
    return focusable(`set:${key}:${value}`, {
      cls: `chip${selected ? ' is-selected' : ''}`, req,
      label: `${label}: ${durationSetting(value)}${selected ? ', gekozen' : ''}`,
      onSelect: () => { S.settings[key] = value; commit(); },
    }, `${selected ? icon('check') : ''}${durationSetting(value)}`);
  }).join('')}</div>
      </div>`;
    return `<div class="screen settings">
      ${offlineBanner()}
      <div class="vscroll">
        <h1>Instellingen</h1>
        <section class="settings-group">
          <h2 class="row-title">Afspelen</h2>
          ${choices('kidsPause', 'Pauze tussen afleveringen in kindermodus', 'FR-SET-02 FR-PLAY-06')}
          ${choices('kidsStill', '“Kijk je nog?” in kindermodus, na', 'FR-SET-02 FR-PLAY-08')}
          ${choices('normalStill', '“Kijk je nog?” in gewone modus, na', 'FR-SET-02 FR-PLAY-08')}
        </section>
        <section class="settings-group">
          <h2 class="row-title">Gegevens op deze Apple TV</h2>
          <p class="setting-note">Vastgezet, recent bekeken, later kijken, kijkposities en zoekgeschiedenis staan alleen op deze Apple TV. Er wordt niets gesynchroniseerd.</p>
          <div class="button-row" data-row="erase">
            ${focusable('set:erase:normal', { cls: 'btn', req: 'FR-SET-04 NFR-PRIV-04', onSelect: () => confirmErase(['normal']) }, 'Wis gewone modus')}
            ${focusable('set:erase:kids', { cls: 'btn', req: 'FR-SET-04 NFR-PRIV-04', onSelect: () => confirmErase(['kids']) }, 'Wis kindermodus')}
            ${focusable('set:erase:both', { cls: 'btn', req: 'FR-SET-04 NFR-PRIV-04', onSelect: () => confirmErase(['normal', 'kids']) }, 'Wis beide modi')}
          </div>
        </section>
        <section class="settings-group">
          <h2 class="row-title">Account</h2>
          <div class="button-row" data-row="account">
            ${focusable('set:signout', { cls: 'btn', req: 'FR-SET-03 FR-AUTH-04', onSelect: confirmSignOut }, 'Afmelden')}
          </div>
        </section>
      </div>
    </div>`;
  }

  // ---------------------------------------------------------------- overlays

  function menuLayer() {
    if (!T.menu) return '';
    const items = T.menu.items.map((entry, index) => focusable(`menu:${index}`, {
      cls: 'menu-item', req: T.menu.req,
      onSelect: () => { closeMenu(false); entry.run(); },
    }, esc(entry.label))).join('');
    return `<div class="scrim"></div><div class="menu layer" role="menu" aria-label="${esc(T.menu.title)}">
      <p class="menu-title">${esc(T.menu.title)}</p>${items}</div>`;
  }

  function dialogLayer() {
    if (!T.dialog) return '';
    const dialog = T.dialog;
    const buttons = dialog.actions.map((action, index) => focusable(`dialog:${index}`, {
      cls: `btn${index === 0 ? ' btn-primary' : ''}`, req: dialog.req,
      onSelect: () => {
        T.dialog = null;
        if (action.run) action.run();
        else { T.focus = T.dialogReturn; render(); }
      },
    }, esc(action.label))).join('');
    return `<div class="scrim"></div><div class="dialog layer" role="alertdialog" aria-label="${esc(dialog.title)}">
      <h2>${esc(dialog.title)}</h2>${dialog.body.map((p) => `<p>${p}</p>`).join('')}
      <div class="dialog-actions">${buttons}</div></div>`;
  }

  function openDialog(dialog) {
    T.dialogReturn = T.focus;
    T.dialog = dialog;
    T.focus = 'dialog:0';
    render();
  }

  function toast(text) {
    T.toast = text;
    clearTimeout(T.toastTimer);
    T.toastTimer = setTimeout(() => {
      T.toast = null;
      const el = document.querySelector('.toast');
      if (el) el.remove();
    }, 2600);
  }

  // ---------------------------------------------------------------- navigation

  function top() {
    return T.stack[T.stack.length - 1];
  }

  function push(screen, params) {
    if (top()) top().focus = T.focus;
    T.stack.push({ screen, params: params || {}, focus: null });
    T.focus = null;
    T.fallback = [];
    render();
  }

  function pop() {
    const leaving = T.stack.pop();
    if (leaving && leaving.screen === 'search' && T.search.query) {
      rememberSearch(T.search.query);
      save();
    }
    if (leaving && leaving.screen === 'player') endPlayer();
    T.focus = top().focus;
    T.fallback = [];
    render();
  }

  function goHome() {
    T.stack = [{ screen: 'home', params: {}, focus: null }];
    T.focus = null;
    render();
  }

  function back() {
    if (T.menu) { closeMenu(true); return; }
    if (T.dialog && T.dialog.cancellable !== false) { T.dialog = null; T.focus = T.dialogReturn; render(); return; }
    if (T.dialog) return;
    const current = top();
    if (current.screen === 'player' && T.player && T.player.overlay && T.player.overlay.type === 'countdown') {
      stopPlayback();
      return;
    }
    if (T.stack.length > 1) { pop(); return; }
    toast('Menu op dit scherm sluit de app en gaat terug naar tvOS');
    render();
  }

  function openSearch() {
    clearTimeout(T.search.timer);
    T.search.token += 1;
    T.search.query = '';
    T.search.status = 'idle';
    push('search');
  }

  function openDetail(item) {
    if (item.kind === 'episode' && item.seriesId) item = get(item.seriesId);
    push('detail', { id: item.id });
  }

  function switchMode() {
    S.mode = isKids() ? 'normal' : 'kids';
    save();
    toast(isKids() ? 'Kindermodus staat aan' : 'Gewone modus staat aan');
    T.focus = 'top:mode';
    render();
  }

  // ---------------------------------------------------------------- search behaviour

  function typeText(text) {
    T.search.query += text;
    afterQueryChange();
  }

  function deleteChar() {
    T.search.query = T.search.query.slice(0, -1);
    afterQueryChange();
  }

  function clearQuery() {
    T.search.query = '';
    afterQueryChange();
  }

  // FR-SEARCH-03: the field updates at once; the request is debounced, and a
  // superseded one is discarded by its token.
  function afterQueryChange() {
    T.search.status = T.search.query ? 'loading' : 'idle';
    T.search.token += 1;
    render();
    if (T.search.query) scheduleSearch(300);
  }

  function scheduleSearch(delay) {
    clearTimeout(T.search.timer);
    const token = T.search.token;
    const query = T.search.query;
    if (T.search.status === 'error') { T.search.status = 'loading'; render(); }
    T.search.timer = setTimeout(() => {
      const latency = S.scenario.slow ? 2500 : 250;
      setTimeout(() => {
        if (token !== T.search.token || top().screen !== 'search') return;
        if (S.scenario.offline) {
          T.search.status = 'error';
        } else {
          const needle = query.trim().toLowerCase();
          T.search.results = CAT.items.filter((item) => visibleInMode(item)
            && item.title.toLowerCase().split(/[\s&:]+/).some((word) => word.startsWith(needle) || item.title.toLowerCase().startsWith(needle)));
          T.search.status = 'done';
          T.search.forQuery = query;
        }
        render();
      }, latency);
    }, delay);
  }

  function runTerm(term) {
    T.search.query = term;
    afterQueryChange();
  }

  function deleteTerm(term, index) {
    md().searches = md().searches.filter((entry) => entry.term !== term);
    const next = md().searches.length ? `term:${Math.min(index, md().searches.length - 1)}` : 'kb:a';
    T.focus = next;
    toast(`“${term}” is verwijderd`);
    commit();
  }

  function confirmClearHistory() {
    openDialog({
      title: 'Zoekgeschiedenis wissen?',
      body: [`Alle recente zoekopdrachten in ${isKids() ? 'kindermodus' : 'gewone modus'} verdwijnen. De andere modus houdt zijn eigen geschiedenis.`],
      req: 'FR-SEARCH-07',
      actions: [
        { label: 'Wissen', run: () => { md().searches = []; T.focus = 'kb:a'; commit(); } },
        { label: 'Annuleren', run: () => { T.focus = 'search:clearall'; render(); } },
      ],
    });
  }

  // ---------------------------------------------------------------- playback behaviour

  function play(playable) {
    if (!playable.available || (seriesOf(playable) && !seriesOf(playable).available)) {
      openDialog({
        title: 'Niet meer beschikbaar',
        body: [`${esc(displayTitle(playable))} is uit het aanbod van NPO gehaald en kan niet meer worden afgespeeld.`],
        req: 'FR-CONTENT-05',
        actions: [{ label: 'OK' }],
      });
      return;
    }
    if (S.scenario.offline) {
      openDialog({
        title: 'Geen verbinding',
        body: ['Afspelen lukt pas weer als deze Apple TV met internet verbonden is.'],
        req: 'NFR-REL-01',
        actions: [{ label: 'OK' }],
      });
      return;
    }
    startPlayer(playable, { continued: false });
  }

  function startPlayer(playable, options) {
    const progress = progressOf(playable.id);
    let pos = progress.pos || 0;
    if (progress.watched) {
      // FR-PLAY-02, FR-HOME-07: played again deliberately, from the beginning.
      pos = 0;
      setProgress(playable.id, { pos: 0, watched: false, finishedAt: null });
    }
    recordPlay(playable);
    save();
    const still = options.continued && T.player ? T.player.still : 0;
    T.player = {
      id: playable.id, pos, duration: playable.duration, playing: true, still,
      overlay: null,
    };
    if (S.scenario.playbackFails) {
      T.player.playing = false;
      T.player.overlay = { type: 'error' };
    }
    if (options.continued) {
      T.focus = null;
      render();
    } else {
      push('player');
    }
    ensureTick();
  }

  function ensureTick() {
    if (T.tick) return;
    let last = performance.now();
    T.tick = setInterval(() => {
      const t = performance.now();
      const dt = (t - last) / 1000;
      last = t;
      tickPlayer(dt);
    }, 200);
  }

  function endPlayer() {
    if (T.player) setProgress(T.player.id, { pos: T.player.watchedAtEnd ? progressOf(T.player.id).pos : T.player.pos });
    clearInterval(T.tick);
    T.tick = null;
    T.player = null;
    save();
  }

  function tickPlayer(dt) {
    const player = T.player;
    if (!player || top().screen !== 'player') return;
    const overlay = player.overlay;
    if (overlay && overlay.type !== 'next') {
      if (overlay.type === 'countdown' || overlay.type === 'still') {
        overlay.acc = (overlay.acc || 0) + dt;
        if (overlay.acc >= 1) {
          overlay.acc -= 1;
          overlay.remaining -= 1;
          if (overlay.remaining <= 0) {
            if (overlay.type === 'countdown') startPlayer(get(overlay.nextId), { continued: true });
            else { endPlayer(); goHome(); toast('Afspelen gestopt: er kwam geen antwoord'); }
            return;
          }
          liveText('countdown', overlay.remaining);
          liveText('countdown2', plural(overlay.remaining, 'tel', 'tellen'));
          liveText('grace', overlay.remaining);
        }
      }
      return;
    }
    if (overlay && overlay.type === 'next') {
      overlay.acc = (overlay.acc || 0) + dt;
      if (overlay.acc >= 1) {
        overlay.acc -= 1;
        overlay.remaining -= 1;
        liveText('nexthide', overlay.remaining);
        if (overlay.remaining <= 0) { player.overlay = null; T.focus = null; render(); return; }
      }
    }
    if (!player.playing) return;
    const advance = dt * S.scenario.speed;
    player.pos = Math.min(player.duration, player.pos + advance);
    player.still += advance;
    const playable = get(player.id);
    // FR-PLAY-03: the position is written while playing.
    setProgress(player.id, progressOf(player.id).watched ? {} : { pos: player.pos });
    if (!progressOf(player.id).watched && player.pos >= threshold(player.duration)) {
      markWatched(playable);
      player.watchedAtEnd = true;
      save();
    }
    const limit = isKids() ? S.settings.kidsStill : S.settings.normalStill;
    if (player.still >= limit) {
      player.playing = false;
      player.overlay = { type: 'still', remaining: STILL_GRACE_SECONDS };
      T.focus = 'player:continue';
      save();
      render();
      return;
    }
    if (player.pos >= player.duration) {
      finishPlayback(playable);
      return;
    }
    updatePlayerLive();
  }

  // FR-PLAY-05, FR-PLAY-06, FR-PLAY-07.
  function finishPlayback(playable) {
    save();
    const next = seriesOf(playable) ? followingEpisode(playable) : null;
    if (!next) {
      const done = seriesOf(playable) ? 'Dat was de laatste aflevering' : 'Klaar met kijken';
      stopPlayback();
      toast(done);
      return;
    }
    const pause = isKids() ? S.settings.kidsPause : 0;
    if (pause > 0) {
      T.player.playing = false;
      T.player.overlay = { type: 'countdown', remaining: pause, nextId: next.id };
      T.focus = 'player:stop';
      render();
      return;
    }
    startPlayer(next, { continued: true });
    if (!T.player.overlay) {
      T.player.overlay = { type: 'next', remaining: NEXT_OVERLAY_SECONDS };
      T.focus = 'player:stop';
      render();
    }
  }

  // Back to wherever playback was started from.
  function stopPlayback() {
    const origin = T.stack.map((entry) => entry.screen).lastIndexOf('player');
    endPlayer();
    if (origin > 0) T.stack = T.stack.slice(0, origin);
    T.focus = top().focus;
    render();
  }

  function continueWatching() {
    T.player.still = 0;
    T.player.overlay = null;
    T.player.playing = true;
    T.focus = null;
    render();
  }

  function retryPlayback() {
    const playable = get(T.player.id);
    if (S.scenario.playbackFails) {
      toast('Lukt nog steeds niet. Zet “Playback fails” uit in het paneel.');
      render();
      return;
    }
    T.player.overlay = null;
    T.player.playing = true;
    T.player.pos = progressOf(playable.id).pos;
    T.focus = null;
    render();
  }

  function playerKey(action) {
    const player = T.player;
    if (!player || player.overlay || action === 'menu') return false;
    // FR-PLAY-08: any interaction restarts the still-watching timer.
    player.still = 0;
    if (action === 'select' || action === 'playpause') {
      player.playing = !player.playing;
    } else if (action === 'left') {
      player.pos = Math.max(0, player.pos - 10);
    } else if (action === 'right') {
      player.pos = Math.min(player.duration - 1, player.pos + 10);
    } else {
      return true;
    }
    render();
    return true;
  }

  function updatePlayerLive() {
    const player = T.player;
    const bar = document.querySelector('[data-live="bar"]');
    if (bar) bar.style.width = `${Math.min(100, (player.pos / player.duration) * 100)}%`;
    liveText('elapsed', clock(player.pos));
    liveText('remaining', `-${clock(player.duration - player.pos)}`);
  }

  function liveText(key, value) {
    const el = document.querySelector(`[data-live="${key}"]`);
    if (el) el.textContent = value;
  }

  // ---------------------------------------------------------------- settings behaviour

  function confirmErase(modes) {
    const names = modes.length === 2 ? 'beide modi' : (modes[0] === 'kids' ? 'kindermodus' : 'gewone modus');
    openDialog({
      title: `Gegevens van ${names} wissen?`,
      body: [
        `Dit verwijdert voorgoed van deze Apple TV: vastgezette programma’s, recent bekeken, later kijken, kijkposities en zoekgeschiedenis van ${names}.`,
        modes.length === 2 ? 'Je blijft ingelogd.' : 'De andere modus blijft zoals hij is, en je blijft ingelogd.',
      ],
      req: 'FR-SET-04 NFR-PRIV-04',
      actions: [
        { label: 'Wissen', run: () => { modes.forEach((mode) => { S.modes[mode] = emptyMode(); }); toast('Gegevens gewist'); T.focus = `set:erase:${modes.length === 2 ? 'both' : modes[0]}`; commit(); } },
        { label: 'Annuleren', run: () => { T.focus = T.dialogReturn; render(); } },
      ],
    });
  }

  function confirmSignOut() {
    openDialog({
      title: 'Afmelden?',
      body: [
        'Deze Apple TV vergeet je inlog. Hij blijft wel gekoppeld aan je NPO-account, tot je hem daar verwijdert bij je gekoppelde apparaten.',
        'Vastgezet, recent bekeken, later kijken en zoekgeschiedenis blijven op deze Apple TV staan.',
      ],
      req: 'FR-SET-03 FR-AUTH-04',
      actions: [
        { label: 'Afmelden', run: signOut },
        { label: 'Annuleren', run: () => { T.focus = 'set:signout'; render(); } },
      ],
    });
  }

  function signOut() {
    if (T.player) endPlayer();
    T.menu = null;
    T.dialog = null;
    S.signedIn = false;
    newSignin();
    T.stack = [{ screen: 'signin', params: {}, focus: null }];
    T.focus = null;
    commit();
  }

  // ---------------------------------------------------------------- sign-in behaviour

  function approveOnPhone(hasPlus) {
    if (!S.signin || S.signin.phase !== 'waiting') return;
    S.signin.phase = 'checking';
    render();
    setTimeout(() => {
      if (hasPlus) {
        S.signedIn = true;
        S.signin = null;
        save();
        goHome();
        return;
      }
      openDialog({
        title: 'NPO light werkt alleen met NPO Plus',
        body: [
          'Het account waarmee je bent ingelogd heeft geen NPO Plus.',
          'We melden het daarom weer af. Log in met een account dat NPO Plus heeft, of neem NPO Plus op npo.nl.',
        ],
        req: 'FR-AUTH-08',
        cancellable: false,
        actions: [{ label: 'OK, afmelden', run: () => { newSignin(); commit(); } }],
      });
    }, 1200);
  }

  function setSigninPhase(phase) {
    if (!S.signin) return;
    S.signin.phase = phase;
    T.focus = null;
    commit();
  }

  function signinTick() {
    if (top().screen !== 'signin' || !S.signin) return;
    if (S.signin.phase === 'waiting') {
      const remaining = Math.round((S.signin.expiresAt - Date.now()) / 1000);
      if (remaining <= 0) setSigninPhase('expired');
      else liveText('expiry', clock(remaining));
    }
  }

  // ---------------------------------------------------------------- render

  const tv = document.getElementById('tv');
  const screenEl = document.getElementById('tv-screen');

  function render() {
    handlers = new Map();
    menus = new Map();
    reqs = new Map();
    const current = top();
    let html = SCREENS[current.screen](current.params);
    html += menuLayer() + dialogLayer();
    if (T.toast) html += `<div class="toast" role="status">${esc(T.toast)}</div>`;
    screenEl.innerHTML = html;
    tv.classList.toggle('is-kids', isKids() && current.screen !== 'signin');
    drawQr();
    applyFocus();
    updatePanel();
  }

  function focusables() {
    const layers = screenEl.querySelectorAll('.layer');
    const scope = layers.length ? layers[layers.length - 1] : screenEl;
    return [...scope.querySelectorAll('[data-f]')];
  }

  function defaultFocus() {
    const screen = top().screen;
    const order = {
      home: ['[data-row="pinned"] [data-f]', '[data-row="recent"] [data-f]', '[data-f]'],
      search: ['[data-f="kb:a"]'],
      detail: ['[data-f="detail:play"]', '[data-f]'],
      settings: ['.chip.is-selected', '[data-f]'],
    }[screen] || ['[data-f]'];
    const scope = focusables();
    for (const selector of order) {
      const found = scope.find((el) => el.matches(selector));
      if (found) return found;
    }
    return scope[0] || null;
  }

  function applyFocus() {
    const scope = focusables();
    const byId = (id) => scope.find((el) => el.dataset.f === id);
    let el = T.focus ? byId(T.focus) : null;
    if (!el) {
      for (const id of T.fallback) {
        el = byId(id);
        if (el) break;
      }
    }
    if (!el) el = defaultFocus();
    screenEl.querySelectorAll('.is-focused').forEach((node) => node.classList.remove('is-focused'));
    T.focus = el ? el.dataset.f : null;
    if (el) {
      el.classList.add('is-focused');
      reveal(el);
      if (tvHasFocus()) el.focus({ preventScroll: true });
    }
  }

  function tvHasFocus() {
    const active = document.activeElement;
    return !active || active === document.body || tv.contains(active);
  }

  // Scroll rows and pages by hand, so the browser page itself never jumps.
  function reveal(el) {
    const scroller = el.closest('.scroller, .keyboard, .recent-search');
    if (scroller && scroller.scrollWidth > scroller.clientWidth) {
      const box = scroller.getBoundingClientRect();
      const rect = el.getBoundingClientRect();
      const scale = box.width / scroller.offsetWidth || 1;
      const leftGap = (rect.left - box.left) / scale;
      const rightGap = (rect.right - box.right) / scale;
      if (leftGap < 60) scroller.scrollLeft += leftGap - 60;
      else if (rightGap > -60) scroller.scrollLeft += rightGap + 60;
    }
    const page = el.closest('.vscroll');
    if (page) {
      const pageRect = page.getBoundingClientRect();
      const rect = el.getBoundingClientRect();
      const scale = pageRect.height / page.clientHeight || 1;
      const topGap = (rect.top - pageRect.top) / scale;
      const bottomGap = (rect.bottom - pageRect.bottom) / scale;
      const block = el.closest('.row, .season, .setting, .recent-search, .result') || el;
      const blockTop = (block.getBoundingClientRect().top - pageRect.top) / scale;
      if (topGap < 0 || blockTop < 0) page.scrollTop += Math.min(topGap, blockTop) - 30;
      else if (bottomGap > 0) page.scrollTop += bottomGap + 40;
    }
  }

  function setFocus(el) {
    T.focus = el.dataset.f;
    T.fallback = [];
    applyFocus();
    updatePanel();
  }

  // Spatial navigation: the nearest element in the pressed direction, with
  // sideways distance weighted so rows and columns behave as tvOS does.
  function move(direction) {
    const scope = focusables();
    const current = scope.find((el) => el.dataset.f === T.focus);
    if (!current) {
      const first = defaultFocus();
      if (first) setFocus(first);
      return;
    }
    const from = current.getBoundingClientRect();
    const cx = from.left + from.width / 2;
    const cy = from.top + from.height / 2;
    // The focused element is scaled up, so its centre is not exactly level
    // with its neighbours; a candidate has to be clearly in the direction.
    const minX = from.width * 0.3;
    const minY = from.height * 0.3;
    let best = null;
    let bestScore = Infinity;
    scope.forEach((el) => {
      if (el === current) return;
      const r = el.getBoundingClientRect();
      const x = r.left + r.width / 2;
      const y = r.top + r.height / 2;
      let primary;
      let secondary;
      if (direction === 'left' || direction === 'right') {
        primary = direction === 'right' ? r.left - from.right : from.left - r.right;
        if ((direction === 'right' ? x - cx : cx - x) <= minX) return;
        const overlap = Math.min(r.bottom, from.bottom) - Math.max(r.top, from.top);
        secondary = overlap > 0 ? 0 : Math.abs(y - cy);
      } else {
        primary = direction === 'down' ? r.top - from.bottom : from.top - r.bottom;
        if ((direction === 'down' ? y - cy : cy - y) <= minY) return;
        const overlap = Math.min(r.right, from.right) - Math.max(r.left, from.left);
        secondary = overlap > 0 ? Math.abs(x - cx) * 0.2 : Math.abs(x - cx);
      }
      const score = Math.max(0, primary) + secondary * 3;
      if (score < bestScore) { bestScore = score; best = el; }
    });
    if (best) setFocus(best);
  }

  function select() {
    const handler = handlers.get(T.focus);
    if (handler) handler();
  }

  function openMenu() {
    const builder = menus.get(T.focus);
    if (!builder) return false;
    const el = screenEl.querySelector(`[data-f="${CSS.escape(T.focus)}"]`);
    const title = el ? (el.querySelector('.tile-title, span') || el).textContent.trim() : '';
    T.menu = { title, items: builder(), returnFocus: T.focus, req: 'NFR-A11Y-01' };
    T.focus = 'menu:0';
    render();
    return true;
  }

  function closeMenu(restore) {
    const returnFocus = T.menu.returnFocus;
    T.menu = null;
    if (restore) { T.focus = returnFocus; render(); } else { T.focus = returnFocus; }
  }

  // ---------------------------------------------------------------- input

  function remote(action) {
    if (top().screen === 'player' && !T.menu && !T.dialog && playerKey(action)) return;
    switch (action) {
      case 'up': case 'down': case 'left': case 'right': move(action); break;
      case 'select': select(); break;
      case 'hold': if (!openMenu()) select(); break;
      case 'menu': back(); break;
      case 'playpause': {
        // On tvOS play/pause on a tile starts it; here it does the same as OK.
        select();
        break;
      }
      default: break;
    }
  }

  const KEYMAP = {
    ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right', Escape: 'menu',
  };

  let holdTimer = null;
  let held = false;

  // Keys belong to the television unless a control in the panel has focus:
  // form fields keep every key, panel buttons keep Enter and Space.
  function keyBelongsToTv(event) {
    const target = event.target;
    if (!(target instanceof HTMLElement) || !target.closest('.panel')) return true;
    if (target.closest('[data-remote]')) return true;
    if (target.matches('input, select, textarea')) return false;
    return !['Enter', ' '].includes(event.key);
  }

  document.addEventListener('keydown', (event) => {
    if (!keyBelongsToTv(event) || event.metaKey || event.ctrlKey || event.altKey) return;
    const onSearch = top().screen === 'search' && !T.menu && !T.dialog;
    if (KEYMAP[event.key]) {
      event.preventDefault();
      remote(KEYMAP[event.key]);
      return;
    }
    if (event.key === 'Enter') {
      event.preventDefault();
      if (event.repeat) return;
      held = false;
      holdTimer = setTimeout(() => { held = true; remote('hold'); }, HOLD_MS);
      return;
    }
    if (onSearch && event.key.length === 1 && /[\p{L}\p{N} ]/u.test(event.key)) {
      event.preventDefault();
      typeText(event.key.toLowerCase());
      return;
    }
    if (onSearch && event.key === 'Backspace') {
      event.preventDefault();
      deleteChar();
      return;
    }
    if (event.key === 'Backspace') { event.preventDefault(); remote('menu'); return; }
    if (event.key === ' ' || event.key === 'p' || event.key === 'P') {
      event.preventDefault();
      remote('playpause');
    }
  });

  document.addEventListener('keyup', (event) => {
    if (event.key !== 'Enter' || holdTimer === null) return;
    clearTimeout(holdTimer);
    if (!held && holdTimer !== null) remote('select');
    holdTimer = null;
    held = false;
  });

  // Pointer: a click on the screen focuses and selects; a long press or a
  // right click opens the context menu, as a long press on OK does on tvOS.
  let pressTimer = null;
  let pressFired = false;

  screenEl.addEventListener('pointerdown', (event) => {
    const el = event.target.closest('[data-f]');
    if (!el || !focusables().includes(el)) return;
    pressFired = false;
    clearTimeout(pressTimer);
    pressTimer = setTimeout(() => {
      pressFired = true;
      setFocus(el);
      remote('hold');
    }, HOLD_MS);
  });

  ['pointerup', 'pointerleave', 'pointercancel'].forEach((type) => {
    screenEl.addEventListener(type, () => clearTimeout(pressTimer));
  });

  screenEl.addEventListener('click', (event) => {
    const el = event.target.closest('[data-f]');
    if (!el || pressFired) { pressFired = false; return; }
    if (!focusables().includes(el)) return;
    setFocus(el);
    remote('select');
  });

  screenEl.addEventListener('contextmenu', (event) => {
    const el = event.target.closest('[data-f]');
    if (!el || !focusables().includes(el)) return;
    event.preventDefault();
    clearTimeout(pressTimer);
    if (pressFired) return;
    setFocus(el);
    remote('hold');
  });

  // The on-screen remote.
  document.querySelectorAll('[data-remote]').forEach((button) => {
    const action = button.dataset.remote;
    if (action === 'select') {
      let timer = null;
      let fired = false;
      button.addEventListener('pointerdown', () => {
        fired = false;
        timer = setTimeout(() => { fired = true; remote('hold'); }, HOLD_MS);
      });
      button.addEventListener('pointerup', () => { clearTimeout(timer); if (!fired) remote('select'); });
      button.addEventListener('pointerleave', () => clearTimeout(timer));
      button.addEventListener('keydown', (event) => { if (event.key === ' ') { event.preventDefault(); remote('select'); } });
    } else {
      button.addEventListener('click', () => remote(action));
    }
  });

  // ---------------------------------------------------------------- panel

  const panel = {
    reqList: document.getElementById('req-list'),
    reqFocus: document.getElementById('req-focus'),
    screenName: document.getElementById('screen-name'),
    signin: document.getElementById('scenario-signin'),
    player: document.getElementById('scenario-player'),
    offline: document.getElementById('opt-offline'),
    slow: document.getElementById('opt-slow'),
    fails: document.getElementById('opt-fails'),
    speed: document.getElementById('opt-speed'),
    date: document.getElementById('sim-date'),
    modeName: document.getElementById('mode-name'),
  };

  const SCREEN_NAMES = {
    signin: 'Sign-in', home: 'Home', detail: 'Detail page', search: 'Search', player: 'Player', settings: 'Settings',
  };

  function reqItem(id) {
    const req = REQS[id];
    if (!req) return `<li><code>${esc(id)}</code></li>`;
    const anchor = `${id} — ${req.title}`.toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, '').replace(/\s/g, '-');
    return `<li><a href="${REPO}${req.file}#${anchor}" target="_blank" rel="noopener"><code>${esc(id)}</code></a>
      <span class="req-title">${esc(req.title)}</span> <span class="req-status status-${req.status.toLowerCase()}">${esc(req.status)}</span></li>`;
  }

  function updatePanel() {
    const screen = top().screen;
    panel.screenName.textContent = SCREEN_NAMES[screen];
    panel.modeName.textContent = screen === 'signin' ? 'signed out' : (isKids() ? 'kids mode' : 'normal mode');
    const focusIds = (reqs.get(T.focus) || '').split(/\s+/).filter(Boolean);
    const screenIds = screenReqs.split(/\s+/).filter((id) => id && !focusIds.includes(id));
    panel.reqFocus.innerHTML = focusIds.length ? focusIds.map(reqItem).join('') : '<li class="muted">Nothing focusable here.</li>';
    panel.reqList.innerHTML = screenIds.map(reqItem).join('');
    panel.signin.hidden = screen !== 'signin';
    panel.player.hidden = screen !== 'player';
    panel.offline.checked = S.scenario.offline;
    panel.slow.checked = S.scenario.slow;
    panel.fails.checked = S.scenario.playbackFails;
    panel.speed.value = String(S.scenario.speed);
    panel.date.textContent = new Date(now()).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
  }

  // A panel button hands the keyboard back to the television once clicked,
  // so the next Enter is OK on the remote rather than a second click.
  function bind(id, handler) {
    const el = document.getElementById(id);
    if (!el) return;
    if (el.tagName === 'BUTTON') {
      el.addEventListener('click', (event) => {
        handler(event);
        if (event.detail > 0) el.blur();
      });
    } else {
      el.addEventListener('change', handler);
    }
  }

  bind('sc-approve', () => approveOnPhone(true));
  bind('sc-approve-free', () => approveOnPhone(false));
  bind('sc-expire', () => setSigninPhase('expired'));
  bind('sc-deny', () => setSigninPhase('denied'));
  bind('sc-neterror', () => setSigninPhase('error'));
  bind('sc-near-end', () => {
    if (!T.player || T.player.overlay) return;
    T.player.pos = Math.max(T.player.pos, threshold(T.player.duration) - 20);
    T.player.playing = true;
    render();
  });
  bind('sc-end', () => {
    if (!T.player || T.player.overlay) return;
    T.player.pos = T.player.duration - 0.5;
    T.player.playing = true;
    render();
  });
  bind('sc-still', () => {
    if (!T.player || T.player.overlay) return;
    T.player.still = isKids() ? S.settings.kidsStill : S.settings.normalStill;
    T.player.playing = true;
  });
  bind('opt-offline', (event) => { S.scenario.offline = event.target.checked; commit(); });
  bind('opt-slow', (event) => { S.scenario.slow = event.target.checked; commit(); });
  bind('opt-fails', (event) => { S.scenario.playbackFails = event.target.checked; commit(); });
  bind('opt-speed', (event) => { S.scenario.speed = Number(event.target.value); commit(); });
  bind('sc-day', () => { S.clockOffset += DAY; toast('Een dag later'); commit(); });
  bind('sc-signout', () => { if (top().screen !== 'signin') signOut(); });
  bind('sc-reset', () => { S = seededState(); resetTransient(); goHome(); save(); });
  bind('sc-empty', () => { S = emptyState(); resetTransient(); goHome(); save(); });

  function resetTransient() {
    if (T.tick) clearInterval(T.tick);
    Object.assign(T, { menu: null, dialog: null, player: null, tick: null, focus: null, fallback: [] });
  }

  // ---------------------------------------------------------------- QR placeholder

  function drawQr() {
    const canvas = screenEl.querySelector('canvas[data-qr]');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const n = canvas.width;
    let seed = Number(canvas.dataset.qr) || 1;
    const random = () => {
      seed = (seed * 1103515245 + 12345) % 2147483648;
      return seed / 2147483648;
    };
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, n, n);
    ctx.fillStyle = '#000';
    const quiet = 2;
    for (let y = quiet; y < n - quiet; y += 1) {
      for (let x = quiet; x < n - quiet; x += 1) {
        if (random() > 0.52) ctx.fillRect(x, y, 1, 1);
      }
    }
    const finder = (fx, fy) => {
      ctx.fillStyle = '#000'; ctx.fillRect(fx, fy, 7, 7);
      ctx.fillStyle = '#fff'; ctx.fillRect(fx + 1, fy + 1, 5, 5);
      ctx.fillStyle = '#000'; ctx.fillRect(fx + 2, fy + 2, 3, 3);
      ctx.fillStyle = '#fff';
      ctx.fillRect(fx - 1 < quiet ? fx + 7 : fx - 1, fy, 1, 8);
    };
    finder(quiet, quiet);
    finder(n - quiet - 7, quiet);
    finder(quiet, n - quiet - 7);
  }

  // ---------------------------------------------------------------- scale

  // The screen is laid out at 1920x1080, like tvOS, and scaled to fit.
  function fit() {
    const scale = tv.clientWidth / 1920;
    screenEl.style.transform = `scale(${scale})`;
  }

  if (window.ResizeObserver) new ResizeObserver(fit).observe(tv);
  window.addEventListener('resize', fit);

  // ---------------------------------------------------------------- start

  S = load() || seededState();
  if (S.signedIn) {
    T.stack = [{ screen: 'home', params: {}, focus: null }];
  } else {
    if (!S.signin || S.signin.phase === 'checking') newSignin();
    T.stack = [{ screen: 'signin', params: {}, focus: null }];
  }
  setInterval(signinTick, 1000);
  fit();
  render();
})();
