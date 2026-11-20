// ==UserScript==
// @name         西农教务助手 · 网页版桥接 (NWAFU Web Bridge)
// @namespace    cn.edu.nwafu.bksxk.webbridge
// @version      1.5.1
// @description  让西农教务助手网页版访问学校接口：选课、站内统一身份认证登录与自动重登，以及课表、成绩、考试、空教室、学业进度、消息与图书馆。仅在校园网内或可访问学校服务的网络下有效。
// @author       nwafu-bksxk
// @match        https://mjy.js.org/nwafu-bksxk/*
// @match        http://localhost:*/*
// @match        http://127.0.0.1:*/*
// @match        https://majianyu2007.github.io/nwafu-bksxk/*
// @connect      bksxk.nwafu.edu.cn
// @connect      ehall.nwafu.edu.cn
// @connect      newehall.nwafu.edu.cn
// @connect      booking-lib.nwafu.edu.cn
// @connect      authserver.nwafu.edu.cn
// @grant        GM_xmlhttpRequest
// @grant        unsafeWindow
// @run-at       document-start
// @downloadURL  https://mjy.js.org/nwafu-bksxk/bksxk-web-bridge.user.js
// @updateURL    https://mjy.js.org/nwafu-bksxk/bksxk-web-bridge.user.js
// ==/UserScript==

//
// HOW IT WORKS
// ------------
// The Flutter web app (served from GitHub Pages / localhost) calls NWAFU hosts
// (bksxk, ehall, newehall, booking-lib, authserver) via XMLHttpRequest.
// Browsers block those cross-origin requests (the school servers send no CORS
// headers) and forbid setting Cookie / Origin / Referer from page JS.
//
// This script replaces window.XMLHttpRequest only for the allowlisted NWAFU
// hosts and endpoints. Selection (bksxk) uses isolated in-memory cookies with
// fresh-node route pinning; academic/CAS hosts reuse the browser's session via
// GM_xmlhttpRequest while stripping Set-Cookie and blocking unallowlisted paths.
// Academic access is restricted to the app's deployment and local development;
// do not restore wildcard hosting @match rules: they expose browser sessions.
//
(function () {
  'use strict';

  var BRIDGE_VERSION = '1.5.1';
  var API_HOST = 'bksxk.nwafu.edu.cn';
  var EDU_HOST = 'ehall.nwafu.edu.cn';
  var PORTAL_HOST = 'newehall.nwafu.edu.cn';
  var LIBRARY_HOST = 'booking-lib.nwafu.edu.cn';
  var AUTH_HOST = 'authserver.nwafu.edu.cn';
  var win = typeof unsafeWindow !== 'undefined' ? unsafeWindow : window;
  var NativeXHR = win.XMLHttpRequest;

  // Signal to the app that the bridge is present (used to skip the install prompt).
  try {
    win.__bksxkBridgeReady = true;
    win.__bksxkBridgeVersion = BRIDGE_VERSION;
    win.__bksxkEduSessionBridgeReady = true;
    win.__bksxkCasLoginBridgeReady = true;
  } catch (e) { /* ignore */ }

  // Browser extension sandboxes can hide JavaScript globals from page code.
  // A DOM attribute is visible from both worlds and provides a reliable
  // fallback for the Flutter app's installation check.
  function markBridgeReadyInDom() {
    try {
      if (win.document && win.document.documentElement) {
        win.document.documentElement.setAttribute('data-bksxk-bridge-ready', 'true');
        win.document.documentElement.setAttribute('data-bksxk-bridge-version', BRIDGE_VERSION);
        win.document.documentElement.setAttribute('data-bksxk-edu-session-bridge-ready', 'true');
        win.document.documentElement.setAttribute('data-bksxk-cas-login-bridge-ready', 'true');
      }
    } catch (e) { /* ignore */ }
  }

  markBridgeReadyInDom();
  if (win.document && win.document.readyState === 'loading') {
    win.document.addEventListener('DOMContentLoaded', markBridgeReadyInDom, { once: true });
  }

  function isApiUrl(url) {
    try {
      // Absolute URL to an allowlisted campus host, or a relative URL that resolves to one.
      var u = new URL(url, win.location.href);
      return u.hostname === API_HOST || u.hostname === EDU_HOST ||
        u.hostname === PORTAL_HOST || u.hostname === LIBRARY_HOST ||
        u.hostname === AUTH_HOST;
    } catch (e) {
      return false;
    }
  }

  function isHttpsCampus(u) {
    return u.protocol === 'https:' &&
      (!u.port || u.port === '443') && !u.username && !u.password;
  }

  function isEduUrl(u) {
    return isHttpsCampus(u) && u.hostname === EDU_HOST &&
      (u.pathname.indexOf('/jwapp/') === 0 ||
        u.pathname === '/login' ||
        u.pathname.indexOf('/execCardMethod/') === 0);
  }

  // Explicit contract for AuthServer (CAS login/MFA/logout), EMAP, portal (newehall)
  // and library (booking-lib).
  function isEduRead(method, u) {
    if (!isHttpsCampus(u)) return false;
    var m = method.toUpperCase();
    var path = u.pathname;
    if (u.hostname === AUTH_HOST) {
      if (m === 'GET') {
        return path === '/authserver/login' ||
          path === '/authserver/logout' ||
          path === '/authserver/checkNeedCaptcha.htl' ||
          path === '/authserver/bfp/info' ||
          path === '/authserver/reAuthCheck/reAuthLoginView.do';
      }
      if (m === 'POST') {
        return path === '/authserver/login' ||
          path === '/authserver/reAuthCheck/changeReAuthType.do' ||
          path === '/authserver/dynamicCode/getDynamicCodeByReauth.do' ||
          path === '/authserver/reAuthCheck/reAuthSubmit.do';
      }
      return false;
    }
    if (u.hostname === PORTAL_HOST) {
      if (m === 'GET') {
        return path === '/login' ||
          path === '/jsonp/ywtb/getUnreadMessageCount' ||
          path === '/jsonp/getTagsMessages';
      }
      if (m === 'POST') {
        return path === '/taskcenterapp/sys/taskCenter/taskNew/getTaskTodoAndDoneCount.do' ||
          path === '/taskcenterapp/sys/taskCenter/taskNew/getTaskRestful.do';
      }
      return false;
    }
    if (u.hostname === LIBRARY_HOST) {
      if (m === 'GET') {
        return path === '/api/cas/cas' ||
          /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(path);
      }
      if (m === 'POST') {
        return /^\/api\/(cas\/user|Member\/(my|seat|seminar)|Seat\/(date|seat|confirm)|seat\/(map|xuzuoconfirm)|Space\/(signin|leave|checkout|cancel)|space\/seminarCancel|Seminar\/(date|detail|seminar|group|submit|roomConfirm|roomCancel)|Room\/detail)$/.test(path) ||
          path === '/reserve/index/list' ||
          path === '/reserve/index/confirm' ||
          path === '/reserve/seminar/signout';
      }
      return false;
    }
    if (!isEduUrl(u)) return false;
    if (m === 'GET') {
      return path === '/login' ||
        /^\/jwapp\/sys\/(wdkbby|cjcx|studentWdksapApp|kxjas|xywccx)\/\*default\/index\.do$/.test(path) ||
        /^\/jwapp\/sys\/funauthapp\/api\/getAppConfig\/(wdkbby-5959167891382285|cjcx-4768574631264620|studentWdksapApp-4768687067472349|kxjas-4768402106681759|xywccx-4980269146247992)\.do$/.test(path);
    }
    if (m !== 'POST' || u.search) return false;
    return /^\/execCardMethod\/[\w-]+\/[\w-]+$/.test(path) ||
      /^\/jwapp\/sys\/wdkbby\/modules\/(jshkcb\/(dqxnxq|xnxqcx|jc|dqzc)|xskcb\/(cxxljc|cxxszhxqkb|xswpkc|xsdkkc))\.do$/.test(path) ||
      /^\/jwapp\/sys\/cjcx\/modules\/cjcx\/(xscjcx|cxxscjpm)\.do$/.test(path) ||
      path === '/jwapp/sys/studentWdksapApp/WdksapController/cxxsksap.do' ||
      path === '/jwapp/sys/studentWdksapApp/modules/wdksap/cxxsjbxx.do' ||
      path === '/jwapp/sys/kxjas/modules/kxjscx/cxkxjs.do' ||
      /^\/jwapp\/sys\/xywccx\/modules\/xywccx\/(grpyfacx|cxdqxnxq|cxscfa|cxscfakz|cxfakzyxxfgj)\.do$/.test(path);
  }

  function isSafeEduResponse(url) {
    try {
      var u = new URL(url);
      return isHttpsCampus(u) &&
        (u.hostname === EDU_HOST || u.hostname === PORTAL_HOST ||
          u.hostname === LIBRARY_HOST || u.hostname === AUTH_HOST);
    } catch (e) { return false; }
  }

  // A minimal XMLHttpRequest-compatible shim backed by GM_xmlhttpRequest.
  // Implements the surface Dio's browser adapter uses.
  function BridgedXHR() {
    this._listeners = {};
    this._headers = {};
    this._method = 'GET';
    this._url = '';
    this._async = true;
    this.readyState = 0;
    this.status = 0;
    this.statusText = '';
    this.response = '';
    this.responseText = '';
    this.responseType = '';
    this.responseURL = '';
    this.timeout = 0;
    this.withCredentials = false;
    this.onreadystatechange = null;
    this.onload = null;
    this.onerror = null;
    this.ontimeout = null;
    this.onabort = null;
    this.onprogress = null;
    this.onloadend = null;
    this._responseHeaders = '';
    this._aborted = false;
    var noop = function () {};
    this.upload = { addEventListener: noop, removeEventListener: noop };
  }

  BridgedXHR.prototype.open = function (method, url, async) {
    this._method = method;
    this._url = url;
    this._async = async !== false;
    this._headers = {};
    this._aborted = false;
    this.readyState = 1;
    this._emitReadyState();
  };

  BridgedXHR.prototype.setRequestHeader = function (k, v) {
    this._headers[k] = v;
  };

  BridgedXHR.prototype.getAllResponseHeaders = function () {
    return this._responseHeaders || '';
  };

  BridgedXHR.prototype.getResponseHeader = function (name) {
    if (!name || !this._responseHeaders) return null;
    var target = String(name).toLowerCase();
    var lines = this._responseHeaders.split(/\r?\n/);
    var values = [];
    for (var i = 0; i < lines.length; i++) {
      var idx = lines[i].indexOf(':');
      if (idx <= 0) continue;
      if (lines[i].slice(0, idx).trim().toLowerCase() === target) {
        values.push(lines[i].slice(idx + 1).trim());
      }
    }
    return values.length ? values.join(', ') : null;
  };

  BridgedXHR.prototype.addEventListener = function (type, fn, opts) {
    if (typeof fn !== 'function') return;
    var list = (this._listeners[type] = this._listeners[type] || []);
    for (var i = 0; i < list.length; i++) {
      if (list[i].fn === fn) return;
    }
    list.push({ fn: fn, once: !!(opts && typeof opts === 'object' && opts.once) });
  };

  BridgedXHR.prototype.removeEventListener = function (type, fn) {
    var l = this._listeners[type];
    if (!l) return;
    for (var i = 0; i < l.length; i++) {
      if (l[i].fn === fn) {
        l.splice(i, 1);
        return;
      }
    }
  };

  BridgedXHR.prototype._emit = function (type) {
    var evt = { type: type, target: this, currentTarget: this };
    var direct = this['on' + type];
    if (typeof direct === 'function') direct.call(this, evt);
    var l = this._listeners[type];
    if (!l || !l.length) return;
    var snapshot = l.slice();
    for (var i = 0; i < snapshot.length; i++) {
      if (snapshot[i].once) this.removeEventListener(type, snapshot[i].fn);
      snapshot[i].fn.call(this, evt);
    }
  };

  BridgedXHR.prototype._emitReadyState = function () {
    this._emit('readystatechange');
  };

  BridgedXHR.prototype.abort = function () {
    this._aborted = true;
    if (this._gm && typeof this._gm.abort === 'function') {
      try { this._gm.abort(); } catch (e) { /* ignore */ }
    }
    this.readyState = 0;
    this._emit('abort');
  };

  // Dio's browser adapter sends every body as a Uint8Array. GM_xmlhttpRequest
  // only takes a string (or Blob/FormData); handed a typed array it sends the
  // text "[object Uint8Array]", so every POST (course queries, selection)
  // failed while GETs (login, courseResult) worked. Form bodies are UTF-8
  // text, so decode them; anything else goes as a Blob.
  function normaliseBody(body, headers) {
    if (body == null || typeof body === 'string') return body;
    var bytes = null;
    if (body instanceof ArrayBuffer) bytes = new Uint8Array(body);
    else if (ArrayBuffer.isView(body)) bytes = new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
    if (bytes === null) return body; // Blob / FormData / URLSearchParams pass through
    var type = '';
    for (var k in headers) if (k.toLowerCase() === 'content-type') type = String(headers[k]).toLowerCase();
    var textual = type === '' || type.indexOf('application/x-www-form-urlencoded') >= 0 ||
      type.indexOf('application/json') >= 0 || type.indexOf('text/') >= 0;
    if (textual) {
      try { return new TextDecoder('utf-8').decode(bytes); } catch (e) { /* fall through */ }
    }
    return new Blob([bytes], { type: type || 'application/octet-stream' });
  }

  // Isolated cookie jar + fresh-node pinning for bksxk.nwafu.edu.cn ONLY.
  // NWAFU's bksxk cluster fronts multiple Tomcat nodes behind nginx sticky
  // `route` cookies; if the browser's cookie jar is stuck on a stale backend
  // node, every login gets frozen historical rounds. Using `anonymous: true`
  // with an in-memory cookie map isolates bksxk from stale browser cookies and
  // pins a verified-fresh `route` (highest sysparam.do `initTimestamp`).
  // Academic hosts (ehall/newehall/booking-lib/authserver) still use
  // `anonymous: false` to carry the browser's official CAS session.
  var bksxkCookies = {};
  var bksxkHighestInitTs = 0;
  var bksxkRouteReady = false;
  var bksxkProbeCallbacks = null;

  function extractRouteFromHeaders(rawHeaders) {
    if (!rawHeaders) return null;
    var lines = String(rawHeaders).split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
      var m = /^set-cookie:\s*route=([^;\s]+)/i.exec(lines[i]);
      if (m && m[1]) return m[1].trim();
    }
    return null;
  }

  function mergeBksxkSetCookies(rawHeaders) {
    if (!rawHeaders) return;
    var lines = String(rawHeaders).split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
      var m = /^set-cookie:\s*([^=\s]+)=([^;\r\n]*)/i.exec(lines[i]);
      if (!m) continue;
      var name = m[1].trim();
      var val = m[2].trim();
      if (!val) continue;
      if (/^route$/i.test(name)) bksxkCookies.route = val;
      else if (/^jsessionid$/i.test(name)) bksxkCookies.JSESSIONID = val;
    }
  }

  function serializeBksxkCookies() {
    var parts = [];
    for (var k in bksxkCookies) {
      if (Object.prototype.hasOwnProperty.call(bksxkCookies, k) && bksxkCookies[k]) {
        parts.push(k + '=' + bksxkCookies[k]);
      }
    }
    return parts.join('; ');
  }

  function parseInitTsFromBody(text) {
    if (!text) return 0;
    try {
      var j = JSON.parse(text);
      var raw = j && j.data ? j.data.initTimestamp : null;
      var n = parseInt(raw, 10);
      return isNaN(n) || n <= 0 ? 0 : n;
    } catch (e) {
      return 0;
    }
  }

  function isBksxkRouteSensitivePath(pathname) {
    return /\/(vcode\.do|check\/login\.do|student\/[^/]+\.do|elective\/batch\.do|publicinfo\/sysparam\.do)$/.test(pathname || '');
  }

  function ensureFreshBksxkRoute(force, done) {
    if (!force && bksxkRouteReady) {
      done();
      return;
    }
    if (bksxkProbeCallbacks !== null) {
      bksxkProbeCallbacks.push(done);
      return;
    }
    bksxkProbeCallbacks = [done];
    var excludedRoute = force ? (bksxkCookies.route || null) : null;
    var pending = 3;
    var probes = [];

    function finishOne(probe) {
      if (probe) probes.push(probe);
      pending -= 1;
      if (pending > 0) return;
      for (var j = 0; j < probes.length; j++) {
        if (probes[j].ts > bksxkHighestInitTs) bksxkHighestInitTs = probes[j].ts;
      }
      var best = null;
      for (var k = 0; k < probes.length; k++) {
        var p = probes[k];
        if (!p.route) continue;
        if (!best || p.ts > best.ts ||
            (p.ts === best.ts && excludedRoute && best.route === excludedRoute && p.route !== excludedRoute)) {
          best = p;
        }
      }
      if (best && best.route && (bksxkHighestInitTs === 0 || best.ts >= bksxkHighestInitTs)) {
        bksxkCookies.route = best.route;
      }
      // Only lock route-ready once at least one probe answered; if every probe
      // failed (e.g. off-campus or momentary blip), allow the next request to
      // re-probe rather than disabling pinning for the whole session.
      if (best && best.route) {
        bksxkRouteReady = true;
      }
      var q = bksxkProbeCallbacks || [];
      bksxkProbeCallbacks = null;
      for (var m = 0; m < q.length; m++) {
        try { q[m](); } catch (e) { /* ignore */ }
      }
    }

    var base = Date.now();
    for (var i = 0; i < 3; i++) {
      (function (idx) {
        var settled = false;
        function doneOne(probe) {
          if (settled) return;
          settled = true;
          finishOne(probe);
        }
        try {
          GM_xmlhttpRequest({
            method: 'GET',
            url: 'https://' + API_HOST + '/xsxkapp/sys/xsxkapp/publicinfo/sysparam.do?timestamp=' + (base + idx),
            headers: { 'Cache-Control': 'no-cache', 'X-Requested-With': 'XMLHttpRequest' },
            timeout: 5000,
            anonymous: true,
            onload: function (resp) {
              doneOne({
                route: extractRouteFromHeaders(resp.responseHeaders || ''),
                ts: parseInitTsFromBody(resp.responseText || ''),
              });
            },
            onerror: function () { doneOne(null); },
            ontimeout: function () { doneOne(null); },
            onabort: function () { doneOne(null); },
          });
        } catch (e) {
          doneOne(null);
        }
      })(i);
    }
  }

  BridgedXHR.prototype.send = function (body) {
    var self = this;
    var url = new URL(this._url, win.location.href);
    var academic = url.hostname !== API_HOST;
    if (academic && !isEduRead(this._method, url)) {
      this.status = 0;
      this.readyState = 4;
      this._emitReadyState();
      this._emit('error');
      this._emit('loadend');
      return;
    }

    var refreshRoute = false;
    var sendHeaders = {};
    for (var hk in this._headers) {
      if (!Object.prototype.hasOwnProperty.call(this._headers, hk)) continue;
      var lowerKey = hk.toLowerCase();
      if (!academic && lowerKey === 'x-bksxk-refresh-route') {
        refreshRoute = true;
        continue;
      }
      if (!academic && lowerKey === 'cookie') continue;
      if (url.hostname === AUTH_HOST && (lowerKey === 'origin' || lowerKey === 'referer')) continue;
      sendHeaders[hk] = this._headers[hk];
    }

    function dispatch() {
      if (self._aborted) return;
      if (!academic) {
        if (url.pathname.indexOf('/check/login.do') >= 0) {
          delete bksxkCookies.JSESSIONID;
        }
        var cookieHeader = serializeBksxkCookies();
        if (cookieHeader) sendHeaders.Cookie = cookieHeader;
        else delete sendHeaders.Cookie;
      } else if (url.hostname === AUTH_HOST) {
        // authserver.nwafu.edu.cn rejects requests carrying a foreign Referer
        // with HTTP 404. Force same-origin Origin & Referer on CAS endpoints.
        sendHeaders.Origin = 'https://' + AUTH_HOST;
        sendHeaders.Referer = (url.pathname.indexOf('/authserver/reAuthCheck/') === 0 ||
          url.pathname.indexOf('/authserver/dynamicCode/') === 0)
          ? 'https://' + AUTH_HOST + '/authserver/reAuthCheck/reAuthLoginView.do?isMultifactor=true'
          : 'https://' + AUTH_HOST + '/authserver/login';
      }
      var details = {
        method: self._method,
        url: url.href,
        headers: sendHeaders,
        data: normaliseBody(body, sendHeaders),
        timeout: self.timeout || 0,
        // Academic hosts reuse the browser's official CAS session; bksxk runs
        // isolated with its own verified-fresh route cookie so stale browser
        // cookies never stick to a lagging backend node.
        anonymous: !academic,
        responseType: self.responseType === 'arraybuffer' ? 'arraybuffer' : undefined,
      onload: function (resp) {
        if (self._aborted) return;
        if (academic && !isSafeEduResponse(resp.finalUrl)) {
          details.onerror();
          return;
        }
        self.status = resp.status;
        self.statusText = resp.statusText || '';
        self.responseURL = resp.finalUrl || self._url;
        self._responseHeaders = resp.responseHeaders || '';
        if (academic) {
          // Dio does not retain XHR.responseURL. Supply a bridge-owned header
          // so it can distinguish the official login/MFA page from a jwapp app.
          self._responseHeaders = self._responseHeaders.split(/\r?\n/)
            .filter(function (line) {
              return !/^(set-cookie|set-cookie2|x-bksxk-final-url):/i.test(line);
            }).join('\r\n') + '\r\nx-bksxk-final-url: ' + resp.finalUrl + '\r\n';
          } else {
            mergeBksxkSetCookies(resp.responseHeaders || '');
            if (url.pathname.indexOf('/publicinfo/sysparam.do') >= 0) {
              var ts = parseInitTsFromBody(resp.responseText || '');
              if (ts > bksxkHighestInitTs) {
                bksxkHighestInitTs = ts;
              } else if (ts > 0 && ts < bksxkHighestInitTs) {
                delete bksxkCookies.route;
                bksxkRouteReady = false;
              }
            }
          }
          if (self.responseType === 'arraybuffer') {
            self.response = resp.response;
          } else {
            self.response = resp.responseText;
            self.responseText = resp.responseText;
          }
          self.readyState = 4;
          self._emitReadyState();
          self._emit('progress');
          self._emit('load');
          self._emit('loadend');
        },
        onerror: function () {
          if (self._aborted) return;
          self.status = 0;
          self.readyState = 4;
          self._emitReadyState();
          self._emit('error');
          self._emit('loadend');
        },
        ontimeout: function () {
          if (self._aborted) return;
          self.status = 0;
          self.readyState = 4;
          self._emitReadyState();
          self._emit('timeout');
          self._emit('loadend');
        },
      };
      self._gm = GM_xmlhttpRequest(details);
    }

    if (!academic && (refreshRoute || (!bksxkRouteReady && isBksxkRouteSensitivePath(url.pathname)))) {
      ensureFreshBksxkRoute(refreshRoute, dispatch);
    } else {
      dispatch();
    }
  };

  // Some callers set/read these; keep them harmless.
  BridgedXHR.prototype.overrideMimeType = function () {};
  BridgedXHR.UNSENT = 0;
  BridgedXHR.OPENED = 1;
  BridgedXHR.HEADERS_RECEIVED = 2;
  BridgedXHR.LOADING = 3;
  BridgedXHR.DONE = 4;

  // Install: a facade whose open() picks the bridged impl for API-host URLs and
  // the native XHR for everything else (fonts, same-origin assets, etc.).
  var XHRFacade = function () {
    var bridged = new BridgedXHR();
    var native = new NativeXHR();
    var useBridge = false;
    var opened = false;

    var active = function () { return useBridge ? bridged : native; };

    var handler = {
      UNSENT: 0,
      OPENED: 1,
      HEADERS_RECEIVED: 2,
      LOADING: 3,
      DONE: 4,
      open: function (method, url, async) {
        useBridge = isApiUrl(url);
        opened = true;
        active().open(method, url, async !== false);
      },
      send: function (b) { active().send(b); },
      setRequestHeader: function (k, v) { active().setRequestHeader(k, v); },
      getAllResponseHeaders: function () { return active().getAllResponseHeaders(); },
      getResponseHeader: function (n) { return active().getResponseHeader(n); },
      abort: function () { active().abort(); },
      addEventListener: function (t, f, opts) {
        if (opened) {
          active().addEventListener(t, f, opts);
        } else {
          bridged.addEventListener(t, f, opts);
          if (typeof native.addEventListener === 'function') native.addEventListener(t, f, opts);
        }
      },
      removeEventListener: function (t, f, opts) {
        if (opened) {
          active().removeEventListener(t, f, opts);
        } else {
          bridged.removeEventListener(t, f, opts);
          if (typeof native.removeEventListener === 'function') native.removeEventListener(t, f, opts);
        }
      },
      overrideMimeType: function (m) { if (!useBridge) native.overrideMimeType(m); },
    };
    Object.defineProperty(handler, 'upload', { get: function () { return active().upload; }, configurable: true });

    // Properties read from / write to the active implementation.
    var props = ['readyState', 'status', 'statusText', 'response', 'responseText',
                 'responseURL', 'responseType', 'timeout', 'withCredentials',
                 'onreadystatechange', 'onload', 'onerror', 'ontimeout', 'onabort',
                 'onprogress', 'onloadend'];
    props.forEach(function (p) {
      Object.defineProperty(handler, p, {
        get: function () { return active()[p]; },
        set: function (v) {
          if (opened) {
            try { active()[p] = v; } catch (e) { /* ignore */ }
          } else {
            // Set on both until open() picks one; harmless either way.
            try { bridged[p] = v; } catch (e) { /* ignore */ }
            try { native[p] = v; } catch (e) { /* ignore */ }
          }
        },
        configurable: true,
        enumerable: true,
      });
    });

    return handler;
  };
  XHRFacade.UNSENT = 0;
  XHRFacade.OPENED = 1;
  XHRFacade.HEADERS_RECEIVED = 2;
  XHRFacade.LOADING = 3;
  XHRFacade.DONE = 4;
  win.XMLHttpRequest = XHRFacade;

  console.log('[NWAFU Web Bridge v' + BRIDGE_VERSION + '] installed — 校园请求将通过 GM_xmlhttpRequest 访问 ' +
    [API_HOST, EDU_HOST, PORTAL_HOST, LIBRARY_HOST, AUTH_HOST].join(' / '));
})();
