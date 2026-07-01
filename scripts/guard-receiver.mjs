import http from 'node:http';
import { appendFile, mkdir, rm, symlink, writeFile } from 'node:fs/promises';
import path from 'node:path';

const ROOT = process.cwd();
const PORT = Number(process.env.BKSXK_GUARD_PORT || 48732);
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const runDir = path.join(ROOT, 'artifacts', 'runs', `receiver-${stamp}`);
const latestLink = path.join(ROOT, 'artifacts', 'latest');
const networkLog = path.join(runDir, 'network.jsonl');
const blockedLog = path.join(runDir, 'blocked-requests.jsonl');
const eventsLog = path.join(runDir, 'guard-events.jsonl');

async function writeJsonl(file, record) {
  await appendFile(file, `${JSON.stringify(record)}\n`, 'utf8');
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    let body = '';
    request.setEncoding('utf8');
    request.on('data', (chunk) => {
      body += chunk;
      if (body.length > 1_000_000) {
        request.destroy();
        reject(new Error('request body too large'));
      }
    });
    request.on('end', () => resolve(body));
    request.on('error', reject);
  });
}

function writeCors(response, status = 204, body = '') {
  response.writeHead(status, {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'content-type',
    'Content-Type': 'text/plain; charset=utf-8',
  });
  response.end(body);
}

await mkdir(runDir, { recursive: true });
await rm(latestLink, { force: true, recursive: true }).catch(() => {});
await symlink(runDir, latestLink, 'dir').catch(() => {});
await writeFile(
  path.join(runDir, 'summary.json'),
  JSON.stringify(
    {
      startedAt: new Date().toISOString(),
      runDir,
      networkLog,
      blockedLog,
      eventsLog,
      collector: `http://127.0.0.1:${PORT}/event`,
    },
    null,
    2,
  ),
  'utf8',
);

const server = http.createServer(async (request, response) => {
  if (request.method === 'OPTIONS') {
    writeCors(response);
    return;
  }

  if (request.method === 'GET' && request.url === '/health') {
    writeCors(response, 200, 'ok\n');
    return;
  }

  if (request.method !== 'POST' || request.url !== '/event') {
    writeCors(response, 404, 'not found\n');
    return;
  }

  try {
    const body = await readBody(request);
    const record = JSON.parse(body || '{}');
    await writeJsonl(eventsLog, record);

    if (record.type === 'request' || record.type === 'response') {
      await writeJsonl(networkLog, record);
    }

    if (record.status === 'blocked' || record.type === 'guard-armed') {
      await writeJsonl(blockedLog, record);
    }

    writeCors(response);
  } catch (error) {
    writeCors(response, 400, `${error.message}\n`);
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`BKSXK guard receiver listening on http://127.0.0.1:${PORT}/event`);
  console.log(`Run artifacts: ${runDir}`);
});

process.on('SIGINT', () => {
  server.close(() => process.exit(0));
});
