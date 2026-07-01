import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const args = process.argv.slice(2);
const checkOnly = args.includes('--check');
const jsonOutputPath = 'docs/go-client-catalog.generated.json';
const markdownOutputPath = 'docs/go-client-catalog.generated.md';
const contractPath = 'docs/client.contract.generated.json';
const endpointAuditPath = 'docs/endpoint-inventory.audit.generated.json';

function key(endpoint) {
  return `${endpoint.method} ${endpoint.endpoint}`;
}

function typeHint(value) {
  if (Array.isArray(value)) return 'array';
  if (value == null) return 'null';
  if (typeof value !== 'string') return typeof value;
  if (/^<[^>]+>$/.test(value)) return 'placeholder';
  if (/^-?\d+$/.test(value)) return 'numeric-string';
  if (value === '') return 'empty-string';
  return 'string';
}

function tryParseJson(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
  try {
    return JSON.parse(trimmed);
  } catch {
    return null;
  }
}

function collectObjectPaths(value, prefix = '') {
  const rows = [];
  if (Array.isArray(value)) {
    rows.push({ path: `${prefix}[]`, type: 'array' });
    return rows;
  }
  if (!value || typeof value !== 'object') {
    rows.push({ path: prefix, type: typeHint(value), sample: value });
    return rows;
  }

  for (const [field, item] of Object.entries(value)) {
    const next = prefix ? `${prefix}.${field}` : field;
    if (item && typeof item === 'object' && !Array.isArray(item)) {
      rows.push({ path: next, type: 'object' });
      rows.push(...collectObjectPaths(item, next));
    } else if (Array.isArray(item)) {
      rows.push({ path: next, type: 'array' });
    } else {
      rows.push({ path: next, type: typeHint(item), sample: item });
    }
  }
  return rows;
}

function requestFields(request, endpointId) {
  const rows = [];
  for (const header of request.headers || []) {
    rows.push({ location: 'header', name: header, path: `header.${header}`, type: 'header' });
  }

  for (const container of ['pathParams', 'query', 'form']) {
    const value = request[container];
    if (!value) continue;
    for (const [field, sample] of Object.entries(value)) {
      rows.push({ location: container, name: field, path: `${container}.${field}`, type: typeHint(sample), sample });
      const parsed = tryParseJson(sample);
      if (parsed) {
        for (const nested of collectObjectPaths(parsed, `${container}.${field}`)) {
          rows.push({
            location: `${container}Json`,
            name: nested.path.split('.').at(-1),
            path: nested.path,
            type: nested.type,
            sample: nested.sample,
          });
        }
      }
    }
  }

  for (const variant of request.variants || []) {
    for (const container of ['query', 'form', 'body']) {
      const value = variant[container];
      if (!value) continue;
      for (const [field, sample] of Object.entries(value)) {
        rows.push({
          location: `variant:${variant.name}:${container}`,
          name: field,
          path: `variants.${variant.name}.${container}.${field}`,
          type: typeHint(sample),
          sample,
        });
        const parsed = tryParseJson(sample);
        if (parsed) {
          for (const nested of collectObjectPaths(parsed, `variants.${variant.name}.${container}.${field}`)) {
            rows.push({
              location: `variant:${variant.name}:${container}Json`,
              name: nested.path.split('.').at(-1),
              path: nested.path,
              type: nested.type,
              sample: nested.sample,
            });
          }
        }
      }
    }
  }

  return rows.map((row) => ({ endpointId, ...row }));
}

function responseFields(response, endpointId) {
  const rows = [];
  for (const field of response.envelopeFields || []) {
    rows.push({ endpointId, location: 'response.envelope', name: field, path: `response.${field}` });
  }
  for (const field of response.dataFields || []) {
    rows.push({ endpointId, location: 'response.data', name: field, path: `response.data.${field}` });
  }
  for (const field of response.dataListItemFields || []) {
    rows.push({ endpointId, location: 'response.dataList[]', name: field, path: `response.dataList[].${field}` });
  }
  if (response.mapKind) {
    rows.push({ endpointId, location: 'response.map', name: 'map', path: 'response.map', note: response.mapKind });
  }
  return rows;
}

function implementationStatus(endpoint) {
  const availability = endpoint.response?.availability || '';
  if (endpoint.executionPolicy === 'serialize-only') return 'serialize-only';
  if (availability === 'runtime-field-summary' || availability === 'binary' || availability === 'binary-or-empty') return 'ready-from-runtime';
  if (availability === 'static-only') return 'request-ready-response-static';
  if (availability.startsWith('static-residual')) return availability;
  return availability || 'unknown';
}

function structHint(endpoint) {
  if (/course(Result|\/kcssfa|recommendedCourse|programCourse|publicCourse|queryCourse|testCourse|course\.do)/.test(endpoint.endpoint)) return 'Course/TeachingClass models';
  if (/student\/<studentCode>|student\/xkxf/.test(endpoint.endpoint)) return 'StudentSession/StudentCredit models';
  if (/batch/.test(endpoint.endpoint)) return 'ElectiveBatch model';
  if (/publicinfo\/(?:notice|problem|celebrityfamous)/.test(endpoint.endpoint)) return 'PublicInfo models';
  if (/queryjzg/.test(endpoint.endpoint)) return 'Teacher model';
  if (/textbook/.test(endpoint.endpoint)) return 'Textbook model';
  return 'Envelope plus endpoint-specific fields';
}

function countBy(items, select) {
  const out = {};
  for (const item of items) {
    const key = select(item);
    out[key] = (out[key] || 0) + 1;
  }
  return out;
}

function fieldIndex(requestRows, responseRows) {
  const map = new Map();
  for (const row of [...requestRows, ...responseRows]) {
    const name = row.name;
    if (!name) continue;
    if (!map.has(name)) {
      map.set(name, {
        name,
        requestCount: 0,
        responseCount: 0,
        locations: new Set(),
        endpoints: new Set(),
      });
    }
    const item = map.get(name);
    if (row.location.startsWith('response.')) item.responseCount += 1;
    else item.requestCount += 1;
    item.locations.add(row.location);
    item.endpoints.add(row.endpointId);
  }

  return [...map.values()]
    .map((item) => ({
      name: item.name,
      requestCount: item.requestCount,
      responseCount: item.responseCount,
      locations: [...item.locations].sort(),
      endpointIds: [...item.endpoints].sort(),
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
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

const contract = JSON.parse(await readFile(contractPath, 'utf8'));
const endpointAudit = JSON.parse(await readFile(endpointAuditPath, 'utf8'));

const endpointCatalog = [];
const allRequestFields = [];
const allResponseFields = [];
const failures = [];

for (const endpoint of contract.endpointContract) {
  const reqFields = requestFields(endpoint.request || {}, endpoint.id);
  const resFields = responseFields(endpoint.response || {}, endpoint.id);
  allRequestFields.push(...reqFields);
  allResponseFields.push(...resFields);

  const status = implementationStatus(endpoint);
  if (!endpoint.request) failures.push(`${endpoint.id}: missing request object`);
  if (!endpoint.response) failures.push(`${endpoint.id}: missing response object`);
  if (!endpoint.executionPolicy) failures.push(`${endpoint.id}: missing execution policy`);
  if (!endpoint.stateChanging && endpoint.executionPolicy !== 'read-only-callable') failures.push(`${endpoint.id}: read-only endpoint has unexpected execution policy ${endpoint.executionPolicy}`);
  if (endpoint.stateChanging && endpoint.executionPolicy !== 'serialize-only') failures.push(`${endpoint.id}: state-changing endpoint must be serialize-only`);

  endpointCatalog.push({
    id: endpoint.id,
    section: endpoint.section,
    method: endpoint.method,
    endpoint: endpoint.endpoint,
    description: endpoint.description,
    stateChanging: endpoint.stateChanging,
    executionPolicy: endpoint.executionPolicy,
    implementationStatus: status,
    request: {
      headers: endpoint.request?.headers || [],
      contentType: endpoint.request?.contentType || '',
      fieldPaths: reqFields.map((field) => field.path),
      variants: (endpoint.request?.variants || []).map((variant) => variant.name),
    },
    response: {
      availability: endpoint.response?.availability || '',
      envelopeFields: endpoint.response?.envelopeFields || [],
      dataFields: endpoint.response?.dataFields || [],
      dataListItemFields: endpoint.response?.dataListItemFields || [],
      mapKind: endpoint.response?.mapKind || '',
      notes: endpoint.response?.notes || '',
    },
    goModelHint: structHint(endpoint),
  });
}

if (endpointAudit.failures) {
  for (const [name, items] of Object.entries(endpointAudit.failures)) {
    if (items.length > 0) failures.push(`endpoint audit ${name} has ${items.length} item(s)`);
  }
}

const sharedFieldIndex = fieldIndex(allRequestFields, allResponseFields);
const output = {
  schemaVersion: 1,
  generatedFrom: [contractPath, endpointAuditPath],
  endpointCount: endpointCatalog.length,
  summary: {
    byImplementationStatus: countBy(endpointCatalog, (endpoint) => endpoint.implementationStatus),
    byExecutionPolicy: countBy(endpointCatalog, (endpoint) => endpoint.executionPolicy),
    bySection: countBy(endpointCatalog, (endpoint) => endpoint.section),
    requestFieldPathCount: allRequestFields.length,
    responseFieldPathCount: allResponseFields.length,
    sharedFieldNameCount: sharedFieldIndex.length,
  },
  endpointCatalog,
  requestFieldCatalog: allRequestFields,
  responseFieldCatalog: allResponseFields,
  sharedFieldIndex,
  failures,
};

const jsonSerialized = `${JSON.stringify(output, null, 2)}\n`;
const topFields = sharedFieldIndex
  .filter((field) => field.requestCount + field.responseCount >= 5)
  .sort((a, b) => (b.requestCount + b.responseCount) - (a.requestCount + a.responseCount) || a.name.localeCompare(b.name))
  .slice(0, 60);

const mdLines = [
  '# Go 客户端字段目录',
  '',
  '这份生成物把 `client.contract.generated.json` 转换成 Go 实现视角：每个端点的请求字段、表单内 JSON 路径、响应字段、执行策略和建议模型分组。',
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
  '## 实现状态说明',
  '',
  '- `ready-from-runtime`：请求构造和响应字段均有运行期证据或二进制类型证据。',
  '- `request-ready-response-static`：请求构造已定位，响应只保留静态说明，后续实现要宽松解码。',
  '- `serialize-only`：状态变更接口，只在本地构造请求，不用真实系统执行响应捕获。',
  '- `static-residual-*`：静态残留或当前部署不走的路径，保留兼容处理。',
  '',
  '## 端点实现清单',
  '',
  ...markdownTable(endpointCatalog, [
    { title: 'ID', render: (row) => `\`${esc(row.id)}\`` },
    { title: '方法', render: (row) => `\`${esc(row.method)}\`` },
    { title: '端点', render: (row) => `\`${esc(row.endpoint)}\`` },
    { title: '策略', render: (row) => `\`${esc(row.executionPolicy)}\`` },
    { title: '实现状态', render: (row) => `\`${esc(row.implementationStatus)}\`` },
    { title: 'Go 模型提示', render: (row) => esc(row.goModelHint) },
  ]),
  '',
  '## 高频字段索引',
  '',
  ...markdownTable(topFields, [
    { title: '字段', render: (row) => `\`${esc(row.name)}\`` },
    { title: '请求次数', render: (row) => String(row.requestCount) },
    { title: '响应次数', render: (row) => String(row.responseCount) },
    { title: '位置', render: (row) => row.locations.slice(0, 8).map((item) => `\`${esc(item)}\``).join(', ') },
  ]),
  '',
  '## 失败项',
  '',
  ...markdownTable(failures.map((message) => ({ message })), [
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
    console.error('Go client catalog files are stale. Run: npm run go-catalog');
    process.exit(1);
  }
  if (failures.length > 0) {
    console.error('Go client catalog failed. See docs/go-client-catalog.generated.md.');
    process.exit(1);
  }
  console.log(`Go client catalog check passed: ${endpointCatalog.length} endpoints, ${sharedFieldIndex.length} field names.`);
} else {
  await mkdir(path.dirname(jsonOutputPath), { recursive: true });
  await Promise.all([
    writeFile(jsonOutputPath, jsonSerialized),
    writeFile(markdownOutputPath, mdSerialized),
  ]);
  if (failures.length > 0) {
    console.error('Go client catalog failed. See docs/go-client-catalog.generated.md.');
    process.exit(1);
  }
  console.log(`Wrote ${jsonOutputPath}`);
  console.log(`Wrote ${markdownOutputPath}`);
}
