import { readFile } from 'node:fs/promises';

const siteMapPath = 'docs/site-map.generated.md';
const coveragePath = 'docs/api.coverage.md';

function between(text, startMarker, endMarker) {
  const start = text.indexOf(startMarker);
  if (start < 0) {
    throw new Error(`Cannot find section marker: ${startMarker}`);
  }
  const afterStart = text.slice(start + startMarker.length);
  const end = afterStart.indexOf(endMarker);
  if (end < 0) {
    throw new Error(`Cannot find section marker: ${endMarker}`);
  }
  return afterStart.slice(0, end);
}

function normalizeEndpoint(value) {
  return String(value)
    .split('?')[0]
    .replace(/\/sys\/xsxkapp\/student\/\{(?:e|e\.code|studentInfo\.code|studentCode)\}\.do/g, '/sys/xsxkapp/student/<studentCode>.do')
    .replace(/\/sys\/xsxkapp\/student\/(?:<redacted>|\d+)\.do/g, '/sys/xsxkapp/student/<studentCode>.do')
    .replace(/\/sys\/xsxkapp\/publicinfo\/(fx|zx)\/\{type\}\.do/g, '/sys/xsxkapp/publicinfo/$1/<type>.do')
    .trim();
}

function parseRows(markdown, format) {
  const rows = [];
  for (const line of markdown.split(/\r?\n/)) {
    if (!line.startsWith('|')) continue;
    const cells = line.split('|').slice(1, -1).map((cell) => cell.trim());
    if (cells.length < 4 || cells.every((cell) => /^-+$/.test(cell))) continue;

    const methodCell = format === 'site-map' ? cells[1] : cells[1];
    const endpointCell = format === 'site-map' ? cells[0] : cells[2];
    const endpointMatch = endpointCell.match(/`([^`]+\.do(?:\?[^`]*)?)`/);
    if (!endpointMatch) continue;

    const endpoint = normalizeEndpoint(endpointMatch[1]);
    if (!endpoint.startsWith('/sys/xsxkapp/')) continue;

    const method = /^(GET|POST)$/i.test(methodCell) ? methodCell.toUpperCase() : '';
    rows.push({ method, endpoint });
  }
  return rows;
}

function identity(row) {
  return `${row.method} ${row.endpoint}`;
}

function hasDynamicDictionaryCoverage(endpoint, covered) {
  const match = endpoint.match(/^\/sys\/xsxkapp\/publicinfo\/(fx|zx)\/<type>\.do$/);
  if (!match) return false;

  const prefix = `/sys/xsxkapp/publicinfo/${match[1]}`;
  return ['nj', 'yx', 'zy'].every((dimension) => covered.has(`${prefix}/${dimension}.do`));
}

const siteMap = await readFile(siteMapPath, 'utf8');
const coverage = await readFile(coveragePath, 'utf8');

const apiSection = between(siteMap, '## API 入口', '## 写操作接口');
const siteMapRows = parseRows(apiSection, 'site-map');
const discoveredRows = siteMapRows.filter((row) => row.method);
const bareDiscoveredRows = siteMapRows.filter((row) => !row.method);
const coveredRows = parseRows(coverage, 'coverage').filter((row) => row.method);
const discovered = new Set(discoveredRows.map(identity));
const covered = new Set(coveredRows.map(identity));
const coveredEndpoints = new Set(coveredRows.map((row) => row.endpoint));

const missingMethodRows = [...discovered]
  .filter((key) => !covered.has(key))
  .filter((key) => {
    const endpoint = key.replace(/^(GET|POST)\s+/, '');
    return !hasDynamicDictionaryCoverage(endpoint, coveredEndpoints);
  })
  .sort();

const missingBareRows = [...new Set(bareDiscoveredRows.map((row) => row.endpoint))]
  .filter((endpoint) => !coveredEndpoints.has(endpoint))
  .filter((endpoint) => !hasDynamicDictionaryCoverage(endpoint, coveredEndpoints))
  .sort();

if (missingMethodRows.length > 0 || missingBareRows.length > 0) {
  if (missingMethodRows.length > 0) {
    console.error('API coverage check failed. Missing method+endpoint rows in docs/api.coverage.md:');
  }
  for (const key of missingMethodRows) {
    console.error(`- ${key}`);
  }

  if (missingBareRows.length > 0) {
    console.error('API coverage check failed. Missing endpoint coverage for static URL references:');
  }
  for (const endpoint of missingBareRows) {
    console.error(`- ${endpoint}`);
  }
  process.exitCode = 1;
} else {
  console.log(`API coverage check passed: ${discovered.size} discovered method+endpoint forms and ${bareDiscoveredRows.length} static URL references are covered.`);
}
