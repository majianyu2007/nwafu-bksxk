// ==UserScript==
// @name         BKSXK API Guard
// @namespace    local.bksxk.guard
// @version      0.1.0
// @description  Record BKSXK API calls and keep selected write operations local.
// @match        *://bksxk.nwafu.edu.cn/*
// @match        *://*.nwafu.edu.cn/*
// @run-at       document-start
// @grant        none
// ==/UserScript==

(function installBksxkGuard() {
  'use strict';

  const win = typeof unsafeWindow !== 'undefined' ? unsafeWindow : window;
  if (win.__BKSXK_GUARD_INSTALLED__) return;
  win.__BKSXK_GUARD_INSTALLED__ = true;

  const COLLECTOR_URL = 'http://127.0.0.1:48732/event';
  const MAX_LOCAL_LOGS = 500;
  const MAX_RESPONSE_PREVIEW = 200000;
  const WRITE_CLICK_TEXT = /选课|退选|提交|保存|确认|确定|志愿|退课|删除|撤销|choose|select|drop|withdraw|submit|save|confirm|delete|remove/i;
  const WRITE_REQUEST_TEXT = /退选|选课|退课|提交|保存|确认|撤销|chooseLesson|selectCourse|courseSelect|drop|withdraw|submit|save|confirm|delete|remove|cancel|grabLesson|grab|addLesson|delLesson|lessonResult/i;
  const READ_ONLY_HINT = /query|search|list|page|get|load|find|menu|captcha|login|cas|auth|ticket|profile|studentInfo/i;
  const SENSITIVE_KEY = /pass|pwd|password|token|csrf|xsrf|cookie|authorization|session|ticket|sid|secret|credential|execution|lt|学号|xh|student|userid|username|account|login/i;
  const SENSITIVE_HEADER = /cookie|authorization|token|csrf|xsrf|ticket|session|set-cookie/i;

  const state = {
    installedAt: new Date().toISOString(),
    blockUntil: 0,
    blockReason: '',
    strictWrites: false,
    blockedCount: 0,
    sentCount: 0,
  };

  function now() {
    return new Date().toISOString();
  }

  function safeDecode(value) {
    try {
      return decodeURIComponent(String(value || ''));
    } catch {
      return String(value || '');
    }
  }

  function urlSummary(rawUrl) {
    const url = String(rawUrl || location.href);
    const queryIndex = url.indexOf('?');
    const hashIndex = url.indexOf('#');
    const endIndex = queryIndex >= 0 ? queryIndex : hashIndex >= 0 ? hashIndex : url.length;
    const noQuery = url.slice(0, endIndex);
    const originMatch = noQuery.match(/^[a-z][a-z0-9+.-]*:\/\/[^/]+/i);
    const origin = originMatch ? originMatch[0] : location.origin;
    const path = noQuery.slice(origin.length) || '/';
    const query = queryIndex >= 0 ? url.slice(queryIndex + 1, hashIndex >= 0 ? hashIndex : url.length) : '';
    const queryKeys = query
      ? query
          .split('&')
          .filter(Boolean)
          .map((part) => safeDecode(part.split('=')[0]))
          .filter(Boolean)
      : [];
    return { origin, path, queryKeys };
  }

  function redactUrl(rawUrl) {
    const text = String(rawUrl || '');
    const hashSplit = text.split('#');
    const main = hashSplit[0];
    const hash = hashSplit.length > 1 ? `#${hashSplit.slice(1).join('#')}` : '';
    const queryIndex = main.indexOf('?');
    const redactPath = (value) => value.replace(/(\/student\/)\d+(\.do\b)/i, '$1<redacted>$2');
    if (queryIndex < 0) return redactPath(redactScalar(main, 'url')) + hash;

    const base = redactPath(main.slice(0, queryIndex));
    const query = main.slice(queryIndex + 1);
    const redactedQuery = query
      .split('&')
      .map((part) => {
        if (!part) return part;
        const splitAt = part.indexOf('=');
        const key = safeDecode(splitAt >= 0 ? part.slice(0, splitAt) : part);
        const rawKey = splitAt >= 0 ? part.slice(0, splitAt) : part;
        const rawValue = splitAt >= 0 ? part.slice(splitAt + 1) : '';
        const value = SENSITIVE_KEY.test(key) ? '<redacted>' : redactScalar(safeDecode(rawValue), key);
        return splitAt >= 0 ? `${rawKey}=${encodeURIComponent(value)}` : rawKey;
      })
      .join('&');
    return `${base}?${redactedQuery}${hash}`;
  }

  function redactScalar(value, key) {
    if (SENSITIVE_KEY.test(String(key || ''))) return '<redacted>';
    if (typeof value !== 'string') return value;
    return value
      .replace(/((?:pass|pwd|password)\s*[=:]\s*)[^&\s"]+/gi, '$1<redacted>')
      .replace(/((?:token|csrf|xsrf|ticket|session|sid|userid|username|account)\s*[=:]\s*)[^&\s"]+/gi, '$1<redacted>');
  }

  function sanitize(value, key) {
    if (value == null) return value;
    if (Array.isArray(value)) return value.map((item) => sanitize(item));
    if (typeof value === 'object') {
      const out = {};
      for (const entry of Object.entries(value)) {
        out[entry[0]] = SENSITIVE_KEY.test(entry[0]) ? '<redacted>' : sanitize(entry[1], entry[0]);
      }
      return out;
    }
    return redactScalar(value, key);
  }

  function sanitizeHeaders(headers) {
    const out = {};
    if (!headers) return out;
    try {
      if (headers instanceof Headers) {
        headers.forEach((value, key) => {
          out[key] = SENSITIVE_HEADER.test(key) ? '<redacted>' : value;
        });
        return out;
      }
      for (const [key, value] of Object.entries(headers)) {
        out[key] = SENSITIVE_HEADER.test(key) ? '<redacted>' : value;
      }
    } catch {
      return {};
    }
    return out;
  }

  function shouldPreviewResponse(headers) {
    const contentType = String(headers && headers['content-type'] ? headers['content-type'] : '').toLowerCase();
    return /json|text|javascript|html|plain|xml/.test(contentType);
  }

  function previewText(text) {
    if (typeof text !== 'string') return text;
    if (text.length <= MAX_RESPONSE_PREVIEW) return text;
    return `${text.slice(0, MAX_RESPONSE_PREVIEW)}\n<truncated ${text.length - MAX_RESPONSE_PREVIEW} chars>`;
  }

  function bodyToShape(value) {
    if (value == null) return null;
    if (typeof value === 'string') {
      const trimmed = value.trim();
      if (!trimmed) return '';
      if ((trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
        try {
          return sanitize(JSON.parse(trimmed));
        } catch {
          return redactScalar(trimmed);
        }
      }
      if (trimmed.includes('=') || trimmed.includes('&')) {
        const out = {};
        for (const part of trimmed.split('&')) {
          if (!part) continue;
          const splitAt = part.indexOf('=');
          const key = safeDecode(splitAt >= 0 ? part.slice(0, splitAt) : part);
          const item = safeDecode(splitAt >= 0 ? part.slice(splitAt + 1) : '');
          out[key] = redactScalar(item, key);
        }
        return out;
      }
      return redactScalar(trimmed);
    }
    if (typeof URLSearchParams !== 'undefined' && value instanceof URLSearchParams) {
      const out = {};
      value.forEach((item, key) => {
        out[key] = redactScalar(item, key);
      });
      return out;
    }
    if (typeof FormData !== 'undefined' && value instanceof FormData) {
      const out = {};
      value.forEach((item, key) => {
        out[key] = typeof item === 'string' ? redactScalar(item, key) : `<file:${item && item.name ? item.name : 'blob'}>`;
      });
      return out;
    }
    if (typeof Blob !== 'undefined' && value instanceof Blob) return `<blob:${value.type || 'unknown'}:${value.size}>`;
    if (typeof ArrayBuffer !== 'undefined' && value instanceof ArrayBuffer) return `<arrayBuffer:${value.byteLength}>`;
    return sanitize(value);
  }

  async function serializeRequestBody(input, init) {
    if (init && Object.prototype.hasOwnProperty.call(init, 'body')) return bodyToShape(init.body);
    if (typeof Request !== 'undefined' && input instanceof Request) {
      try {
        return bodyToShape(await input.clone().text());
      } catch {
        return '<unavailable>';
      }
    }
    return null;
  }

  function pushLocal(record) {
    try {
      const list = JSON.parse(sessionStorage.getItem('__BKSXK_GUARD_LOGS__') || '[]');
      list.push(record);
      sessionStorage.setItem('__BKSXK_GUARD_LOGS__', JSON.stringify(list.slice(-MAX_LOCAL_LOGS)));
    } catch {
      // Storage can be disabled in some frames.
    }
  }

  function report(record) {
    const safeRecord = sanitize({
      ts: now(),
      pageUrl: location.href,
      source: 'userscript',
      ...record,
    });
    pushLocal(safeRecord);

    try {
      if (typeof win.__bksxkGuardReport === 'function') {
        win.__bksxkGuardReport(safeRecord);
      }
    } catch {
      // Playwright binding is best effort.
    }

    try {
      navigator.sendBeacon(COLLECTOR_URL, new Blob([JSON.stringify(safeRecord)], { type: 'text/plain' }));
    } catch {
      try {
        fetch(COLLECTOR_URL, {
          method: 'POST',
          mode: 'no-cors',
          keepalive: true,
          headers: { 'Content-Type': 'text/plain' },
          body: JSON.stringify(safeRecord),
        });
      } catch {
        // Local receiver is optional.
      }
    }
  }

  function arm(seconds, reason) {
    const duration = seconds == null ? 20 : Number(seconds);
    state.blockUntil = Date.now() + duration * 1000;
    state.blockReason = String(reason || 'manual').slice(0, 160);
    report({
      type: 'guard-armed',
      reason: state.blockReason,
      blockUntil: new Date(state.blockUntil).toISOString(),
    });
  }

  function shouldBlock(method, rawUrl, bodyShape) {
    const upperMethod = String(method || 'GET').toUpperCase();
    if (upperMethod === 'GET' || upperMethod === 'HEAD' || upperMethod === 'OPTIONS') return false;

    const text = `${safeDecode(rawUrl)}\n${safeDecode(JSON.stringify(bodyShape || ''))}`;
    if (Date.now() < state.blockUntil) return true;
    if (WRITE_REQUEST_TEXT.test(text) && !READ_ONLY_HINT.test(text)) return true;
    if (state.strictWrites && !READ_ONLY_HINT.test(text)) return true;
    return false;
  }

  function requestRecord(kind, status, method, rawUrl, headers, bodyShape, extra) {
    return {
      type: 'request',
      transport: kind,
      status,
      method: String(method || 'GET').toUpperCase(),
      resourceType: kind,
      url: redactUrl(rawUrl || location.href),
      urlSummary: urlSummary(rawUrl || location.href),
      headers: sanitizeHeaders(headers),
      postData: bodyShape,
      ...extra,
    };
  }

  function patchFetch() {
    if (!win.fetch || win.fetch.__bksxkGuardPatched) return;
    const originalFetch = win.fetch.bind(win);
    const patchedFetch = async function guardedFetch(input, init) {
      const method = (init && init.method) || (typeof Request !== 'undefined' && input instanceof Request ? input.method : 'GET');
      const rawUrl = typeof input === 'string' ? input : input && input.url ? input.url : String(input);
      const headers = (init && init.headers) || (typeof Request !== 'undefined' && input instanceof Request ? input.headers : {});
      const bodyShape = await serializeRequestBody(input, init || {});

      if (shouldBlock(method, rawUrl, bodyShape)) {
        state.blockedCount += 1;
        report(requestRecord('fetch', 'blocked', method, rawUrl, headers, bodyShape, { guardReason: state.blockReason || 'state-changing request' }));
        throw new DOMException('BKSXK Guard kept this write request local.', 'NetworkError');
      }

      state.sentCount += 1;
      report(requestRecord('fetch', 'sent', method, rawUrl, headers, bodyShape));
      try {
        const response = await originalFetch(input, init);
        const responseHeaders = sanitizeHeaders(response.headers);
        let bodyPreview;
        if (shouldPreviewResponse(responseHeaders)) {
          try {
            bodyPreview = previewText(await response.clone().text());
          } catch {
            bodyPreview = '<unavailable>';
          }
        }
        report({
          type: 'response',
          transport: 'fetch',
          method: String(method || 'GET').toUpperCase(),
          resourceType: 'fetch',
          url: rawUrl,
          urlSummary: urlSummary(rawUrl),
          status: response.status,
          headers: responseHeaders,
          bodyPreview,
        });
        return response;
      } catch (error) {
        report({
          type: 'request',
          transport: 'fetch',
          status: 'failed',
          method: String(method || 'GET').toUpperCase(),
          resourceType: 'fetch',
          url: rawUrl,
          urlSummary: urlSummary(rawUrl),
          postData: bodyShape,
          failure: error && error.message ? error.message : String(error),
        });
        throw error;
      }
    };
    patchedFetch.__bksxkGuardPatched = true;
    win.fetch = patchedFetch;
  }

  function patchXhr() {
    if (!win.XMLHttpRequest || win.XMLHttpRequest.prototype.__bksxkGuardPatched) return;
    const proto = win.XMLHttpRequest.prototype;
    const originalOpen = proto.open;
    const originalSend = proto.send;
    proto.open = function guardedOpen(method, rawUrl) {
      this.__bksxkGuardMeta = { method, rawUrl };
      return originalOpen.apply(this, arguments);
    };
    proto.send = function guardedSend(body) {
      const meta = this.__bksxkGuardMeta || {};
      const method = meta.method || 'GET';
      const rawUrl = meta.rawUrl || location.href;
      const bodyShape = bodyToShape(body);
      if (shouldBlock(method, rawUrl, bodyShape)) {
        state.blockedCount += 1;
        report(requestRecord('xhr', 'blocked', method, rawUrl, {}, bodyShape, { guardReason: state.blockReason || 'state-changing request' }));
        setTimeout(() => {
          try {
            this.dispatchEvent(new ProgressEvent('abort'));
            this.dispatchEvent(new ProgressEvent('loadend'));
          } catch {
            // Some old XHR shims do not support synthetic events.
          }
        }, 0);
        return undefined;
      }

      state.sentCount += 1;
      report(requestRecord('xhr', 'sent', method, rawUrl, {}, bodyShape));
      try {
        this.addEventListener(
          'loadend',
          () => {
            let bodyPreview;
            const responseHeaders = {};
            try {
              const rawHeaders = this.getAllResponseHeaders();
              for (const line of rawHeaders.split(/\r?\n/)) {
                const splitAt = line.indexOf(':');
                if (splitAt > 0) {
                  const key = line.slice(0, splitAt).trim().toLowerCase();
                  responseHeaders[key] = line.slice(splitAt + 1).trim();
                }
              }
            } catch {
              // Ignore header access errors.
            }
            if (shouldPreviewResponse(responseHeaders)) {
              try {
                bodyPreview = previewText(this.responseType && this.responseType !== 'text' ? '<non-text response>' : this.responseText);
              } catch {
                bodyPreview = '<unavailable>';
              }
            }
            report({
              type: 'response',
              transport: 'xhr',
              method: String(method || 'GET').toUpperCase(),
              resourceType: 'xhr',
              url: rawUrl,
              urlSummary: urlSummary(rawUrl),
              status: this.status,
              headers: sanitizeHeaders(responseHeaders),
              bodyPreview,
            });
          },
          { once: true },
        );
      } catch {
        // Best effort.
      }
      return originalSend.apply(this, arguments);
    };
    proto.__bksxkGuardPatched = true;
  }

  function getElementLabel(element) {
    if (!element) return '';
    return [
      element.innerText,
      element.textContent,
      element.value,
      element.title,
      element.getAttribute && element.getAttribute('aria-label'),
      element.getAttribute && element.getAttribute('data-original-title'),
    ]
      .filter(Boolean)
      .join(' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function installDomGuards() {
    document.addEventListener(
      'click',
      (event) => {
        const target = event.target;
        const element = target && target.closest
          ? target.closest('button,a,[role="button"],input[type="button"],input[type="submit"],.btn,.el-button,.layui-btn,.ivu-btn,.ant-btn,[onclick]')
          : null;
        const label = getElementLabel(element);
        if (label && WRITE_CLICK_TEXT.test(label)) {
          arm(20, `click:${label}`);
        }
      },
      true,
    );

    document.addEventListener(
      'submit',
      (event) => {
        const form = event.target;
        if (!form || !form.action) return;
        const method = form.method || 'GET';
        let bodyShape = null;
        try {
          bodyShape = bodyToShape(new FormData(form));
        } catch {
          bodyShape = '<unavailable>';
        }
        if (shouldBlock(method, form.action, bodyShape)) {
          state.blockedCount += 1;
          event.preventDefault();
          event.stopImmediatePropagation();
          report(requestRecord('form', 'blocked', method, form.action, {}, bodyShape, { guardReason: state.blockReason || 'state-changing form submit' }));
        }
      },
      true,
    );
  }

  function installBadge() {
    const paint = () => {
      if (!document.documentElement || document.getElementById('__bksxk_guard_badge__')) return;
      const badge = document.createElement('div');
      badge.id = '__bksxk_guard_badge__';
      badge.textContent = 'BKSXK Guard';
      badge.style.cssText = [
        'position:fixed',
        'right:10px',
        'bottom:10px',
        'z-index:2147483647',
        'padding:4px 7px',
        'font:12px/1.2 -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif',
        'color:#0f3d2e',
        'background:#d9fbe8',
        'border:1px solid #6bcf98',
        'border-radius:4px',
        'box-shadow:0 1px 6px rgba(0,0,0,.16)',
        'pointer-events:none',
      ].join(';');
      document.documentElement.appendChild(badge);
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', paint, { once: true });
    else paint();
  }

  win.__BKSXK_GUARD__ = {
    arm,
    strict(value) {
      state.strictWrites = Boolean(value);
      report({ type: 'guard-config', strictWrites: state.strictWrites });
      return state.strictWrites;
    },
    state() {
      return { ...state };
    },
    exportLogs() {
      try {
        return JSON.parse(sessionStorage.getItem('__BKSXK_GUARD_LOGS__') || '[]');
      } catch {
        return [];
      }
    },
  };

  patchFetch();
  patchXhr();
  installDomGuards();
  installBadge();
  report({ type: 'guard-installed', href: location.href });
})();
