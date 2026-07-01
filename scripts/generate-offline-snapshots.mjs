import { createHash } from 'node:crypto';
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const args = process.argv.slice(2);
const checkOnly = args.includes('--check');
const sourceDomPath = path.join(root, 'artifacts', 'latest', 'snapshot', 'dom.html');
const loginSourceHtmlPath = process.env.BKSXK_LOGIN_HTML || '/tmp/bksxk-index.html';
const snapshotDir = path.join(root, 'snapshots');
const grablessonsHtmlPath = path.join(snapshotDir, 'grablessons.sanitized.html');
const indexHtmlPath = path.join(snapshotDir, 'index.sanitized.html');
const manifestPath = path.join(root, 'docs', 'offline-snapshots.manifest.generated.json');

function toPosix(value) {
  return value.split(path.sep).join('/');
}

function relativeToRoot(filePath) {
  return toPosix(path.relative(root, filePath));
}

function xkresLocalUrl(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    return rawUrl;
  }

  if (url.origin !== 'https://xkres.nwafu.edu.cn') return rawUrl;
  if (!url.pathname.startsWith('/products/jwfw/xsxkapp/')) return rawUrl;
  return `../static-snapshot/xkres.nwafu.edu.cn${url.pathname}`;
}

async function fileExists(filePath) {
  try {
    const info = await stat(filePath);
    return info.isFile();
  } catch {
    return false;
  }
}

function sanitizeTextIdentifiers(html) {
  let courseIndex = 0;
  return html
    .replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/gi, '<redacted-uuid>')
    .replace(/token=[^"'&<>\s]+/gi, 'token=<redacted>')
    .replace(/loginName=[^"'&<>\s]+/gi, 'loginName=<redacted>')
    .replace(/loginPwd=[^"'&<>\s]+/gi, 'loginPwd=<redacted>')
    .replace(/verifyCode=[^"'&<>\s]+/gi, 'verifyCode=<redacted>')
    .replace(/vtoken=[^"'&<>\s]+/gi, 'vtoken=<redacted>')
    .replace(/(\/student\/)\d{6,}(\.do\b)/gi, '$1<studentCode>$2')
    .replace(/\b(studentCode|xh)=\d{6,}\b/gi, '$1=<studentCode>')
    .replace(/\b(teachingclassid|teachingClassId|tcid|tcId|jxbid)=["'][^"']+["']/gi, (match) => {
      const [name] = match.split('=');
      return `${name}="TEACHING_CLASS_ID"`;
    })
    .replace(/\b(coursenumber|courseNumber|data-num)=["'][^"']+["']/gi, (match) => {
      const [name] = match.split('=');
      return `${name}="COURSE_NUMBER"`;
    })
    .replace(/(<span class="num-value">)\d{6,8}(<\/span>)/g, '$1COURSE_NUMBER$2')
    .replace(/>\s*\d{6,8}\[[^\]]+\]\s*</g, '>COURSE_NUMBER[SECTION]<')
    .replace(/>\s*20\d{11,}\s*</g, '>TEACHING_CLASS_ID<')
    .replace(/(<div class="cv-course">)([\s\S]*?)(<\/div>)/g, (_match, open, _content, close) => {
      courseIndex += 1;
      return `${open}课程示例 ${courseIndex}${close}`;
    });
}

function disableExecutableScripts(html) {
  let out = html.replace(/<script\b([^>]*)\bsrc=(["'])(.*?)\2([^>]*)>\s*<\/script>/gi, (_match, before, _quote, src, after) => {
    const localSrc = xkresLocalUrl(src);
    return `<script type="text/plain" data-bksxk-disabled="external-script" data-src="${localSrc}"${before}${after}></script>`;
  });

  out = out.replace(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi, (match, attrs, content) => {
    if (/type=(["'])text\/template\1/i.test(attrs)) return match;
    if (/data-bksxk-disabled=/i.test(attrs)) return match;
    return `<script type="text/plain" data-bksxk-disabled="inline-script"${attrs}>${content}</script>`;
  });

  return out;
}

function sanitizeDom(rawHtml, sourceLabel) {
  let html = rawHtml;

  const firstHtmlClose = html.search(/<\/html>/i);
  if (firstHtmlClose >= 0) {
    html = `${html.slice(0, firstHtmlClose + '</html>'.length)}\n`;
  }

  html = html
    .replace(/https:\/\/xkres\.nwafu\.edu\.cn\/products\/jwfw\/xsxkapp\/[^"'\s<>]+/gi, (url) => xkresLocalUrl(url))
    .replace(/https:\/\/bksxk\.nwafu\.edu\.cn\/xsxkapp\/sys\/xsxkapp\/\*default\/help\.do\?av=[^"'\s<>]+/gi, 'about:blank#help-offline')
    .replace(/var\s+BaseUrl\s*=\s*["']https:\/\/bksxk\.nwafu\.edu\.cn\/xsxkapp["'];/i, 'var BaseUrl = "about:blank#bksxk-offline";')
    .replace(/var\s+resUrl\s*=\s*["']https:\/\/xkres\.nwafu\.edu\.cn\/products\/jwfw\/xsxkapp["'];/i, 'var resUrl = "../static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp";')
    .replace(/var\s+casUrl\s*=\s*["']https:\/\/[^"']+["'];/i, 'var casUrl = "about:blank#cas-offline";')
    .replace(/<div id="__bksxk_guard_badge__"[\s\S]*?<\/div>/gi, '');

  html = sanitizeTextIdentifiers(html);
  html = disableExecutableScripts(html);

  const note = [
    '<!--',
    `Sanitized offline snapshot generated from ${sourceLabel}.`,
    'Scripts are disabled intentionally; linked resources point to ../static-snapshot/.',
    'Course numbers, teaching-class ids, tokens, login fields, and student identifiers are redacted.',
    '-->',
    '',
  ].join('\n');

  return `${note}${html}`;
}

async function sha256(filePath) {
  const bytes = await readFile(filePath);
  return createHash('sha256').update(bytes).digest('hex');
}

async function fileInfo(filePath) {
  const info = await stat(filePath);
  return {
    localPath: relativeToRoot(filePath),
    bytes: info.size,
    sha256: await sha256(filePath),
  };
}

async function referencedLocalAssets(filePath) {
  const html = await readFile(filePath, 'utf8');
  const refs = new Set();
  for (const match of html.matchAll(/(?:href|src|data-src)=["'](\.\.\/static-snapshot\/[^"']+)["']/g)) {
    refs.add(match[1]);
  }
  return [...refs].sort().map((ref) => {
    const absolutePath = path.resolve(path.dirname(filePath), ref);
    return {
      reference: ref,
      localPath: relativeToRoot(absolutePath),
      absolutePath,
    };
  });
}

async function assertReferencesExist(references) {
  const missing = [];
  for (const ref of references) {
    try {
      const info = await stat(ref.absolutePath);
      if (!info.isFile()) missing.push(ref);
    } catch {
      missing.push(ref);
    }
  }
  if (missing.length > 0) {
    console.error('Offline snapshot references missing files:');
    for (const ref of missing) console.error(`- ${ref.reference} -> ${ref.localPath}`);
    process.exit(1);
  }
}

async function snapshotEntry(config) {
  const references = await referencedLocalAssets(config.outputPath);
  await assertReferencesExist(references);
  const htmlInfo = await fileInfo(config.outputPath);
  return {
    id: config.id,
    kind: 'offline-html',
    source: config.source,
    ...htmlInfo,
    scriptExecution: 'disabled',
    localAssetReferenceCount: references.length,
    localAssetReferences: references.map(({ reference, localPath }) => ({ reference, localPath })),
    redactions: config.redactions,
  };
}

async function buildManifest() {
  const snapshotConfigs = [
    {
      id: 'index-sanitized',
      source: 'public login/index HTML',
      outputPath: indexHtmlPath,
      redactions: [
        'login query values',
        'student identifiers',
        'remote help link',
      ],
    },
    {
      id: 'grablessons-sanitized',
      source: 'artifacts/latest/snapshot/dom.html',
      outputPath: grablessonsHtmlPath,
      redactions: [
        'session token and login query values',
        'student identifiers',
        'course numbers in attributes/text',
        'teaching-class identifiers in attributes/text',
        'dynamic selected-course modal appended after the first HTML document',
      ],
    },
  ];

  for (const config of snapshotConfigs) {
    if (!(await fileExists(config.outputPath))) {
      console.error(`Missing offline snapshot: ${relativeToRoot(config.outputPath)}`);
      process.exit(1);
    }
  }

  const snapshots = [];
  for (const config of snapshotConfigs) snapshots.push(await snapshotEntry(config));

  return {
    schemaVersion: 1,
    generatedFrom: ['artifacts/latest/snapshot/dom.html', 'public login/index HTML'],
    snapshotCount: snapshots.length,
    snapshots,
  };
}

if (!checkOnly) {
  const rawHtml = await readFile(sourceDomPath, 'utf8');
  await mkdir(snapshotDir, { recursive: true });
  await writeFile(grablessonsHtmlPath, sanitizeDom(rawHtml, 'artifacts/latest/snapshot/dom.html'), 'utf8');

  if (await fileExists(loginSourceHtmlPath)) {
    const rawLoginHtml = await readFile(loginSourceHtmlPath, 'utf8');
    await writeFile(indexHtmlPath, sanitizeDom(rawLoginHtml, 'public login/index HTML'), 'utf8');
  } else if (!(await fileExists(indexHtmlPath))) {
    console.error(`Missing login snapshot source ${loginSourceHtmlPath} and ${relativeToRoot(indexHtmlPath)} does not exist.`);
    process.exit(1);
  }
}

const manifest = await buildManifest();
const serialized = `${JSON.stringify(manifest, null, 2)}\n`;

if (checkOnly) {
  const current = await readFile(manifestPath, 'utf8');
  if (current !== serialized) {
    console.error('Offline snapshot manifest is stale. Run: npm run offline-snapshots');
    process.exit(1);
  }
  const referenceCount = manifest.snapshots.reduce((total, snapshot) => total + snapshot.localAssetReferenceCount, 0);
  console.log(`Offline snapshot check passed: ${manifest.snapshotCount} HTML snapshots, ${referenceCount} local asset references.`);
} else {
  await mkdir(path.dirname(manifestPath), { recursive: true });
  await writeFile(manifestPath, serialized, 'utf8');
  console.log(`Wrote ${relativeToRoot(grablessonsHtmlPath)}`);
  console.log(`Wrote ${relativeToRoot(indexHtmlPath)}`);
  console.log(`Wrote ${relativeToRoot(manifestPath)}`);
}
