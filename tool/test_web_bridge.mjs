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
assert.equal(sandbox.window.__bksxkBridgeVersion, '1.5.0');
assert.equal(sandbox.window.__bksxkCasLoginBridgeReady, true);
assert.equal(attrs['data-bksxk-bridge-version'], '1.5.0');
assert.equal(attrs['data-bksxk-cas-login-bridge-ready'], 'true');

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

console.log('All 11 web bridge tests passed.');
