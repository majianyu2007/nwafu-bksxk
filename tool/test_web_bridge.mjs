import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const scriptPath = new URL('../web_bridge/bksxk-web-bridge.user.js', import.meta.url);
const source = fs.readFileSync(scriptPath, 'utf8');

const calls = [];
let mockResponse = () => ({
  status: 200,
  statusText: 'OK',
  finalUrl: 'https://ehall.nwafu.edu.cn/jwapp/sys/wdkbby/*default/index.do',
  responseHeaders: 'content-type: application/json\r\nset-cookie: secret=1\r\n',
  responseText: '{"code":1}',
});

const attrs = {};
const sandbox = {
  URL,
  Uint8Array,
  ArrayBuffer,
  TextDecoder,
  FormData: class {},
  URLSearchParams,
  console,
  GM_xmlhttpRequest(details) {
    calls.push(details);
    const resp = mockResponse(details);
    setTimeout(() => details.onload(resp), 0);
  },
  window: {
    location: { href: 'https://mjy.js.org/nwafu-bksxk/app/' },
    XMLHttpRequest: class NativeXHR {},
    document: {
      readyState: 'complete',
      documentElement: {
        setAttribute(k, v) {
          attrs[k] = v;
        },
      },
    },
  },
};
sandbox.unsafeWindow = sandbox.window;
vm.runInNewContext(source, sandbox);

assert.equal(sandbox.window.__bksxkBridgeReady, true);
assert.equal(sandbox.window.__bksxkBridgeVersion, '1.4.1');
assert.equal(attrs['data-bksxk-bridge-version'], '1.4.1');

function send(method, url, body = null, headers = {}) {
  return new Promise((resolve) => {
    const xhr = new sandbox.window.XMLHttpRequest();
    xhr.open(method, url, true);
    for (const [k, v] of Object.entries(headers)) xhr.setRequestHeader(k, v);
    xhr.onload = () => resolve({ ok: true, xhr });
    xhr.onerror = () => resolve({ ok: false, xhr });
    xhr.send(body);
  });
}

// 1. Uint8Array body to bksxk must decode to string (never "[object Uint8Array]")
mockResponse = (d) => ({
  status: 200,
  statusText: 'OK',
  finalUrl: d.url,
  responseHeaders: 'content-type: application/json',
  responseText: '{"code":"1"}',
});
{
  const bytes = new TextEncoder().encode('foo=bar&baz=1');
  const r = await send(
    'POST',
    'https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/elective/volunteer.do',
    bytes,
    { 'Content-Type': 'application/x-www-form-urlencoded' },
  );
  assert.equal(r.ok, true);
  assert.equal(calls.at(-1).data, 'foo=bar&baz=1');
}

// 2. newehall portal endpoints allowed & strip set-cookie
{
  const r = await send(
    'GET',
    'https://newehall.nwafu.edu.cn/jsonp/ywtb/getUnreadMessageCount',
  );
  assert.equal(r.ok, true);
  assert.equal(r.xhr.getResponseHeader('set-cookie'), null);
  assert.equal(
    r.xhr.getResponseHeader('x-bksxk-final-url'),
    'https://newehall.nwafu.edu.cn/jsonp/ywtb/getUnreadMessageCount',
  );
}

// 3. booking-lib CAS redirect preserves #/cas/?cas=CODE in x-bksxk-final-url
mockResponse = () => ({
  status: 200,
  statusText: 'OK',
  finalUrl: 'https://booking-lib.nwafu.edu.cn/h5/index.html#/cas/?cas=ABC123',
  responseHeaders: 'content-type: text/html',
  responseText: '<html></html>',
});
{
  const r = await send('GET', 'https://booking-lib.nwafu.edu.cn/api/cas/cas');
  assert.equal(r.ok, true);
  assert.equal(
    r.xhr.getResponseHeader('x-bksxk-final-url'),
    'https://booking-lib.nwafu.edu.cn/h5/index.html#/cas/?cas=ABC123',
  );
}

// 4. booking-lib native seat confirm endpoint allowed
mockResponse = (d) => ({
  status: 200,
  statusText: 'OK',
  finalUrl: d.url,
  responseHeaders: 'content-type: application/json',
  responseText: '{"code":1,"msg":"预约成功"}',
});
{
  const r = await send(
    'POST',
    'https://booking-lib.nwafu.edu.cn/api/Seat/confirm',
    new TextEncoder().encode('{"aesjson":"xxx","authorization":"bearerT"}'),
    { 'Content-Type': 'application/json' },
  );
  assert.equal(r.ok, true);
  assert.equal(JSON.parse(r.xhr.responseText).code, 1);
}

// 4b. booking-lib seat map and seminar confirm endpoints allowed
{
  const r1 = await send('POST', 'https://booking-lib.nwafu.edu.cn/api/seat/map', '{"id":"1"}');
  assert.equal(r1.ok, true);
  const r2 = await send('POST', 'https://booking-lib.nwafu.edu.cn/reserve/index/confirm', '{"aesjson":"xxx"}');
  assert.equal(r2.ok, true);
}

// 5. Unsafe redirect target rejected
mockResponse = () => ({
  status: 200,
  statusText: 'OK',
  finalUrl: 'https://evil.example.com/phish',
  responseHeaders: '',
  responseText: '',
});
{
  const r = await send('GET', 'https://newehall.nwafu.edu.cn/login');
  assert.equal(r.ok, false);
}

// 6. Disallowed arbitrary path on ehall rejected
{
  const r = await send('POST', 'https://ehall.nwafu.edu.cn/jwapp/sys/evil/write.do');
  assert.equal(r.ok, false);
}

console.log('All 6 web bridge tests passed.');
