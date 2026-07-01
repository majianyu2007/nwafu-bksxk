import { readdir, readFile, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const runDir = process.argv[2] || path.join(root, 'artifacts', 'latest');
const files = ['network.jsonl', 'guard-events.jsonl', 'blocked-requests.jsonl'];
const sensitiveKey = /pass|pwd|password|token|csrf|xsrf|cookie|authorization|session|ticket|sid|secret|credential|execution|lt|学号|xh|student|studentCode|userid|username|account|login|loginName|verifyCode|vtoken/i;

function safeDecode(value) {
  try {
    return decodeURIComponent(String(value || ''));
  } catch {
    return String(value || '');
  }
}

function redactScalar(value, key = '') {
  if (sensitiveKey.test(key)) return '<redacted>';
  if (typeof value !== 'string') return value;
  return value
    .replace(/"((?:pass|pwd|password|token|csrf|xsrf|ticket|session|sid|userid|username|account|loginName|studentCode|verifyCode|vtoken|xh))"\s*:\s*"[^"]*"/gi, '"$1":"<redacted>"')
    .replace(/((?:pass|pwd|password)\s*[=:]\s*)[^&\s"]+/gi, '$1<redacted>')
    .replace(/((?:token|csrf|xsrf|ticket|session|sid|userid|username|account|loginName|studentCode|verifyCode|vtoken|xh)\s*[=:]\s*)[^&\s"]+/gi, '$1<redacted>');
}

function redactUrl(rawUrl) {
  const text = String(rawUrl || '');
  const hashSplit = text.split('#');
  const main = hashSplit[0];
  const hash = hashSplit.length > 1 ? `#${hashSplit.slice(1).join('#')}` : '';
  const queryIndex = main.indexOf('?');
  const redactPath = (value) => value.replace(/(\/student\/)\d+(\.do\b)/i, '$1<redacted>$2');
  if (queryIndex < 0) return redactPath(text);

  const base = redactPath(main.slice(0, queryIndex));
  const query = main.slice(queryIndex + 1);
  const redactedQuery = query
    .split('&')
    .map((part) => {
      if (!part) return part;
      const splitAt = part.indexOf('=');
      const rawKey = splitAt >= 0 ? part.slice(0, splitAt) : part;
      const rawValue = splitAt >= 0 ? part.slice(splitAt + 1) : '';
      const key = safeDecode(rawKey);
      const value = sensitiveKey.test(key) ? '<redacted>' : redactScalar(safeDecode(rawValue), key);
      return splitAt >= 0 ? `${rawKey}=${encodeURIComponent(value)}` : rawKey;
    })
    .join('&');
  return `${base}?${redactedQuery}${hash}`;
}

function sanitize(value, key = '') {
  if (key === 'url' || key === 'pageUrl') return redactUrl(value);
  if (key === 'path') return String(value || '').replace(/(\/student\/)\d+(\.do\b)/i, '$1<redacted>$2');
  if (Array.isArray(value)) return value.map((item) => sanitize(item));
  if (value && typeof value === 'object') {
    const out = {};
    for (const [childKey, childValue] of Object.entries(value)) {
      out[childKey] = sensitiveKey.test(childKey) ? '<redacted>' : sanitize(childValue, childKey);
    }
    return out;
  }
  return redactScalar(value, key);
}

for (const file of files) {
  const filePath = path.join(runDir, file);
  let raw;
  try {
    raw = await readFile(filePath, 'utf8');
  } catch {
    continue;
  }

  const lines = raw
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.stringify(sanitize(JSON.parse(line))));
  await writeFile(filePath, `${lines.join('\n')}\n`, 'utf8');
  console.log(`Sanitized ${path.relative(root, filePath)}`);
}

const textExtensions = new Set(['.json', '.jsonl', '.md', '.txt', '.yml', '.yaml']);
const textDirs = ['network', 'pages', 'snapshot'];

function redactText(raw) {
  let out = redactScalar(raw);
  out = out
    .replace(/(studentCode%22%3A%22)[^%&"]+(%22)/gi, '$1%3Credacted%3E$2')
    .replace(/(xh%22%3A%22)[^%&"]+(%22)/gi, '$1%3Credacted%3E$2')
    .replace(/(loginName=)[^&\s]+/gi, '$1<redacted>')
    .replace(/(loginPwd=)[^&\s]+/gi, '$1<redacted>')
    .replace(/(verifyCode=)[^&\s]+/gi, '$1<redacted>')
    .replace(/(vtoken=)[^&\s]+/gi, '$1<redacted>')
    .replace(/(token:\s*)[0-9a-f-]{20,}/gi, '$1<redacted>')
    .replace(/(token=)[0-9a-f-]{20,}/gi, '$1<redacted>')
    .replace(/(\/student\/)\d+(\.do\b)/gi, '$1<redacted>$2')
    .replace(/(学生:)\d+/g, '$1<redacted>')
    .replace(/(studentCode=)\d+/gi, '$1<redacted>')
    .replace(/(xh=)\d+/gi, '$1<redacted>');
  return out;
}

async function sanitizeTextTree(dir) {
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    const entryPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      await sanitizeTextTree(entryPath);
      continue;
    }
    if (!entry.isFile() || !textExtensions.has(path.extname(entry.name))) continue;

    const info = await stat(entryPath);
    if (info.size > 10 * 1024 * 1024) continue;

    const raw = await readFile(entryPath, 'utf8');
    const sanitized = redactText(raw);
    if (sanitized !== raw) {
      await writeFile(entryPath, sanitized, 'utf8');
      console.log(`Sanitized ${path.relative(root, entryPath)}`);
    }
  }
}

for (const dir of textDirs) {
  await sanitizeTextTree(path.join(runDir, dir));
}
