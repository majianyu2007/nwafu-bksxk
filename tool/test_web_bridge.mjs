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

let mockHandler = null;
const attrs = {};
const sandbox = {
  URL,
  Uint8Array,
  ArrayBuffer,
  TextDecoder,
  Blob,
  FormData: class {},
  URLSearchParams,
  console,
  GM_xmlhttpRequest(details) {
    calls.push(details);
    if (mockHandler) return mockHandler(details);
    const resp = mockResponse(details);
    const timer = setTimeout(() => details.onload(resp), 0);
    return {
      abort() {
        clearTimeout(timer);
        if (typeof details.onabort === 'function') details.onabort();
      },
    };
  },
  window: {
    location: { href: 'https://mjy.js.org/nwafu-bksxk/app/' },
    XMLHttpRequest: class NativeXHR {
      open() {}
      send() {}
      setRequestHeader() {}
      addEventListener() {}
      removeEventListener() {}
      overrideMimeType() {}
    },
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
assert.equal(sandbox.window.__bksxkBridgeVersion, '1.5.1');
assert.equal(sandbox.window.__bksxkCasLoginBridgeReady, true);
assert.equal(attrs['data-bksxk-bridge-version'], '1.5.1');
assert.equal(attrs['data-bksxk-cas-login-bridge-ready'], 'true');
assert.equal(sandbox.window.XMLHttpRequest.DONE, 4);
assert.equal(new sandbox.window.XMLHttpRequest().DONE, 4);

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

// 4b. booking-lib seat map, floorplan image, and seminar confirm/cancel/signout endpoints allowed
{
  const r1 = await send('POST', 'https://booking-lib.nwafu.edu.cn/api/seat/map', '{"id":"1"}');
  assert.equal(r1.ok, true);
  const r2 = await send('POST', 'https://booking-lib.nwafu.edu.cn/reserve/index/confirm', '{"aesjson":"xxx"}');
  assert.equal(r2.ok, true);
  const r3 = await send('GET', 'https://booking-lib.nwafu.edu.cn/uploads/floor4.png');
  assert.equal(r3.ok, true);
  const r4 = await send('POST', 'https://booking-lib.nwafu.edu.cn/api/space/seminarCancel', '{"aesjson":"xxx"}');
  assert.equal(r4.ok, true);
  const r5 = await send('POST', 'https://booking-lib.nwafu.edu.cn/reserve/seminar/signout', '{"aesjson":"xxx"}');
  assert.equal(r5.ok, true);
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

// 7. bksxk fresh-node pinning avoids zombie node (old initTimestamp) & isolates cookies
{
  let probeIdx = 0;
  const probeNodes = [
    { route: '2074c2538aee3dfbb37bbf24e6596c51', ts: '1788928141330' }, // stale Sep-9 zombie
    { route: 'f5a676915751f478db3c4448bd0d8db3', ts: '1792144680028' }, // healthy Oct-16
    { route: '622503b5c3b661d3018e64339e65752b', ts: '1792144680028' }, // healthy Oct-16
  ];
  mockResponse = (d) => {
    if (d.url.includes('/publicinfo/sysparam.do')) {
      const node = probeNodes[probeIdx % probeNodes.length];
      probeIdx++;
      return {
        status: 200,
        statusText: 'OK',
        finalUrl: d.url,
        responseHeaders: `content-type: application/json\r\nset-cookie: route=${node.route}; Path=/\r\n`,
        responseText: JSON.stringify({ code: '1', data: { initTimestamp: node.ts } }),
      };
    }
    return {
      status: 200,
      statusText: 'OK',
      finalUrl: d.url,
      responseHeaders: 'content-type: application/json',
      responseText: '{"code":"1","data":{"token":"vtok1"}}',
    };
  };
  const r = await send('GET', 'https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/student/4/vcode.do?timestamp=1');
  assert.equal(r.ok, true);
  const vcodeCall = calls.at(-1);
  assert.equal(vcodeCall.anonymous, true);
  assert.equal(vcodeCall.headers.Cookie, 'route=f5a676915751f478db3c4448bd0d8db3');

  // 8. X-Bksxk-Refresh-Route triggers rotation away from previous route & is stripped
  probeIdx = 0;
  const r2 = await send(
    'GET',
    'https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/student/2025013665.do?timestamp=2',
    null,
    { token: 'tok', 'X-Bksxk-Refresh-Route': '1' },
  );
  assert.equal(r2.ok, true);
  const stuCall = calls.at(-1);
  assert.equal(stuCall.anonymous, true);
  assert.equal(stuCall.headers['X-Bksxk-Refresh-Route'], undefined);
  assert.equal(stuCall.headers.Cookie, 'route=622503b5c3b661d3018e64339e65752b');
}

// 9. authserver CAS login/MFA/logout allowed with same-origin Referer & Origin, set-cookie stripped
{
  mockResponse = (d) => ({
    status: 200,
    statusText: 'OK',
    finalUrl: d.url.includes('/authserver/login') && d.method === 'POST'
      ? 'https://ehall.nwafu.edu.cn/jwapp/sys/wdkbby/*default/index.do'
      : d.url,
    responseHeaders: 'content-type: text/html\r\nset-cookie: CASTGC=secret; HttpOnly\r\n',
    responseText: '<html>ok</html>',
  });
  const loginGet = await send('GET', 'https://authserver.nwafu.edu.cn/authserver/login?service=https%3A%2F%2Fehall.nwafu.edu.cn%2Fjwapp%2Fsys%2Fwdkbby%2F*default%2Findex.do');
  assert.equal(loginGet.ok, true);
  assert.equal(calls.at(-1).anonymous, false);
  assert.equal(calls.at(-1).headers.Origin, 'https://authserver.nwafu.edu.cn');
  assert.equal(calls.at(-1).headers.Referer, 'https://authserver.nwafu.edu.cn/authserver/login');
  assert.equal(loginGet.xhr.getResponseHeader('set-cookie'), null);

  const loginPost = await send(
    'POST',
    'https://authserver.nwafu.edu.cn/authserver/login?service=https%3A%2F%2Fehall.nwafu.edu.cn%2Fjwapp%2Fsys%2Fwdkbby%2F*default%2Findex.do',
    new TextEncoder().encode('username=2025013665&password=enc'),
    { 'Content-Type': 'application/x-www-form-urlencoded' },
  );
  assert.equal(loginPost.ok, true);
  assert.equal(
    loginPost.xhr.getResponseHeader('x-bksxk-final-url'),
    'https://ehall.nwafu.edu.cn/jwapp/sys/wdkbby/*default/index.do',
  );

  // 10. MFA submit uses reAuthLoginView.do Referer; logout & bfp/info & checkNeedCaptcha allowed
  const mfa = await send(
    'POST',
    'https://authserver.nwafu.edu.cn/authserver/reAuthCheck/reAuthSubmit.do',
    'service=x&dynamicCode=123456',
    { 'Content-Type': 'application/x-www-form-urlencoded' },
  );
  assert.equal(mfa.ok, true);
  assert.equal(
    calls.at(-1).headers.Referer,
    'https://authserver.nwafu.edu.cn/authserver/reAuthCheck/reAuthLoginView.do?isMultifactor=true',
  );
  assert.equal((await send('GET', 'https://authserver.nwafu.edu.cn/authserver/logout')).ok, true);
  assert.equal((await send('GET', 'https://authserver.nwafu.edu.cn/authserver/checkNeedCaptcha.htl?username=1')).ok, true);
  assert.equal((await send('GET', 'https://authserver.nwafu.edu.cn/authserver/bfp/info?bfp=abc')).ok, true);

  // 11. Disallowed personalInfo / arbitrary authserver paths remain blocked
  assert.equal((await send('POST', 'https://authserver.nwafu.edu.cn/personalInfo/accountSecurity/deleteDevice', '{}')).ok, false);
  assert.equal((await send('POST', 'https://authserver.nwafu.edu.cn/authserver/evil', '{}')).ok, false);
}

// 12. dqzc.do is allowed on ehall (week-1 anchoring), onreadystatechange fires once per transition,
//     onloadend fires, and getResponseHeader handles regex chars & comma-joins duplicates
{
  mockResponse = (d) => ({
    status: 200,
    statusText: 'OK',
    finalUrl: d.url,
    responseHeaders: 'content-type: application/json\r\nX-Custom: a\r\nx-custom: b\r\n',
    responseText: '{"datas":{"dqzc":{"rows":[{"ZC":12}]}}}',
  });
  let stateChanges = 0;
  let loadEnded = false;
  const xhr = new sandbox.window.XMLHttpRequest();
  xhr.onreadystatechange = () => { stateChanges++; };
  xhr.onloadend = () => { loadEnded = true; };
  await new Promise((resolve, reject) => {
    xhr.onload = resolve;
    xhr.onerror = () => reject(new Error('dqzc.do should be allowed'));
    xhr.open('POST', 'https://ehall.nwafu.edu.cn/jwapp/sys/wdkbby/modules/jshkcb/dqzc.do', true);
    xhr.send('XN=2026-2027&XQ=1');
  });
  assert.equal(stateChanges, 2, 'OPENED + DONE should fire onreadystatechange exactly twice');
  assert.equal(loadEnded, true);
  assert.equal(xhr.getResponseHeader('x-custom'), 'a, b');
  assert.equal(xhr.getResponseHeader('x-custom[test]'), null);
}

// 13. Case-insensitive Origin/Referer stripping on authserver and Cookie stripping on bksxk
{
  mockResponse = (d) => ({
    status: 200,
    statusText: 'OK',
    finalUrl: d.url,
    responseHeaders: 'content-type: text/html',
    responseText: '<html>ok</html>',
  });
  const r = await send(
    'GET',
    'https://authserver.nwafu.edu.cn/authserver/login',
    null,
    { referer: 'https://mjy.js.org/evil', origin: 'https://mjy.js.org' },
  );
  assert.equal(r.ok, true);
  assert.equal(calls.at(-1).headers.referer, undefined);
  assert.equal(calls.at(-1).headers.origin, undefined);
  assert.equal(calls.at(-1).headers.Referer, 'https://authserver.nwafu.edu.cn/authserver/login');
  assert.equal(calls.at(-1).headers.Origin, 'https://authserver.nwafu.edu.cn');
}

// 14. All-3-probes-failing (abort/error/throw) does not deadlock and re-probes next time
{
  const sandbox2 = {
    ...sandbox,
    window: {
      ...sandbox.window,
      XMLHttpRequest: sandbox.window.XMLHttpRequest,
    },
  };
  let probeAttempt = 0;
  sandbox2.window = {
    location: { href: 'https://mjy.js.org/nwafu-bksxk/app/' },
    XMLHttpRequest: class NativeXHR2 {
      open() {}
      send() {}
      setRequestHeader() {}
      addEventListener() {}
      removeEventListener() {}
      overrideMimeType() {}
    },
    document: { readyState: 'complete', documentElement: { setAttribute() {} } },
  };
  sandbox2.unsafeWindow = sandbox2.window;
  let vcodeHeaders = null;
  sandbox2.GM_xmlhttpRequest = (details) => {
    if (details.url.includes('/publicinfo/sysparam.do')) {
      probeAttempt++;
      if (probeAttempt === 1) throw new Error('boom');
      if (probeAttempt === 2) { setTimeout(() => details.onabort(), 0); return {}; }
      if (probeAttempt === 3) { setTimeout(() => details.onerror(), 0); return {}; }
      // Second wave succeeds!
      setTimeout(() => details.onload({
        status: 200,
        statusText: 'OK',
        finalUrl: details.url,
        responseHeaders: 'set-cookie: route=healthy123; Path=/\r\n',
        responseText: '{"code":"1","data":{"initTimestamp":"1792144680028"}}',
      }), 0);
      return {};
    }
    vcodeHeaders = details.headers;
    setTimeout(() => details.onload({
      status: 200,
      statusText: 'OK',
      finalUrl: details.url,
      responseHeaders: 'content-type: application/json',
      responseText: '{"code":"1","data":{"token":"t"}}',
    }), 0);
    return {};
  };
  vm.runInNewContext(source, sandbox2);

  const callVcode = () => new Promise((resolve) => {
    const x = new sandbox2.window.XMLHttpRequest();
    x.open('GET', 'https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/student/4/vcode.do', true);
    x.onload = () => resolve(true);
    x.onerror = () => resolve(false);
    x.send(null);
  });

  // First call: all 3 probes fail (throw/abort/error), should still complete without deadlocking
  assert.equal(await callVcode(), true);
  assert.equal(probeAttempt, 3);
  // Second call: because bksxkRouteReady stayed false, it re-probes and pins healthy123
  assert.equal(await callVcode(), true);
  assert.equal(probeAttempt, 6);
  assert.equal(vcodeHeaders.Cookie, 'route=healthy123');
}

console.log('All 14 web bridge tests passed.');
