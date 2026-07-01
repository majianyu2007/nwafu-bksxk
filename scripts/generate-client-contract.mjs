import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const args = process.argv.slice(2);
const checkOnly = args.includes('--check');
const outputPath = args.find((arg) => arg !== '--check') || 'docs/client.contract.generated.json';

const manifestPath = 'docs/api.manifest.generated.json';
const requestsPath = 'docs/api.requests.generated.json';
const responsesPath = 'docs/api.response-schemas.generated.json';
const pagesPath = 'docs/page.manifest.generated.json';
const siteMapPath = 'docs/site-map.generated.json';

function key(entry) {
  return `${entry.id} ${entry.method} ${entry.endpoint}`;
}

function indexById(entries, label) {
  const map = new Map();
  const duplicates = [];
  for (const entry of entries) {
    if (map.has(entry.id)) duplicates.push(entry.id);
    map.set(entry.id, entry);
  }
  if (duplicates.length > 0) {
    throw new Error(`Duplicate ids in ${label}: ${duplicates.join(', ')}`);
  }
  return map;
}

function assertSameEndpointShape(base, other, label) {
  for (const field of ['id', 'section', 'status', 'method', 'endpoint', 'stateChanging', 'description']) {
    if (base[field] !== other[field]) {
      throw new Error(`${label} mismatch for ${key(base)} field ${field}: ${JSON.stringify(base[field])} !== ${JSON.stringify(other[field])}`);
    }
  }
}

function countBy(entries, select) {
  const counts = {};
  for (const entry of entries) {
    const value = select(entry);
    counts[value] = (counts[value] || 0) + 1;
  }
  return counts;
}

const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
const requests = JSON.parse(await readFile(requestsPath, 'utf8'));
const responses = JSON.parse(await readFile(responsesPath, 'utf8'));
const pages = JSON.parse(await readFile(pagesPath, 'utf8'));

let siteMapStats = null;
try {
  const siteMap = JSON.parse(await readFile(siteMapPath, 'utf8'));
  siteMapStats = {
    apiRows: siteMap.apis.length,
    pageRows: siteMap.pages.length,
    stateChangingRows: siteMap.stateChanging.length,
    functionRows: siteMap.functions.length,
  };
} catch {
  siteMapStats = null;
}

if (manifest.endpointCount !== manifest.endpoints.length) {
  throw new Error(`Manifest endpointCount mismatch: ${manifest.endpointCount} !== ${manifest.endpoints.length}`);
}
if (requests.requestCount !== requests.requests.length) {
  throw new Error(`Request count mismatch: ${requests.requestCount} !== ${requests.requests.length}`);
}
if (responses.endpointCount !== responses.responseSchemas.length) {
  throw new Error(`Response schema count mismatch: ${responses.endpointCount} !== ${responses.responseSchemas.length}`);
}
if (pages.pageCount !== pages.pages.length) {
  throw new Error(`Page count mismatch: ${pages.pageCount} !== ${pages.pages.length}`);
}

const requestById = indexById(requests.requests, requestsPath);
const responseById = indexById(responses.responseSchemas, responsesPath);
indexById(manifest.endpoints, manifestPath);
indexById(pages.pages, pagesPath);

const missingRequests = [];
const missingResponses = [];
const endpoints = manifest.endpoints.map((endpoint) => {
  const requestEntry = requestById.get(endpoint.id);
  const responseEntry = responseById.get(endpoint.id);

  if (!requestEntry) missingRequests.push(key(endpoint));
  if (!responseEntry) missingResponses.push(key(endpoint));
  if (!requestEntry || !responseEntry) return null;

  assertSameEndpointShape(endpoint, requestEntry, requestsPath);
  assertSameEndpointShape(endpoint, responseEntry, responsesPath);

  return {
    ...endpoint,
    request: requestEntry.request,
    response: responseEntry.response,
    executionPolicy: endpoint.stateChanging ? 'serialize-only' : 'read-only-callable',
  };
});

if (missingRequests.length > 0 || missingResponses.length > 0) {
  if (missingRequests.length > 0) {
    console.error('Missing requests:');
    for (const item of missingRequests) console.error(`- ${item}`);
  }
  if (missingResponses.length > 0) {
    console.error('Missing responses:');
    for (const item of missingResponses) console.error(`- ${item}`);
  }
  process.exit(1);
}

const contractEndpoints = endpoints.filter(Boolean);
const output = {
  schemaVersion: 1,
  generatedFrom: [manifestPath, requestsPath, responsesPath, pagesPath],
  ...(siteMapStats ? { siteMapStats } : {}),
  endpointCount: contractEndpoints.length,
  pageCount: pages.pages.length,
  summary: {
    byStatus: countBy(contractEndpoints, (endpoint) => endpoint.status),
    bySection: countBy(contractEndpoints, (endpoint) => endpoint.section),
    byMethod: countBy(contractEndpoints, (endpoint) => endpoint.method),
    byResponseAvailability: countBy(contractEndpoints, (endpoint) => endpoint.response.availability),
    stateChanging: contractEndpoints.filter((endpoint) => endpoint.stateChanging).length,
  },
  endpointContract: contractEndpoints,
  pageContract: pages.pages,
};

const serialized = `${JSON.stringify(output, null, 2)}\n`;

if (checkOnly) {
  const current = await readFile(outputPath, 'utf8');
  if (current !== serialized) {
    console.error(`${outputPath} is stale. Run: npm run client-contract`);
    process.exit(1);
  }
  console.log(`Client contract check passed: ${contractEndpoints.length} endpoints and ${pages.pages.length} pages are current.`);
} else {
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, serialized);
  console.log(`Wrote ${outputPath} with ${contractEndpoints.length} endpoints and ${pages.pages.length} pages.`);
}
