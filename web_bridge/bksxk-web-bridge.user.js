// ==UserScript==
// @name         西农本科选课 · Web 跨域桥接 (BKSXK Web Bridge)
// @namespace    cn.edu.nwafu.bksxk.webbridge
// @version      1.0.0
// @description  让「西农本科选课」网页版可以直接访问校园网选课接口：把发往 bksxk.nwafu.edu.cn 的请求改走 GM_xmlhttpRequest，绕过浏览器 CORS 与被禁止的请求头限制。仅在校园网内有效。
// @author       nwafu-bksxk
// @match        https://mjy.js.org/nwafu-bksxk/*
// @match        http://localhost:*/*
// @match        http://127.0.0.1:*/*
// @match        https://*.github.io/*
// @match        https://*.pages.dev/*
// @match        https://*.vercel.app/*
// @match        https://*.netlify.app/*
// @connect      bksxk.nwafu.edu.cn
// @grant        GM_xmlhttpRequest
// @grant        unsafeWindow
// @run-at       document-start
// ==/UserScript==

//
// HOW IT WORKS
// ------------
// The Flutter web app (served from GitHub Pages / localhost / etc.) makes its
// API calls with XMLHttpRequest to https://bksxk.nwafu.edu.cn/... . A browser
// blocks those as cross-origin (the school server sends no CORS headers) and
// also forbids setting Cookie / User-Agent from page JS.
//
// This script replaces window.XMLHttpRequest with a shim: requests to the API
// host are routed through GM_xmlhttpRequest (a privileged, CORS-exempt request
// that carries the browser's bksxk cookies), while every other request falls
// through to the native XMLHttpRequest untouched. The app needs no changes.
//
// SECURITY: @connect is limited to bksxk.nwafu.edu.cn, so this script can only
// reach the course-selection host — nothing else.
//
(function () {
  'use strict';

  var API_HOST = 'bksxk.nwafu.edu.cn';
  var win = typeof unsafeWindow !== 'undefined' ? unsafeWindow : window;
  var NativeXHR = win.XMLHttpRequest;

  // Signal to the app that the bridge is present (used to skip the install prompt).
  try {
    win.__bksxkBridgeReady = true;
    win.__bksxkBridgeVersion = '1.0.0';
  } catch (e) { /* ignore */ }

  function isApiUrl(url) {
    try {
      // Absolute URL to the API host, or a protocol-relative/absolute path that
      // resolves to it.
      var u = new URL(url, win.location.href);
      return u.hostname === API_HOST;
    } catch (e) {
      return false;
    }
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

  BridgedXHR.prototype.send = function (body) {
    var self = this;
    var details = {
      method: this._method,
      url: new URL(this._url, win.location.href).href,
      headers: this._headers,
      data: body,
      timeout: this.timeout || 0,
      // Carry the browser's bksxk cookies with the request.
      anonymous: false,
      responseType: this.responseType === 'arraybuffer' ? 'arraybuffer' : undefined,
      onload: function (resp) {
        if (self._aborted) return;
        self.status = resp.status;
        self.statusText = resp.statusText || '';
        self.responseURL = resp.finalUrl || self._url;
        self._responseHeaders = resp.responseHeaders || '';
        if (self.responseType === 'arraybuffer') {
          self.response = resp.response;
        } else {
          self.response = resp.responseText;
          self.responseText = resp.responseText;
        }
        self.readyState = 4;
        self._emitReadyState();
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

  console.log('[BKSXK Web Bridge] installed — API 请求将通过 GM_xmlhttpRequest 访问 ' + API_HOST);
})();
