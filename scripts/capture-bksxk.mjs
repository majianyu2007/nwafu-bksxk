import { chromium } from 'playwright';
import { createInterface } from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import { copyFile, mkdir, rm, symlink, writeFile, appendFile } from 'node:fs/promises';
import path from 'node:path';

const TARGET_URL = process.env.BKSXK_URL || 'https://bksxk.nwafu.edu.cn';
const ROOT = process.cwd();
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const runDir = path.join(ROOT, 'artifacts', 'runs', stamp);
const latestLink = path.join(ROOT, 'artifacts', 'latest');
const networkLog = path.join(runDir, 'network.jsonl');
const blockedLog = path.join(runDir, 'blocked-requests.jsonl');
const guardEventsLog = path.join(runDir, 'guard-events.jsonl');
const snapshotDir = path.join(runDir, 'snapshot');
const userDataDir = path.join(runDir, 'chromium-profile');
const guardScriptPath = path.join(ROOT, 'userscripts', 'bksxk-guard.user.js');
const extensionDir = path.join(ROOT, 'extensions', 'bksxk-guard');
const extensionScriptPath = path.join(extensionDir, 'bksxk-guard.user.js');

const writeRequestText = /退选|选课|退课|志愿|提交|保存|确认|撤销|withdraw|drop|choose|select|submit|save|confirm|delete|remove|cancel/i;
const sensitiveHeader = /cookie|authorization|token|csrf|xsrf|ticket|session|set-cookie/i;
const sensitiveKey = /pass|pwd|password|token|csrf|xsrf|cookie|authorization|session|ticket|sid|secret|credential|execution|lt|学号|xh|student/i;

const guard = {
  blockUntil: 0,
  reason: '',
};

function safeDecode(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function redactScalar(value, key = '') {
  if (sensitiveKey.test(key)) {
    return '<redacted>';
  }

  if (typeof value !== 'string') {
    return value;
  }

  return value
    .replace(/((?:pass|pwd|password)\s*[=:]\s*)[^&\s"]+/gi, '$1<redacted>')
    .replace(/((?:token|csrf|xsrf|ticket|session|sid)\s*[=:]\s*)[^&\s"]+/gi, '$1<redacted>');
}

function sanitizeObject(value) {
  if (Array.isArray(value)) {
    return value.map((item) => sanitizeObject(item));
  }

  if (value && typeof value === 'object') {
    const out = {};
    for (const [key, item] of Object.entries(value)) {
      out[key] = sensitiveKey.test(key) ? '<redacted>' : sanitizeObject(item);
    }
    return out;
  }

  return redactScalar(value);
}

function sanitizeHeaders(headers) {
  const out = {};
  for (const [key, value] of Object.entries(headers || {})) {
    out[key] = sensitiveHeader.test(key) ? '<redacted>' : value;
  }
  return out;
}

function parseBody(postData, contentType = '') {
  if (!postData) {
    return null;
  }

  if (contentType.includes('application/json')) {
    try {
      return sanitizeObject(JSON.parse(postData));
    } catch {
      return redactScalar(postData);
    }
  }

  if (
    contentType.includes('application/x-www-form-urlencoded') ||
    postData.includes('=') ||
    postData.includes('&')
  ) {
    try {
      const params = new URLSearchParams(postData);
      const out = {};
      for (const [key, value] of params.entries()) {
        if (Object.hasOwn(out, key)) {
          out[key] = Array.isArray(out[key]) ? [...out[key], redactScalar(value, key)] : [out[key], redactScalar(value, key)];
        } else {
          out[key] = redactScalar(value, key);
        }
      }
      return out;
    } catch {
      return redactScalar(postData);
    }
  }

  return redactScalar(postData);
}

function summarizeUrl(rawUrl) {
  const url = new URL(rawUrl);
  return {
    origin: url.origin,
    path: url.pathname,
    queryKeys: [...url.searchParams.keys()],
  };
}

async function logJsonl(file, record) {
  await appendFile(file, `${JSON.stringify(record)}\n`, 'utf8');
}

function requestRecord(request, status = 'sent') {
  const headers = request.headers();
  return {
    ts: new Date().toISOString(),
    type: 'request',
    status,
    method: request.method(),
    resourceType: request.resourceType(),
    url: request.url(),
    urlSummary: summarizeUrl(request.url()),
    headers: sanitizeHeaders(headers),
    postData: parseBody(request.postData(), headers['content-type'] || ''),
  };
}

function shouldBlock(routeRequest) {
  const method = routeRequest.method().toUpperCase();
  if (method === 'GET' || method === 'HEAD' || method === 'OPTIONS') {
    return false;
  }

  const resourceType = routeRequest.resourceType();
  if (!['xhr', 'fetch', 'document'].includes(resourceType)) {
    return false;
  }

  if (Date.now() < guard.blockUntil) {
    return true;
  }

  const decodedUrl = safeDecode(routeRequest.url());
  const body = routeRequest.postData() || '';
  return writeRequestText.test(decodedUrl) || writeRequestText.test(safeDecode(body));
}

async function main() {
  await mkdir(snapshotDir, { recursive: true });
  await mkdir(extensionDir, { recursive: true });
  await copyFile(guardScriptPath, extensionScriptPath);
  await rm(latestLink, { force: true, recursive: true }).catch(() => {});
  await symlink(runDir, latestLink, 'dir').catch(() => {});

  const context = await chromium.launchPersistentContext(userDataDir, {
    headless: false,
    viewport: { width: 1440, height: 950 },
    ignoreHTTPSErrors: true,
    args: [
      `--disable-extensions-except=${extensionDir}`,
      `--load-extension=${extensionDir}`,
    ],
  });

  await context.exposeBinding('__bksxkGuardReport', async (_source, record) => {
    await logJsonl(guardEventsLog, record);
    if (record.type === 'request' || record.type === 'response') {
      await logJsonl(networkLog, record);
    }
    if (record.type === 'guard-armed') {
      guard.blockUntil = Date.parse(record.blockUntil) || Date.now() + 20_000;
      guard.reason = record.reason || 'userscript guard';
      await logJsonl(blockedLog, record);
    }
    if (record.status === 'blocked') {
      await logJsonl(blockedLog, record);
    }
  });

  await context.addInitScript({ path: guardScriptPath });

  await context.route('**/*', async (route) => {
    const request = route.request();
    if (shouldBlock(request)) {
      const record = requestRecord(request, 'blocked');
      record.guardReason = guard.reason || 'request keyword matched';
      await logJsonl(networkLog, record);
      await logJsonl(blockedLog, record);
      await route.abort('blockedbyclient');
      return;
    }

    await logJsonl(networkLog, requestRecord(request));
    await route.continue();
  });

  const page = context.pages()[0] || await context.newPage();

  page.on('response', async (response) => {
    const request = response.request();
    const record = {
      ts: new Date().toISOString(),
      type: 'response',
      method: request.method(),
      resourceType: request.resourceType(),
      url: response.url(),
      urlSummary: summarizeUrl(response.url()),
      status: response.status(),
      headers: sanitizeHeaders(response.headers()),
    };

    const contentType = response.headers()['content-type'] || '';
    if (['xhr', 'fetch'].includes(request.resourceType()) && /json|text|javascript|html|plain/.test(contentType)) {
      try {
        const body = await response.text();
        record.bodyPreview = body.length > 200_000 ? `${body.slice(0, 200_000)}\n<truncated ${body.length - 200_000} chars>` : body;
      } catch {
        record.bodyPreview = '<unavailable>';
      }
    }

    await logJsonl(networkLog, record);
  });

  page.on('requestfailed', async (request) => {
    await logJsonl(networkLog, {
      ...requestRecord(request, 'failed'),
      failure: request.failure()?.errorText,
    });
  });

  await page.goto(TARGET_URL, { waitUntil: 'domcontentloaded' });
  console.log(`Opened ${TARGET_URL}`);
  console.log(`Run artifacts: ${runDir}`);
  console.log('Userscript guard is active. Log in manually in the browser.');
  console.log('Press Enter here when you want to save the current snapshot and close.');

  const rl = createInterface({ input, output });
  await rl.question('');
  rl.close();

  await page.screenshot({ path: path.join(snapshotDir, 'page.png'), fullPage: true });
  await writeFile(path.join(snapshotDir, 'dom.html'), await page.content(), 'utf8');
  await writeFile(
    path.join(runDir, 'summary.json'),
    JSON.stringify(
      {
        targetUrl: TARGET_URL,
        capturedAt: new Date().toISOString(),
        runDir,
        networkLog,
        blockedLog,
        guardEventsLog,
        snapshotDir,
      },
      null,
      2,
    ),
    'utf8',
  );

  await context.close();
  console.log(`Saved snapshot to ${snapshotDir}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
