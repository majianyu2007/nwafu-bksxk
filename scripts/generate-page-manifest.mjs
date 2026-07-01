import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const args = process.argv.slice(2);
const checkOnly = args.includes('--check');
const outputPath = args.find((arg) => arg !== '--check') || 'docs/page.manifest.generated.json';
const siteMapPath = 'docs/site-map.generated.json';

function pageId(endpoint) {
  return String(endpoint)
    .replace(/^\.\//, 'fragment/')
    .replace(/^\/sys\/xsxkapp\/\*default\//, 'default/')
    .replace(/[?#].*$/, '')
    .replace(/\.do$/, '')
    .replace(/[^A-Za-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .toLowerCase();
}

function classifyPage(endpoint) {
  if (endpoint.startsWith('./')) return 'fragment';
  if (/\/(?:course|jc|js|score|content|publicinfo)/i.test(endpoint)) return 'detail-page';
  if (/curriculum/i.test(endpoint)) return 'curriculum-page';
  if (/grablessons|index/i.test(endpoint)) return 'primary-page';
  return 'page';
}

function routeParams(endpoint) {
  const query = endpoint.split('?')[1] || '';
  return query
    .split('&')
    .filter(Boolean)
    .map((part) => part.split('=')[0])
    .filter(Boolean);
}

function normalizePage(record) {
  return {
    id: pageId(record.endpoint),
    endpoint: record.endpoint,
    kind: classifyPage(record.endpoint),
    method: record.method || 'GET',
    routeParams: routeParams(record.endpoint),
    source: `${record.source}:${record.line}`,
    functionName: record.functionName || '',
  };
}

const siteMap = JSON.parse(await readFile(siteMapPath, 'utf8'));
const pages = siteMap.pages.map(normalizePage);
const ids = new Set();
const duplicates = [];

for (const page of pages) {
  if (ids.has(page.id)) duplicates.push(page.id);
  ids.add(page.id);
}

if (duplicates.length > 0) {
  throw new Error(`Duplicate page ids: ${duplicates.join(', ')}`);
}

const output = {
  schemaVersion: 1,
  generatedFrom: [siteMapPath],
  pageCount: pages.length,
  kindLegend: {
    'primary-page': 'Top-level page that drives login, round selection, or course selection.',
    'curriculum-page': 'Timetable page entry.',
    'detail-page': 'HTML wrapper for detail views; business data usually comes from JSON APIs.',
    fragment: 'HTML fragment loaded into the current course-selection page.',
    page: 'Other static page entry.',
  },
  pages,
};

const serialized = `${JSON.stringify(output, null, 2)}\n`;

if (checkOnly) {
  const current = await readFile(outputPath, 'utf8');
  if (current !== serialized) {
    console.error(`${outputPath} is stale. Run: npm run page-manifest`);
    process.exit(1);
  }
  console.log(`Page manifest check passed: ${pages.length} page entries are current.`);
} else {
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, serialized);
  console.log(`Wrote ${outputPath} with ${pages.length} page entries.`);
}
