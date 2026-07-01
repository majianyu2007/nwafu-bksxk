import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

const inputPath = process.argv[2] || path.join(process.cwd(), 'artifacts', 'latest', 'network.jsonl');
const outputPath = process.argv[3] || path.join(process.cwd(), 'docs', 'api.generated.md');
const writeEndpointPattern = /\/(?:elective\/(?:volunteer|deleteVolunteer|submit\/unsuccessful)|textbook\/(?:addbook|modifybook)|student\/(?:xklcqr|logout|authlogout|register|guideMap))\.do\b/i;

function bodyShape(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return value ? typeof value : '';
  }
  return Object.fromEntries(
    Object.entries(value).map(([key, item]) => {
      if (Array.isArray(item)) return [key, 'array'];
      if (item && typeof item === 'object') return [key, bodyShape(item)];
      return [key, typeof item];
    }),
  );
}

function routeKey(record) {
  const rawPath = record.urlSummary?.path || new URL(record.url).pathname;
  const path = rawPath.replace(/(\/student\/)\d+(\.do\b)/i, '$1<redacted>$2');
  return `${record.method || 'GET'} ${record.urlSummary?.origin || ''}${path}`;
}

function isWriteOperation(record) {
  const path = record.urlSummary?.path || new URL(record.url).pathname;
  return writeEndpointPattern.test(path);
}

function mergeSet(target, values = []) {
  for (const value of values) {
    if (value) target.add(value);
  }
}

const raw = await readFile(inputPath, 'utf8');
const records = raw
  .split('\n')
  .filter(Boolean)
  .map((line) => JSON.parse(line));

const routes = new Map();
const locallyBlocked = [];

for (const record of records) {
  if (record.type !== 'request') continue;
  const key = routeKey(record);
  if (!routes.has(key)) {
    routes.set(key, {
      key,
      count: 0,
      blockedCount: 0,
      resourceTypes: new Set(),
      queryKeys: new Set(),
      bodyShape: '',
      sampleUrl: record.url,
    });
  }
  const route = routes.get(key);
  route.count += 1;
  if (record.status === 'blocked') {
    route.blockedCount += 1;
    locallyBlocked.push(record);
  }
  route.resourceTypes.add(record.resourceType);
  mergeSet(route.queryKeys, record.urlSummary?.queryKeys);
  if (!route.bodyShape && record.postData) {
    route.bodyShape = bodyShape(record.postData);
  }
}

const blockedWriteOperations = locallyBlocked.filter(isWriteOperation);
const sortedRoutes = [...routes.values()].sort((a, b) => a.key.localeCompare(b.key));
const now = new Date().toISOString();

const lines = [
  '# BKSXK API 捕获摘要',
  '',
  `生成时间：${now}`,
  '',
  `来源日志：\`${path.relative(process.cwd(), inputPath)}\``,
  '',
  '> 这份文档只保留接口结构、字段形状和本地阻断状态；Cookie、Token、密码、学号等敏感值应只留在本地 artifacts 中，且不要提交。 ',
  '',
  '## 接口列表',
  '',
  '| 方法与路径 | 次数 | 资源类型 | Query Keys | Body Shape | 本地阻断 |',
  '| --- | ---: | --- | --- | --- | ---: |',
];

for (const route of sortedRoutes) {
  lines.push(
    `| \`${route.key}\` | ${route.count} | ${[...route.resourceTypes].join(', ')} | ${[...route.queryKeys].join(', ') || '-'} | \`${JSON.stringify(route.bodyShape || '-')}\` | ${route.blockedCount} |`,
  );
}

lines.push('', '## 本地阻断的写操作请求', '');

if (blockedWriteOperations.length === 0) {
  lines.push('本次日志中没有本地阻断的选课/退选写操作请求。');
} else {
  for (const record of blockedWriteOperations) {
    lines.push(
      `- \`${record.method} ${record.urlSummary.origin}${record.urlSummary.path}\`：resource=\`${record.resourceType}\`，reason=\`${record.guardReason || 'matched'}\`，bodyShape=\`${JSON.stringify(bodyShape(record.postData) || '-')}\``,
    );
  }
}

await mkdir(path.dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${lines.join('\n')}\n`, 'utf8');
console.log(`Wrote ${outputPath}`);
