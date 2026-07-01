import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const coveragePath = 'docs/api.coverage.md';
const outputPath = process.argv[2] || 'docs/api.manifest.generated.json';

function slugifyMethod(method) {
  const value = String(method || '').trim();
  return value && value !== '-' ? value.toUpperCase() : 'UNKNOWN';
}

function makeEndpointId(method, endpoint) {
  const methodPart = slugifyMethod(method).toLowerCase();
  const pathPart = endpoint
    .replace(/^\/sys\/xsxkapp\//, '')
    .replace(/<([^>]+)>/g, '$1')
    .replace(/[^A-Za-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .toLowerCase();
  return `${methodPart}_${pathPart}`;
}

function isStateChanging(status, method, endpoint) {
  return /写操作/.test(status)
    || /\/elective\/(?:volunteer|deleteVolunteer|submit\/unsuccessful)\.do\b/i.test(endpoint)
    || /\/textbook\/(?:addbook|modifybook)\.do\b/i.test(endpoint)
    || /\/student\/(?:xklcqr|logout|authlogout|register)\.do\b/i.test(endpoint)
    || (method === 'POST' && /\/student\/guideMap\.do\b/i.test(endpoint));
}

function parseCoverage(markdown) {
  const endpoints = [];
  let section = '';

  for (const line of markdown.split(/\r?\n/)) {
    const sectionMatch = line.match(/^##\s+(.+)$/);
    if (sectionMatch) {
      section = sectionMatch[1].trim();
      continue;
    }

    const rowMatch = line.match(/^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*`([^`]+\.do)`\s*\|\s*([^|]+?)\s*\|$/);
    if (!rowMatch) continue;

    const [, statusRaw, methodRaw, endpointRaw, descriptionRaw] = rowMatch;
    if (statusRaw.trim() === '状态') continue;

    const status = statusRaw.trim();
    const method = slugifyMethod(methodRaw);
    const endpoint = endpointRaw.trim();
    const description = descriptionRaw.trim();

    endpoints.push({
      id: makeEndpointId(method, endpoint),
      section,
      status,
      method,
      endpoint,
      description,
      stateChanging: isStateChanging(status, method, endpoint),
    });
  }

  return endpoints;
}

const coverage = await readFile(coveragePath, 'utf8');
const endpoints = parseCoverage(coverage);
const ids = new Set();
const duplicates = [];

for (const endpoint of endpoints) {
  if (ids.has(endpoint.id)) duplicates.push(endpoint.id);
  ids.add(endpoint.id);
}

if (duplicates.length > 0) {
  throw new Error(`Duplicate endpoint ids: ${duplicates.join(', ')}`);
}

const manifest = {
  schemaVersion: 1,
  generatedFrom: [coveragePath],
  endpointCount: endpoints.length,
  statusLegend: {
    '运行期已验证': '登录态中只读调用过，已有响应字段或摘要。',
    '静态已定位': '前端脚本确认调用点和参数构造，但没有完整运行期响应样例。',
    '静态残留': '脚本里有函数或字符串，当前部署或当前流程不可用，已记录验证结果。',
    '写操作未执行': '会改变正式系统状态，只整理参数和调用链。',
    '待复现': '静态源码存在，但当前参数或流程尚未成功复现。',
  },
  endpoints,
};

await mkdir(path.dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Wrote ${outputPath} with ${endpoints.length} endpoints.`);
