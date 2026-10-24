// Vrstva 3: dynamický obsah + hook na History API.
// Konfiguraci (window.__mygramConfig) vkládá Swift před tento skript z filters.json.
(function () {
  'use strict';
  if (window.__mygramInstalled) return;
  window.__mygramInstalled = true;

  var cfg = window.__mygramConfig || {};
  var hideEntries = cfg.hide || [];
  var phrases = (cfg.suggestedTexts || []).map(function (t) { return t.toLowerCase(); });
  var healthChecks = cfg.health || [];
  var HIDDEN = 'data-mygram-hidden';
  var USER_CLICK_WINDOW_MS = 800;

  function hide(el) {
    if (!el || el.hasAttribute(HIDDEN)) return;
    el.setAttribute(HIDDEN, '1');
    el.style.display = 'none';
  }

  // Stránka jednoho příspěvku/Reelu (/reel/<id>/, /p/<id>/, /<user>/reel/<id>/): pravidla
  // "Reel ve feedu" se tu nesmí uplatnit, jinak by se skryl právě otevřený Reel.
  var CONTENT_PATH = /^\/(?:[^\/]+\/)?(?:reel|reels|p|tv)\/[^\/]+/;
  function onContentPage() { return CONTENT_PATH.test(location.pathname); }
  function markPage() {
    if (onContentPage()) document.documentElement.setAttribute('data-mygram-content', '1');
    else document.documentElement.removeAttribute('data-mygram-content');
  }
  markPage();

  function applySelectors() {
    var content = onContentPage();
    hideEntries.forEach(function (entry) {
      if (content && entry.skipOnContentPages) return;
      var nodes;
      try { nodes = document.querySelectorAll(entry.selector); } catch (e) { return; }
      for (var i = 0; i < nodes.length; i++) {
        var target = nodes[i];
        if (entry.ancestor) {
          try { target = nodes[i].closest(entry.ancestor); } catch (e) { target = null; }
        }
        hide(target);
      }
    });
  }

  // "Navrhováno pro vás" apod. nejde chytit podle href, hledáme krátké listové texty.
  function applySuggestedTexts() {
    if (!phrases.length) return;
    var nodes = document.querySelectorAll('article span, article h2, article h3, h2, h3, h4');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (el.children.length !== 0) continue;
      var text = el.textContent;
      if (!text || text.length > 60) continue;
      if (phrases.indexOf(text.trim().toLowerCase()) === -1) continue;
      hide(el.closest('article') || el.closest('section'));
    }
  }

  function scan() {
    applySelectors();
    applySuggestedTexts();
  }

  // Throttle ~50 ms: při souvislém scrollu (stále nové mutace) se sken stejně provede.
  var scheduled = false;
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(function () { scheduled = false; scan(); }, 50);
  }

  function start() {
    scan();
    new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true });
  }
  if (document.body) start();
  else document.addEventListener('DOMContentLoaded', start);

  // --- History API: Instagram je SPA, WKNavigationDelegate přechody nevidí. ---
  var lastHref = location.href;
  var lastClickAt = 0;
  document.addEventListener('click', function () { lastClickAt = Date.now(); }, true);

  function post(message) {
    try { window.webkit.messageHandlers.route.postMessage(message); } catch (e) { /* mimo WKWebView */ }
  }

  function report() {
    var to = location.href;
    if (to === lastHref) return;
    var from = lastHref;
    lastHref = to;
    markPage();
    scan();
    post({ from: from, to: to, userInitiated: Date.now() - lastClickAt < USER_CLICK_WINDOW_MS });
  }

  ['pushState', 'replaceState'].forEach(function (name) {
    var original = history[name];
    history[name] = function () {
      var result = original.apply(this, arguments);
      report();
      return result;
    };
  });
  window.addEventListener('popstate', report);

  // --- FilterHealth: kolik prvků každý "kotevní" selektor našel. ---
  window.__mygramHealth = function () {
    var counts = {};
    healthChecks.forEach(function (h) {
      try { counts[h.name] = document.querySelectorAll(h.selector).length; }
      catch (e) { counts[h.name] = -1; }
    });
    return {
      loggedIn: /(^|;\s*)ds_user_id=/.test(document.cookie),
      path: location.pathname,
      counts: counts
    };
  };
})();
