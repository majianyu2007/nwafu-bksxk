// ==UserScript==
// @name         西农教务助手 · 网页版桥接 (NWAFU Web Bridge)
// @namespace    cn.edu.nwafu.bksxk.webbridge
// @version      1.3.1
// @description  让西农教务助手网页版访问学校接口：选课，以及用本浏览器里已登录的教务会话查看课表、成绩、考试和空教室。教务登录在学校官方页面完成；仅在校园网内有效。
// @author       nwafu-bksxk
// @match        https://mjy.js.org/nwafu-bksxk/*
// @match        http://localhost:*/*
// @match        http://127.0.0.1:*/*
// @match        https://majianyu2007.github.io/nwafu-bksxk/*
// @connect      bksxk.nwafu.edu.cn
// @connect      ehall.nwafu.edu.cn
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
// The Flutter web app (served from GitHub Pages / localhost / etc.) makes its
// API calls with XMLHttpRequest to https://bksxk.nwafu.edu.cn/... (selection)
// and https://ehall.nwafu.edu.cn/... (timetable, grades, exams, free rooms). A browser
// blocks those as cross-origin (the school server sends no CORS headers) and
// also forbids setting Cookie / User-Agent from page JS.
//
// This script replaces window.XMLHttpRequest for selection and HTTPS jwapp
// requests only. GM follows redirects itself and carries browser cookies.
// It does NOT expose manual CAS redirects or import passwords/private keys.
// The user signs in on the official school page, then connects that session.
// Academic access is restricted to the app's deployment and local development;
// do not restore wildcard hosting @match rules: they expose browser sessions.
//
(function () {
  'use strict';

  var API_HOST = 'bksxk.nwafu.edu.cn';
  var EDU_HOST = 'ehall.nwafu.edu.cn';
  var win = typeof unsafeWindow !== 'undefined' ? unsafeWindow : window;
  var NativeXHR = win.XMLHttpRequest;

  // Signal to the app that the bridge is present (used to skip the install prompt).
  try {
    win.__bksxkBridgeReady = true;
    win.__bksxkBridgeVersion = '1.3.1';
    win.__bksxkEduSessionBridgeReady = true;
  } catch (e) { /* ignore */ }

  // Browser extension sandboxes can hide JavaScript globals from page code.
  // A DOM attribute is visible from both worlds and provides a reliable
  // fallback for the Flutter app's installation check.
  function markBridgeReadyInDom() {
    try {
      if (win.document && win.document.documentElement) {
        win.document.documentElement.setAttribute('data-bksxk-bridge-ready', 'true');
        win.document.documentElement.setAttribute('data-bksxk-bridge-version', '1.3.1');
        win.document.documentElement.setAttribute('data-bksxk-edu-session-bridge-ready', 'true');
      }
    } catch (e) { /* ignore */ }
  }

  markBridgeReadyInDom();
  if (win.document && win.document.readyState === 'loading') {
    win.document.addEventListener('DOMContentLoaded', markBridgeReadyInDom, { once: true });
  }

  function isApiUrl(url) {
    try {
      // Absolute URL to the API host, or a protocol-relative/absolute path that
      // resolves to it.
      var u = new URL(url, win.location.href);
      return u.hostname === API_HOST || u.hostname === EDU_HOST ||
        u.hostname === 'authserver.nwafu.edu.cn';
    } catch (e) {
      return false;
    }
  }

  function isEduUrl(u) {
    return u.protocol === 'https:' && u.hostname === EDU_HOST &&
      (!u.port || u.port === '443') && !u.username && !u.password &&
      u.pathname.indexOf('/jwapp/') === 0;
  }

  // Explicit read-only EMAP contract. POST here is querying, never a generic
  // authenticated proxy: no enrollment, application, password or MFA writes.
  function isEduRead(method, u) {
    if (!isEduUrl(u)) return false;
    var path = u.pathname;
    if (method.toUpperCase() === 'GET') {
      return /^\/jwapp\/sys\/(wdkbby|cjcx|studentWdksapApp|kxjas)\/\*default\/index\.do$/.test(path) ||
        /^\/jwapp\/sys\/funauthapp\/api\/getAppConfig\/(wdkbby-5959167891382285|cjcx-4768574631264620|studentWdksapApp-4768687067472349|kxjas-4768402106681759)\.do$/.test(path);
    }
    if (method.toUpperCase() !== 'POST' || u.search) return false;
    return /^\/jwapp\/sys\/wdkbby\/modules\/(jshkcb\/(dqxnxq|xnxqcx|jc)|xskcb\/(cxxljc|cxxszhxqkb|xswpkc|xsdkkc))\.do$/.test(path) ||
      /^\/jwapp\/sys\/cjcx\/modules\/cjcx\/(xscjcx|cxxscjpm)\.do$/.test(path) ||
      path === '/jwapp/sys/studentWdksapApp/WdksapController/cxxsksap.do' ||
      path === '/jwapp/sys/studentWdksapApp/modules/wdksap/cxxsjbxx.do' ||
      path === '/jwapp/sys/kxjas/modules/kxjscx/cxkxjs.do';
  }

  function isSafeEduResponse(url) {
    try {
      var u = new URL(url);
      return u.protocol === 'https:' && (!u.port || u.port === '443') &&
        !u.username && !u.password &&
        (u.hostname === EDU_HOST || u.hostname === 'authserver.nwafu.edu.cn');
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
    this._responseHeaders = '';
    this._aborted = false;
    var noop = function () {};
    this.upload = { addEventListener: noop, removeEventListener: noop };
  }

  BridgedXHR.prototype.open = function (method, url, async) {
    this._method = method;
    this._url = url;
    this._async = async !== false;
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
    var re = new RegExp('^' + name + ':\\s*(.*)$', 'im');
    var m = re.exec(this._responseHeaders || '');
    return m ? m[1].trim() : null;
  };

  BridgedXHR.prototype.addEventListener = function (type, fn) {
    (this._listeners[type] = this._listeners[type] || []).push(fn);
  };

  BridgedXHR.prototype.removeEventListener = function (type, fn) {
    var l = this._listeners[type];
    if (!l) return;
    var i = l.indexOf(fn);
    if (i >= 0) l.splice(i, 1);
  };

  BridgedXHR.prototype._emit = function (type) {
    var evt = { type: type, target: this, currentTarget: this };
    var direct = this['on' + type];
    if (typeof direct === 'function') direct.call(this, evt);
    var l = this._listeners[type];
    if (l) for (var i = 0; i < l.length; i++) l[i].call(this, evt);
  };

  BridgedXHR.prototype._emitReadyState = function () {
    if (typeof this.onreadystatechange === 'function') {
      this.onreadystatechange({ type: 'readystatechange', target: this });
    }
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
    var details = {
      method: this._method,
      url: new URL(this._url, win.location.href).href,
      headers: this._headers,
      data: normaliseBody(body, this._headers),
      timeout: this.timeout || 0,
      // Use the browser's session; no app-side Cookie header or cookie export.
      anonymous: false,
      responseType: this.responseType === 'arraybuffer' ? 'arraybuffer' : undefined,
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
        self.status = 0;
        self.readyState = 4;
        self._emitReadyState();
        self._emit('timeout');
        self._emit('loadend');
      },
    };
    this._gm = GM_xmlhttpRequest(details);
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
  win.XMLHttpRequest = function () {
    var bridged = new BridgedXHR();
    var native = new NativeXHR();
    var useBridge = false;

    var active = function () { return useBridge ? bridged : native; };

    var handler = {
      open: function (method, url, async) {
        useBridge = isApiUrl(url);
        active().open(method, url, async !== false);
      },
      send: function (b) { active().send(b); },
      setRequestHeader: function (k, v) { active().setRequestHeader(k, v); },
      getAllResponseHeaders: function () { return active().getAllResponseHeaders(); },
      getResponseHeader: function (n) { return active().getResponseHeader(n); },
      abort: function () { active().abort(); },
      addEventListener: function (t, f) { bridged.addEventListener(t, f); native.addEventListener(t, f); },
      removeEventListener: function (t, f) { bridged.removeEventListener(t, f); native.removeEventListener(t, f); },
      overrideMimeType: function (m) { if (!useBridge) native.overrideMimeType(m); },
    };
    Object.defineProperty(handler, 'upload', { get: function () { return active().upload; }, configurable: true });

    // Properties read from / write to the active implementation.
    var props = ['readyState', 'status', 'statusText', 'response', 'responseText',
                 'responseURL', 'responseType', 'timeout', 'withCredentials',
                 'onreadystatechange', 'onload', 'onerror', 'ontimeout', 'onabort'];
    props.forEach(function (p) {
      Object.defineProperty(handler, p, {
        get: function () { return active()[p]; },
        set: function (v) {
          // Set on both until open() picks one; harmless either way.
          try { bridged[p] = v; } catch (e) { /* ignore */ }
          try { native[p] = v; } catch (e) { /* ignore */ }
        },
        configurable: true,
        enumerable: true,
      });
    });

    return handler;
  };

  console.log('[NWAFU Web Bridge] installed — 选课与教务请求将通过 GM_xmlhttpRequest 访问 ' + API_HOST + ' / ' + EDU_HOST);
})();
