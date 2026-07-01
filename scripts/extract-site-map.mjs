import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const staticDir = path.join(root, 'static-snapshot', 'bksxk.nwafu.edu.cn', 'xsxkapp', 'static');
const outputPath = process.argv[2] || path.join(root, 'docs', 'site-map.generated.md');
const jsonOutputPath = path.join(root, 'docs', 'site-map.generated.json');

const endpointStringPattern = /(['"`])([^'"`]*\.do(?:\?[^'"`]*)?)\1/g;
const defaultPagePattern = /(?:\/sys\/xsxkapp\/\*default\/|\.\/)[^'"`\s<>]*\.do(?:\?[^'"`\s<>]*)?/g;
const sensitiveSegmentPattern = /(\/student\/)\d+(\.do\b)/i;
const stateChangingEndpointPattern = /\/elective\/volunteer\.do\b|\/elective\/deleteVolunteer\.do\b|\/elective\/submit\/unsuccessful\.do\b|\/textbook\/(?:addbook|modifybook)\.do\b|\/student\/(?:xklcqr|logout|authlogout|register)\.do\b/i;
const stateChangingFunctionPattern = /\b(?:addVolunteer|deleteVolunteerResult|bookJxbJcResult|delBookJxbJcResult|submitUnSuccessful|makeSureLcxz|studentLogOut|autoLogOut|loginInUserRegister)\b/i;
const categoryLabels = {
  'write-operation': '写操作',
  'write-status': '写操作状态',
  'get-query': 'GET 查询',
  'post-query': 'POST 查询',
  'static-reference': '静态引用',
};

function lineOf(text, index) {
  let line = 1;
  for (let i = 0; i < index; i += 1) {
    if (text.charCodeAt(i) === 10) line += 1;
  }
  return line;
}

function decodeStringLiteral(literal) {
  try {
    return Function(`"use strict"; return (${literal});`)();
  } catch {
    return literal.slice(1, -1);
  }
}

function splitTopLevel(source, separator = ',') {
  const out = [];
  let current = '';
  let depth = 0;
  let quote = '';
  let escaped = false;

  for (const ch of source) {
    if (quote) {
      current += ch;
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === quote) {
        quote = '';
      }
      continue;
    }

    if (ch === '"' || ch === "'" || ch === '`') {
      quote = ch;
      current += ch;
      continue;
    }

    if (ch === '(' || ch === '[' || ch === '{') depth += 1;
    if (ch === ')' || ch === ']' || ch === '}') depth -= 1;

    if (ch === separator && depth === 0) {
      out.push(current.trim());
      current = '';
    } else {
      current += ch;
    }
  }

  if (current.trim()) out.push(current.trim());
  return out;
}

function splitTopLevelPlus(source) {
  const out = [];
  let current = '';
  let depth = 0;
  let quote = '';
  let escaped = false;

  for (const ch of source) {
    if (quote) {
      current += ch;
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === quote) {
        quote = '';
      }
      continue;
    }

    if (ch === '"' || ch === "'" || ch === '`') {
      quote = ch;
      current += ch;
      continue;
    }

    if (ch === '(' || ch === '[' || ch === '{') depth += 1;
    if (ch === ')' || ch === ']' || ch === '}') depth -= 1;

    if (ch === '+' && depth === 0) {
      out.push(current.trim());
      current = '';
    } else {
      current += ch;
    }
  }

  if (current.trim()) out.push(current.trim());
  return out;
}

function splitObjectProperty(source) {
  let depth = 0;
  let quote = '';
  let escaped = false;

  for (let i = 0; i < source.length; i += 1) {
    const ch = source[i];
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === quote) {
        quote = '';
      }
      continue;
    }

    if (ch === '"' || ch === "'" || ch === '`') {
      quote = ch;
      continue;
    }

    if (ch === '(' || ch === '[' || ch === '{') depth += 1;
    if (ch === ')' || ch === ']' || ch === '}') depth -= 1;

    if (ch === ':' && depth === 0) {
      return [source.slice(0, i).trim(), source.slice(i + 1).trim()];
    }
  }

  return ['', ''];
}

function cleanObjectKey(key) {
  return key.trim().replace(/^['"`]|['"`]$/g, '');
}

function parseObjectLiteralProperties(source) {
  const trimmed = source.trim();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return new Map();

  const body = trimmed.slice(1, -1);
  const properties = new Map();
  for (const part of splitTopLevel(body)) {
    const [rawKey, value] = splitObjectProperty(part);
    const key = cleanObjectKey(rawKey);
    if (key) properties.set(key, value);
  }
  return properties;
}

function cleanExpressionToken(token) {
  return token
    .replace(/^\(+|\)+$/g, '')
    .replace(/\bnew Date\(\)\.getTime\(\)/g, 'timestamp')
    .replace(/\(new Date\)\.getTime\(\)/g, 'timestamp')
    .replace(/\s+/g, ' ')
    .trim();
}

function templateFromExpression(expression) {
  const pieces = splitTopLevelPlus(expression);
  let template = '';

  for (const piece of pieces) {
    const trimmed = piece.trim();
    if (!trimmed || trimmed === 'BaseUrl' || trimmed === 'resUrl') continue;
    if (/^['"`]/.test(trimmed)) {
      template += decodeStringLiteral(trimmed);
      continue;
    }

    const clean = cleanExpressionToken(trimmed);
    if (!clean || clean === 'BaseUrl' || clean === 'resUrl') continue;
    template += `{${clean}}`;
  }

  return normalizeEndpoint(template);
}

function normalizeEndpoint(value) {
  return String(value || '')
    .replace(/^https:\/\/bksxk\.nwafu\.edu\.cn\/xsxkapp/, '')
    .replace(/^https:\/\/bksxk\.nwafu\.edu\.cn/, '')
    .replace(/^\.\/+/, './')
    .replace(sensitiveSegmentPattern, '$1<studentCode>$2')
    .replace(/(\/student\/)\{(?:e|e\.code|studentInfo\.code|studentCode)\}(\.do\b)/gi, '$1<studentCode>$2')
    .replace(/token=[^&#]+/gi, 'token=<redacted>')
    .replace(/studentCode=\d+/gi, 'studentCode=<redacted>')
    .replace(/loginName=[^&#]+/gi, 'loginName=<redacted>')
    .replace(/verifyCode=[^&#]+/gi, 'verifyCode=<redacted>')
    .replace(/vtoken=[^&#]+/gi, 'vtoken=<redacted>');
}

function classify(record) {
  const target = `${record.method || ''} ${record.endpoint || ''} ${record.functionName || ''}`;
  if (stateChangingEndpointPattern.test(record.endpoint || '') || stateChangingFunctionPattern.test(target)) return 'write-operation';
  if (/\/student\/guideMap\.do\b/i.test(record.endpoint || '') && String(record.method || '').toUpperCase() === 'POST') return 'write-operation';
  if (/\/elective\/studentstatus\.do\b/i.test(record.endpoint || '')) return 'write-status';
  if (record.method && record.method.toUpperCase() === 'GET') return 'get-query';
  if (record.method && record.method.toUpperCase() === 'POST') return 'post-query';
  return 'static-reference';
}

function isUsefulEndpoint(endpoint) {
  const value = String(endpoint || '').trim();
  if (!value.includes('.do')) return false;
  if (/^\.do(?:\?.*)?$/.test(value)) return false;
  return value.startsWith('/sys/xsxkapp/') || value.startsWith('./');
}

function endpointIdentity(endpoint) {
  const value = String(endpoint || '');
  const [pathname, query = ''] = value.split('?');
  const queryKeys = query
    .split('&')
    .filter(Boolean)
    .map((part) => part.split('=')[0])
    .sort()
    .join('&');
  return queryKeys ? `${pathname}?${queryKeys}` : pathname;
}

function extractBalancedCall(text, startIndex) {
  const openIndex = text.indexOf('(', startIndex);
  if (openIndex < 0) return null;

  let depth = 0;
  let quote = '';
  let escaped = false;

  for (let i = openIndex; i < text.length; i += 1) {
    const ch = text[i];
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === quote) {
        quote = '';
      }
      continue;
    }

    if (ch === '"' || ch === "'" || ch === '`') {
      quote = ch;
      continue;
    }

    if (ch === '(') depth += 1;
    if (ch === ')') {
      depth -= 1;
      if (depth === 0) {
        return {
          argsSource: text.slice(openIndex + 1, i),
          endIndex: i + 1,
        };
      }
    }
  }

  return null;
}

function nearestFunctionName(text, index) {
  const prefix = text.slice(Math.max(0, index - 2500), index);
  const matches = [...prefix.matchAll(/function\s+([\w$]+)\s*\(/g)];
  if (matches.length) return matches.at(-1)[1];

  const assignmentMatches = [...prefix.matchAll(/(?:window\.)?([\w$]+)\.([\w$]+)\s*=\s*function\b/g)];
  if (assignmentMatches.length) {
    const match = assignmentMatches.at(-1);
    return `${match[1]}.${match[2]}`;
  }

  const moduleMatches = [...prefix.matchAll(/\}\)\(window\.([\w$]+)\s*=/g)];
  if (moduleMatches.length) return moduleMatches.at(-1)[1];
  return '';
}

async function readStaticSources() {
  const entries = [];
  let files = [];
  try {
    files = await readdir(staticDir);
  } catch {
    files = [];
  }

  for (const file of files.sort()) {
    if (!/\.(js|html)$/i.test(file)) continue;
    const filePath = path.join(staticDir, file);
    entries.push({
      name: `static/${file}`,
      text: await readFile(filePath, 'utf8'),
    });
  }

  return entries;
}

function collectStringEndpoints(source) {
  const records = [];
  for (const match of source.text.matchAll(endpointStringPattern)) {
    const endpoint = normalizeEndpoint(match[2]);
    if (!isUsefulEndpoint(endpoint)) continue;
    records.push({
      endpoint,
      kind: defaultPagePattern.test(endpoint) || endpoint.startsWith('./') ? 'page-or-fragment' : 'endpoint-string',
      source: source.name,
      line: lineOf(source.text, match.index || 0),
      functionName: nearestFunctionName(source.text, match.index || 0),
      method: '',
    });
    defaultPagePattern.lastIndex = 0;
  }
  return records;
}

function collectAjaxCalls(source) {
  const records = [];
  const callPattern = /BH_UTILS\.do(?:Sync)?Ajax\s*\(/g;
  for (const match of source.text.matchAll(callPattern)) {
    const call = extractBalancedCall(source.text, match.index || 0);
    if (!call) continue;
    const args = splitTopLevel(call.argsSource);
    const endpointExpression = args[0] || '';
    const endpoint = templateFromExpression(endpointExpression);
    if (!isUsefulEndpoint(endpoint)) continue;

    const methodArg = args.find((arg) => /^['"](get|post)['"]$/i.test(arg.trim()));
    const method = methodArg ? decodeStringLiteral(methodArg).toUpperCase() : '';

    records.push({
      endpoint,
      kind: 'ajax',
      method,
      source: source.name,
      line: lineOf(source.text, match.index || 0),
      functionName: nearestFunctionName(source.text, match.index || 0),
      args: args.slice(0, 4).join(', ').replace(/\s+/g, ' ').slice(0, 260),
    });
  }
  return records;
}

function collectJqueryShortcutAjaxCalls(source) {
  const records = [];
  const callPattern = /\$\.(get|post)\s*\(/g;

  for (const match of source.text.matchAll(callPattern)) {
    const call = extractBalancedCall(source.text, match.index || 0);
    if (!call) continue;
    const args = splitTopLevel(call.argsSource);
    const endpointExpression = args[0] || '';
    const endpoint = templateFromExpression(endpointExpression);
    if (!isUsefulEndpoint(endpoint)) continue;

    records.push({
      endpoint,
      kind: 'ajax',
      method: match[1].toUpperCase(),
      source: source.name,
      line: lineOf(source.text, match.index || 0),
      functionName: nearestFunctionName(source.text, match.index || 0),
      args: args.slice(0, 4).join(', ').replace(/\s+/g, ' ').slice(0, 260),
    });
  }

  return records;
}

function collectJqueryObjectAjaxCalls(source) {
  const records = [];
  const callPattern = /\$\.ajax\s*\(/g;

  for (const match of source.text.matchAll(callPattern)) {
    const call = extractBalancedCall(source.text, match.index || 0);
    if (!call) continue;
    const args = splitTopLevel(call.argsSource);
    const properties = parseObjectLiteralProperties(args[0] || '');
    const endpointExpression = properties.get('url') || '';
    const endpoint = templateFromExpression(endpointExpression);
    if (!isUsefulEndpoint(endpoint)) continue;

    const methodExpression = properties.get('type') || properties.get('method') || '';
    const method = /^['"](get|post)['"]$/i.test(methodExpression.trim())
      ? decodeStringLiteral(methodExpression).toUpperCase()
      : 'GET';

    records.push({
      endpoint,
      kind: 'ajax',
      method,
      source: source.name,
      line: lineOf(source.text, match.index || 0),
      functionName: nearestFunctionName(source.text, match.index || 0),
      args: args.slice(0, 2).join(', ').replace(/\s+/g, ' ').slice(0, 260),
    });
  }

  return records;
}

function collectFunctions(source) {
  const records = [];

  for (const match of source.text.matchAll(/function\s+([\w$]+)\s*\(/g)) {
    records.push({
      name: match[1],
      source: source.name,
      line: lineOf(source.text, match.index || 0),
    });
  }

  for (const match of source.text.matchAll(/\}\)\(window\.([\w$]+)\s*=\s*window\.[\w$]+\s*\|\|\s*\{\}\)/g)) {
    records.push({
      name: `window.${match[1]}`,
      source: source.name,
      line: lineOf(source.text, match.index || 0),
    });
  }

  return records;
}

function mergeRecords(records) {
  const map = new Map();
  for (const record of records) {
    const key = `${record.kind}|${record.method || ''}|${record.endpoint}|${record.source}|${record.line}`;
    if (!map.has(key)) {
      const next = { ...record };
      next.category = classify(next);
      map.set(key, next);
    }
  }
  return [...map.values()].sort((a, b) => {
    const endpoint = a.endpoint.localeCompare(b.endpoint);
    if (endpoint !== 0) return endpoint;
    return `${a.source}:${a.line}`.localeCompare(`${b.source}:${b.line}`);
  });
}

function uniqueByEndpoint(records, predicate) {
  const ajaxIdentities = new Set(records.filter((record) => record.kind === 'ajax').map((record) => endpointIdentity(record.endpoint)));
  const map = new Map();
  for (const record of records.filter(predicate)) {
    if (record.kind !== 'ajax' && ajaxIdentities.has(endpointIdentity(record.endpoint))) continue;
    const key = `${record.method || ''} ${endpointIdentity(record.endpoint)}`;
    if (!map.has(key)) {
      map.set(key, record);
      continue;
    }

    const current = map.get(key);
    if (!current.method && record.method) map.set(key, record);
  }
  return [...map.values()].sort((a, b) => `${a.method || ''} ${a.endpoint}`.localeCompare(`${b.method || ''} ${b.endpoint}`));
}

function renderTable(records, columns) {
  if (!records.length) return ['_None found._'];
  const lines = [
    `| ${columns.map((column) => column.title).join(' | ')} |`,
    `| ${columns.map((column) => column.align || '---').join(' | ')} |`,
  ];

  for (const record of records) {
    lines.push(`| ${columns.map((column) => column.render(record)).join(' | ')} |`);
  }

  return lines;
}

function escapeCell(value) {
  return String(value == null ? '' : value).replace(/\|/g, '\\|').replace(/\n/g, ' ');
}

const sources = await readStaticSources();
const stringRecords = sources.flatMap(collectStringEndpoints);
const ajaxRecords = sources.flatMap((source) => [
  ...collectAjaxCalls(source),
  ...collectJqueryShortcutAjaxCalls(source),
  ...collectJqueryObjectAjaxCalls(source),
]);
const functionRecords = sources.flatMap(collectFunctions);
const records = mergeRecords([...stringRecords, ...ajaxRecords]);
const apiRecords = uniqueByEndpoint(records, (record) => !record.endpoint.includes('*default') && !record.endpoint.startsWith('./'));
const pageRecords = uniqueByEndpoint(records, (record) => record.endpoint.includes('*default') || record.endpoint.startsWith('./'));
const stateChangingRecords = uniqueByEndpoint(records, (record) => ['write-operation', 'write-status'].includes(record.category));

await mkdir(path.dirname(outputPath), { recursive: true });
await mkdir(path.dirname(jsonOutputPath), { recursive: true });
await writeFile(
  jsonOutputPath,
  JSON.stringify(
    {
      generatedAt: new Date().toISOString(),
      sources: sources.map((source) => source.name),
      pages: pageRecords,
      apis: apiRecords,
      stateChanging: stateChangingRecords,
      records,
      functions: functionRecords,
    },
    null,
    2,
  ),
  'utf8',
);

const lines = [
  '# BKSXK 静态站点地图',
  '',
  `生成时间：${new Date().toISOString()}`,
  '',
  `扫描来源：${sources.map((source) => `\`${source.name}\``).join(', ')}`,
  '',
  `统计：页面/片段 ${pageRecords.length} 个，API ${apiRecords.length} 个，写操作相关接口 ${stateChangingRecords.length} 个，函数/模块标识 ${functionRecords.length} 个。`,
  '',
  '> 本文档来自静态脚本快照的自动提取，会解析 `BH_UTILS.doAjax`、`BH_UTILS.doSyncAjax`、`$.get`、`$.post` 和 `$.ajax({ url, type })`。动态条件分支仍需要通过受保护浏览器逐项验证。',
  '',
  '## 页面与片段入口',
  '',
  ...renderTable(pageRecords, [
    { title: '入口', render: (record) => `\`${escapeCell(record.endpoint)}\`` },
    { title: '方法', render: (record) => record.method || '-' },
    { title: '来源', render: (record) => `\`${escapeCell(`${record.source}:${record.line}`)}\`` },
    { title: '附近函数', render: (record) => `\`${escapeCell(record.functionName || '-')}\`` },
  ]),
  '',
  '## API 入口',
  '',
  ...renderTable(apiRecords, [
    { title: '接口', render: (record) => `\`${escapeCell(record.endpoint)}\`` },
    { title: '方法', render: (record) => record.method || '-' },
    { title: '分类', render: (record) => categoryLabels[record.category] || record.category },
    { title: '来源', render: (record) => `\`${escapeCell(`${record.source}:${record.line}`)}\`` },
    { title: '附近函数', render: (record) => `\`${escapeCell(record.functionName || '-')}\`` },
  ]),
  '',
  '## 写操作接口',
  '',
  ...renderTable(stateChangingRecords, [
    { title: '接口', render: (record) => `\`${escapeCell(record.endpoint)}\`` },
    { title: '方法', render: (record) => record.method || '-' },
    { title: '来源', render: (record) => `\`${escapeCell(`${record.source}:${record.line}`)}\`` },
    { title: '附近函数', render: (record) => `\`${escapeCell(record.functionName || '-')}\`` },
  ]),
  '',
  '## 函数与模块索引',
  '',
  ...renderTable(
    functionRecords
      .filter((record) => !record.name.startsWith('t') && !record.name.startsWith('i') && !record.name.startsWith('n'))
      .sort((a, b) => a.name.localeCompare(b.name))
      .slice(0, 180),
    [
      { title: '函数/模块', render: (record) => `\`${escapeCell(record.name)}\`` },
      { title: '来源', render: (record) => `\`${escapeCell(`${record.source}:${record.line}`)}\`` },
    ],
  ),
  '',
];

await writeFile(outputPath, `${lines.join('\n')}\n`, 'utf8');
console.log(`Wrote ${path.relative(root, outputPath)}`);
console.log(`Wrote ${path.relative(root, jsonOutputPath)}`);
