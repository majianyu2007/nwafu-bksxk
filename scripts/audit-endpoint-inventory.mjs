import { readdir, readFile, stat, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const args = process.argv.slice(2);
const checkOnly = args.includes('--check');
const jsonOutputPath = 'docs/endpoint-inventory.audit.generated.json';
const markdownOutputPath = 'docs/endpoint-inventory.audit.generated.md';

const staticSnapshotRoot = path.join(root, 'static-snapshot');
const runtimeLogPath = path.join(root, 'artifacts', 'latest', 'network.jsonl');
const apiManifestPath = 'docs/api.manifest.generated.json';
const pageManifestPath = 'docs/page.manifest.generated.json';
const siteMapPath = 'docs/site-map.generated.json';
const contractPath = 'docs/client.contract.generated.json';
const assetManifestPath = 'docs/static-assets.manifest.generated.json';

const endpointLiteralPattern = /(['"`])([^'"`]*\.do(?:\?[^'"`]*)?)\1/g;
const dangerousStateChangingPattern = /\/(?:elective\/(?:volunteer|deleteVolunteer|submit\/unsuccessful)|textbook\/(?:addbook|modifybook)|student\/(?:xklcqr|logout|authlogout|register))\.do\b/i;
const textExtensions = new Set(['.css', '.html', '.js', '.json', '.md', '.txt']);

function toPosix(value) {
  return value.split(path.sep).join('/');
}

function relativeToRoot(filePath) {
  return toPosix(path.relative(root, filePath));
}

async function readJson(filePath) {
  return JSON.parse(await readFile(path.join(root, filePath), 'utf8'));
}

async function collectFiles(entryPath, out = []) {
  let info;
  try {
    info = await stat(entryPath);
  } catch {
    return out;
  }

  if (info.isDirectory()) {
    const entries = await readdir(entryPath);
    for (const entry of entries.sort()) {
      if (entry === '.DS_Store') continue;
      await collectFiles(path.join(entryPath, entry), out);
    }
    return out;
  }

  if (info.isFile()) out.push(entryPath);
  return out;
}

function stripQuery(value) {
  return String(value).split('?')[0];
}

function normalizeEndpointPath(value) {
  if (!value) return '';
  let raw = String(value).trim();

  try {
    const url = new URL(raw);
    raw = url.pathname;
  } catch {
    // Not an absolute URL.
  }

  raw = raw
    .replace(/^https:\/\/bksxk\.nwafu\.edu\.cn\/xsxkapp/i, '')
    .replace(/^https:\/\/bksxk\.nwafu\.edu\.cn/i, '')
    .replace(/^\/xsxkapp(?=\/sys\/xsxkapp\/)/, '')
    .replace(/^\.\/+/, './');

  if (raw.startsWith('./')) return stripQuery(raw);

  raw = stripQuery(raw)
    .replace(/%3CstudentCode%3E/gi, '<studentCode>')
    .replace(/%3Credacted%3E/gi, '<redacted>')
    .replace(/(\/student\/)(?:\d+|<redacted>|\{e\}|\{e\.code\}|\{studentInfo\.code\}|e|\{studentCode\})(\.do\b)/gi, '$1<studentCode>$2')
    .replace(/\/publicinfo\/(fx|zx)\/\{type\}\.do\b/gi, '/publicinfo/$1/<type>.do')
    .replace(/\/publicinfo\/queryjzg\.do$/i, '/publicinfo/queryjzg.do');

  return raw;
}

function endpointIdentity(method, endpoint) {
  return `${String(method || '').toUpperCase()} ${normalizeEndpointPath(endpoint)}`;
}

function isBusinessEndpoint(pathname) {
  return pathname.startsWith('/sys/xsxkapp/') || pathname.startsWith('./');
}

function isPageEndpoint(pathname) {
  return pathname.startsWith('./') || pathname.includes('/sys/xsxkapp/*default/');
}

function isDynamicDictionaryCovered(pathname, apiPaths) {
  const match = pathname.match(/^\/sys\/xsxkapp\/publicinfo\/(fx|zx)\/<type>\.do$/i);
  if (!match) return false;
  const prefix = `/sys/xsxkapp/publicinfo/${match[1].toLowerCase()}`;
  return ['nj', 'yx', 'zy'].every((item) => apiPaths.has(`${prefix}/${item}.do`));
}

function isPathCovered(pathname, apiPaths, pagePaths) {
  if (apiPaths.has(pathname) || pagePaths.has(pathname)) return true;
  return isDynamicDictionaryCovered(pathname, apiPaths);
}

function lineOf(text, index) {
  let line = 1;
  for (let i = 0; i < index; i += 1) {
    if (text.charCodeAt(i) === 10) line += 1;
  }
  return line;
}

async function collectStaticLiteralReferences() {
  const files = (await collectFiles(staticSnapshotRoot))
    .filter((filePath) => textExtensions.has(path.extname(filePath).toLowerCase()));
  const references = [];
  const seen = new Set();

  for (const filePath of files.sort()) {
    const text = await readFile(filePath, 'utf8');
    endpointLiteralPattern.lastIndex = 0;
    for (const match of text.matchAll(endpointLiteralPattern)) {
      const pathname = normalizeEndpointPath(match[2]);
      if (!isBusinessEndpoint(pathname)) continue;
      const key = `${pathname}|${relativeToRoot(filePath)}|${lineOf(text, match.index || 0)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      references.push({
        endpoint: pathname,
        source: relativeToRoot(filePath),
        line: lineOf(text, match.index || 0),
      });
    }
  }

  return references.sort((a, b) => `${a.endpoint} ${a.source}:${a.line}`.localeCompare(`${b.endpoint} ${b.source}:${b.line}`));
}

async function collectRuntimeRequests() {
  let raw;
  try {
    raw = await readFile(runtimeLogPath, 'utf8');
  } catch {
    return [];
  }

  const requests = [];
  const seen = new Map();
  for (const line of raw.split(/\r?\n/).filter(Boolean)) {
    let record;
    try {
      record = JSON.parse(line);
    } catch {
      continue;
    }
    if (record.type !== 'request') continue;

    const rawPath = record.urlSummary?.path || '';
    const pathname = normalizeEndpointPath(rawPath);
    if (!pathname.includes('.do') || !pathname.startsWith('/sys/xsxkapp/')) continue;

    const method = String(record.method || 'GET').toUpperCase();
    const key = endpointIdentity(method, pathname);
    const existing = seen.get(key) || {
      method,
      endpoint: pathname,
      count: 0,
      blockedCount: 0,
      statuses: new Set(),
      resourceTypes: new Set(),
    };
    existing.count += 1;
    if (record.status === 'blocked') existing.blockedCount += 1;
    if (record.status) existing.statuses.add(record.status);
    if (record.resourceType) existing.resourceTypes.add(record.resourceType);
    seen.set(key, existing);
  }

  for (const item of seen.values()) {
    requests.push({
      method: item.method,
      endpoint: item.endpoint,
      count: item.count,
      blockedCount: item.blockedCount,
      statuses: [...item.statuses].sort(),
      resourceTypes: [...item.resourceTypes].sort(),
    });
  }

  return requests.sort((a, b) => endpointIdentity(a.method, a.endpoint).localeCompare(endpointIdentity(b.method, b.endpoint)));
}

function uniqueEndpoints(records) {
  return [...new Set(records.map((record) => normalizeEndpointPath(record.endpoint)).filter(Boolean))].sort();
}

function countBy(items, select) {
  const out = {};
  for (const item of items) {
    const key = select(item);
    out[key] = (out[key] || 0) + 1;
  }
  return out;
}

function markdownTable(rows, columns) {
  if (rows.length === 0) return ['_None._'];
  return [
    `| ${columns.map((column) => column.title).join(' | ')} |`,
    `| ${columns.map(() => '---').join(' | ')} |`,
    ...rows.map((row) => `| ${columns.map((column) => column.render(row)).join(' | ')} |`),
  ];
}

function esc(value) {
  return String(value == null ? '' : value).replace(/\|/g, '\\|').replace(/\n/g, ' ');
}

const [apiManifest, pageManifest, siteMap, contract, assetManifest] = await Promise.all([
  readJson(apiManifestPath),
  readJson(pageManifestPath),
  readJson(siteMapPath),
  readJson(contractPath),
  readJson(assetManifestPath),
]);

const apiPaths = new Set(apiManifest.endpoints.map((endpoint) => normalizeEndpointPath(endpoint.endpoint)));
const pagePaths = new Set(pageManifest.pages.map((page) => normalizeEndpointPath(page.endpoint)));
const apiIdentities = new Set(apiManifest.endpoints.map((endpoint) => endpointIdentity(endpoint.method, endpoint.endpoint)));
const staticLiteralReferences = await collectStaticLiteralReferences();
const runtimeRequests = await collectRuntimeRequests();

const staticLiteralEndpoints = uniqueEndpoints(staticLiteralReferences);
const siteMapApiPaths = uniqueEndpoints(siteMap.apis);
const siteMapPagePaths = uniqueEndpoints(siteMap.pages);
const runtimeIdentities = new Set(runtimeRequests.map((request) => endpointIdentity(request.method, request.endpoint)));

const missingStaticLiteralCoverage = staticLiteralEndpoints
  .filter((endpoint) => !isPathCovered(endpoint, apiPaths, pagePaths))
  .map((endpoint) => ({
    endpoint,
    sources: staticLiteralReferences
      .filter((reference) => reference.endpoint === endpoint)
      .slice(0, 5)
      .map((reference) => `${reference.source}:${reference.line}`),
  }));

const missingSiteMapApiCoverage = siteMapApiPaths
  .filter((endpoint) => !isPathCovered(endpoint, apiPaths, pagePaths))
  .map((endpoint) => ({ endpoint }));

const missingSiteMapPageCoverage = siteMapPagePaths
  .filter((endpoint) => !pagePaths.has(endpoint))
  .map((endpoint) => ({ endpoint }));

const missingRuntimeCoverage = [...runtimeIdentities]
  .filter((identity) => !apiIdentities.has(identity))
  .map((identity) => {
    const [method, ...endpointParts] = identity.split(' ');
    return { method, endpoint: endpointParts.join(' ') };
  });

const dangerousStateChangingMismatches = apiManifest.endpoints
  .filter((endpoint) => dangerousStateChangingPattern.test(endpoint.endpoint) && !endpoint.stateChanging)
  .map((endpoint) => ({
    method: endpoint.method,
    endpoint: endpoint.endpoint,
    id: endpoint.id,
  }));

const contractMismatches = [];
if (contract.endpointCount !== apiManifest.endpointCount) {
  contractMismatches.push(`contract endpointCount ${contract.endpointCount} != manifest endpointCount ${apiManifest.endpointCount}`);
}
if (contract.pageCount !== pageManifest.pageCount) {
  contractMismatches.push(`contract pageCount ${contract.pageCount} != page manifest pageCount ${pageManifest.pageCount}`);
}
if (contract.siteMapStats?.apiRows !== siteMap.apis.length) {
  contractMismatches.push(`contract siteMapStats.apiRows ${contract.siteMapStats?.apiRows} != site-map apis ${siteMap.apis.length}`);
}
if (contract.siteMapStats?.pageRows !== siteMap.pages.length) {
  contractMismatches.push(`contract siteMapStats.pageRows ${contract.siteMapStats?.pageRows} != site-map pages ${siteMap.pages.length}`);
}

const failures = {
  missingStaticLiteralCoverage,
  missingSiteMapApiCoverage,
  missingSiteMapPageCoverage,
  missingRuntimeCoverage,
  dangerousStateChangingMismatches,
  contractMismatches,
};

const pass = Object.values(failures).every((items) => items.length === 0);

const output = {
  schemaVersion: 1,
  generatedFrom: [
    'static-snapshot/',
    runtimeLogPath.replace(`${root}${path.sep}`, ''),
    apiManifestPath,
    pageManifestPath,
    siteMapPath,
    contractPath,
    assetManifestPath,
  ],
  scope: {
    staticSnapshot: 'All persisted text resources under static-snapshot are scanned for literal .do references.',
    staticCallGraph: 'docs/site-map.generated.json records reconstructed BH_UTILS and jQuery AJAX calls from the persisted app static scripts.',
    runtime: 'artifacts/latest/network.jsonl is checked when present; state-changing endpoints are not executed for response capture.',
    contract: 'docs/client.contract.generated.json must stay aligned with manifest, response schemas, requests, and page manifest.',
  },
  summary: {
    apiManifestEndpoints: apiManifest.endpointCount,
    pageManifestEntries: pageManifest.pageCount,
    clientContractEndpoints: contract.endpointCount,
    clientContractPages: contract.pageCount,
    siteMapApiRows: siteMap.apis.length,
    siteMapPageRows: siteMap.pages.length,
    siteMapFunctionRows: siteMap.functions.length,
    staticAssetFiles: assetManifest.assetCount,
    staticLiteralEndpoints: staticLiteralEndpoints.length,
    runtimeRequestIdentities: runtimeRequests.length,
    stateChangingEndpoints: apiManifest.endpoints.filter((endpoint) => endpoint.stateChanging).length,
    byEndpointStatus: countBy(apiManifest.endpoints, (endpoint) => endpoint.status),
    byResponseAvailability: countBy(contract.endpointContract, (endpoint) => endpoint.response.availability),
  },
  runtimeRequests,
  staticLiteralEndpointSources: staticLiteralEndpoints.map((endpoint) => ({
    endpoint,
    sources: staticLiteralReferences
      .filter((reference) => reference.endpoint === endpoint)
      .map((reference) => `${reference.source}:${reference.line}`),
  })),
  failures,
};

const jsonSerialized = `${JSON.stringify(output, null, 2)}\n`;
const mdLines = [
  '# BKSXK 端点库存审计',
  '',
  '这份报告核对持久化静态快照、运行期网络日志、覆盖矩阵和 Go 客户端合同之间的端点一致性。',
  '',
  '## 范围',
  '',
  '- `static-snapshot/` 下所有文本资源都会扫描字面量 `.do` 引用。',
  '- `docs/site-map.generated.json` 提供从业务脚本重建出的 `BH_UTILS` / jQuery AJAX 调用和页面入口。',
  '- `artifacts/latest/network.jsonl` 存在时会核对运行期请求是否进入覆盖矩阵。',
  '- 添加选课、退选、教材订退、确认、退出等状态变更接口只验证前端调用链和本地构造，不执行真实提交。',
  '',
  '## 统计',
  '',
  ...markdownTable(
    Object.entries(output.summary).map(([name, value]) => ({ name, value: typeof value === 'object' ? JSON.stringify(value) : value })),
    [
      { title: '项目', render: (row) => `\`${esc(row.name)}\`` },
      { title: '值', render: (row) => `\`${esc(row.value)}\`` },
    ],
  ),
  '',
  '## 审计结果',
  '',
  pass ? '当前审计通过：未发现静态快照、运行期日志、覆盖矩阵和客户端合同之间的端点缺口。' : '当前审计未通过，缺口如下。',
  '',
  '### 静态字面量未覆盖',
  '',
  ...markdownTable(missingStaticLiteralCoverage, [
    { title: '端点', render: (row) => `\`${esc(row.endpoint)}\`` },
    { title: '来源', render: (row) => row.sources.map((item) => `\`${esc(item)}\``).join(', ') },
  ]),
  '',
  '### 站点地图 API 未覆盖',
  '',
  ...markdownTable(missingSiteMapApiCoverage, [
    { title: '端点', render: (row) => `\`${esc(row.endpoint)}\`` },
  ]),
  '',
  '### 站点地图页面未覆盖',
  '',
  ...markdownTable(missingSiteMapPageCoverage, [
    { title: '端点', render: (row) => `\`${esc(row.endpoint)}\`` },
  ]),
  '',
  '### 运行期请求未覆盖',
  '',
  ...markdownTable(missingRuntimeCoverage, [
    { title: '方法', render: (row) => `\`${esc(row.method)}\`` },
    { title: '端点', render: (row) => `\`${esc(row.endpoint)}\`` },
  ]),
  '',
  '### 状态变更标记异常',
  '',
  ...markdownTable(dangerousStateChangingMismatches, [
    { title: 'ID', render: (row) => `\`${esc(row.id)}\`` },
    { title: '方法', render: (row) => `\`${esc(row.method)}\`` },
    { title: '端点', render: (row) => `\`${esc(row.endpoint)}\`` },
  ]),
  '',
  '### 客户端合同不一致',
  '',
  ...markdownTable(contractMismatches.map((message) => ({ message })), [
    { title: '问题', render: (row) => esc(row.message) },
  ]),
  '',
];

const mdSerialized = `${mdLines.join('\n')}\n`;

if (checkOnly) {
  const [currentJson, currentMd] = await Promise.all([
    readFile(jsonOutputPath, 'utf8'),
    readFile(markdownOutputPath, 'utf8'),
  ]);
  if (currentJson !== jsonSerialized || currentMd !== mdSerialized) {
    console.error('Endpoint inventory audit files are stale. Run: npm run endpoint-audit');
    process.exit(1);
  }
  if (!pass) {
    console.error('Endpoint inventory audit failed. See docs/endpoint-inventory.audit.generated.md.');
    process.exit(1);
  }
  console.log(`Endpoint inventory audit passed: ${apiManifest.endpointCount} API endpoints, ${pageManifest.pageCount} pages, ${assetManifest.assetCount} static files.`);
} else {
  await mkdir(path.dirname(jsonOutputPath), { recursive: true });
  await Promise.all([
    writeFile(jsonOutputPath, jsonSerialized),
    writeFile(markdownOutputPath, mdSerialized),
  ]);
  if (!pass) {
    console.error('Endpoint inventory audit failed. See docs/endpoint-inventory.audit.generated.md.');
    process.exit(1);
  }
  console.log(`Wrote ${jsonOutputPath}`);
  console.log(`Wrote ${markdownOutputPath}`);
}
