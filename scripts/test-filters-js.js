// Testuje Sources/MyGramCore/Resources/filters.js nad falešným DOM (jsdom) s configem z filters.json.
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { JSDOM } = require('jsdom');

const res = path.join(__dirname, '..', 'Sources', 'MyGramCore', 'Resources');
const config = JSON.parse(fs.readFileSync(path.join(res, 'filters.json'), 'utf8'));
const script = fs.readFileSync(path.join(res, 'filters.js'), 'utf8');

const scriptConfig = {
  hide: config.groups.filter(g => !g.optional).flatMap(g => g.hide),
  suggestedTexts: config.suggestedTexts,
  health: config.health,
};

const sleep = ms => new Promise(r => setTimeout(r, ms));

function load(url, body) {
  const messages = [];
  const dom = new JSDOM(`<!doctype html><html><body>${body}</body></html>`, {
    url, runScripts: 'outside-only', pretendToBeVisual: true,
  });
  const w = dom.window;
  w.webkit = { messageHandlers: { route: { postMessage: m => messages.push(m) } } };
  w.__mygramConfig = scriptConfig;
  w.eval(script);
  return { w, doc: w.document, messages };
}
const hidden = el => el.hasAttribute('data-mygram-hidden');

const NAV = `<ul><li id="home"><a href="/">Home</a></li>
  <li id="reels"><a href="/reels/">Reels</a></li>
  <li id="explore"><a href="/explore/">Explore</a></li>
  <li id="dm"><a href="/direct/inbox/">DM</a></li></ul>`;
const FEED = `<main>
  <article id="normal"><a href="/p/abc/">1h</a><span>Hello</span></article>
  <article id="reel"><a href="/someone/reel/xyz/">2h</a></article>
  <article id="sugg"><span>Navrhováno pro vás</span></article>
</main>`;

(async () => {
  // Navigace + feed
  let { doc } = load('https://www.instagram.com/', NAV + FEED);
  assert(hidden(doc.getElementById('reels')), 'tab Reels skryt (ancestor li)');
  assert(hidden(doc.getElementById('explore')), 'tab Explore skryt');
  assert(!hidden(doc.getElementById('home')) && !hidden(doc.getElementById('dm')), 'Home a DM zůstávají');
  assert(hidden(doc.getElementById('reel')), 'Reel ve feedu skryt');
  assert(hidden(doc.getElementById('sugg')), 'navržený příspěvek skryt');
  assert(!hidden(doc.getElementById('normal')), 'běžný příspěvek zůstává');

  // Stránka jednoho Reelu z DM se nesmí skrýt, ani když je to <article> s odkazem na sebe.
  ({ doc } = load('https://www.instagram.com/reel/xyz/', '<article id="single"><a href="/reel/xyz/">now</a></article>'));
  assert(!hidden(doc.getElementById('single')), 'otevřený Reel zůstává viditelný');
  assert(doc.documentElement.hasAttribute('data-mygram-content'), 'html má značku stránky obsahu');

  // Dynamicky donačtený obsah (MutationObserver)
  let ctx = load('https://www.instagram.com/', NAV + '<main id="m"></main>');
  const late = ctx.doc.createElement('article');
  late.id = 'late';
  late.innerHTML = '<a href="/u/reel/q/">x</a>';
  ctx.doc.getElementById('m').appendChild(late);
  await sleep(150);
  assert(hidden(late), 'později přidaný Reel skryt');

  // Hook na History API
  ctx = load('https://www.instagram.com/direct/inbox/', '<div></div>');
  ctx.w.history.pushState({}, '', '/reel/AAA/');
  assert.strictEqual(ctx.messages.length, 1);
  assert.strictEqual(ctx.messages[0].to, 'https://www.instagram.com/reel/AAA/');
  assert.strictEqual(ctx.messages[0].from, 'https://www.instagram.com/direct/inbox/');
  assert.strictEqual(ctx.messages[0].userInitiated, false, 'bez kliknutí = neuživatelské');
  ctx.doc.body.firstChild.dispatchEvent(new ctx.w.Event('click', { bubbles: true }));
  ctx.w.history.pushState({}, '', '/reel/BBB/');
  assert.strictEqual(ctx.messages[1].userInitiated, true, 'po kliknutí = uživatelské');
  assert(ctx.doc.documentElement.hasAttribute('data-mygram-content'));

  // Health
  ctx = load('https://www.instagram.com/', NAV);
  ctx.doc.cookie = 'ds_user_id=1';
  const h = ctx.w.__mygramHealth();
  assert.strictEqual(h.loggedIn, true);
  assert.strictEqual(h.path, '/');
  assert.strictEqual(h.counts.reelsTab, 1);
  ctx = load('https://www.instagram.com/', '<a href="/jinak/">x</a>');
  assert.strictEqual(ctx.w.__mygramHealth().counts.reelsTab, 0, 'rozbitý selektor = 0');

  console.log('filters.js: OK');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
