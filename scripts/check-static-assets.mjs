import { createHash } from 'node:crypto';
import { readdir, readFile, stat, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const args = process.argv.slice(2);
const checkOnly = args.includes('--check');
const outputPath = args.find((arg) => arg !== '--check') || 'docs/static-assets.manifest.generated.json';
const snapshotRoot = path.join(root, 'static-snapshot');
const xkresRoot = path.join(snapshotRoot, 'xkres.nwafu.edu.cn', 'products', 'jwfw', 'xsxkapp');
const xkresPublicRoot = path.join(xkresRoot, 'public');
const appStaticRoot = path.join(snapshotRoot, 'bksxk.nwafu.edu.cn', 'xsxkapp', 'static');
const artifactAssetsManifestPath = path.join(root, 'artifacts', 'latest', 'assets-manifest.json');
const artifactDomPath = path.join(root, 'artifacts', 'latest', 'snapshot', 'dom.html');

const contentTypes = new Map([
  ['.css', 'text/css'],
  ['.gif', 'image/gif'],
  ['.html', 'text/html'],
  ['.jpg', 'image/jpeg'],
  ['.jpeg', 'image/jpeg'],
  ['.js', 'application/javascript'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml'],
  ['.txt', 'text/plain'],
]);

function toPosix(value) {
  return value.split(path.sep).join('/');
}

function relativeToRoot(filePath) {
  return toPosix(path.relative(root, filePath));
}

function stableId(localPath) {
  return localPath
    .replace(/^static-snapshot\//, '')
    .replace(/[^A-Za-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .toLowerCase();
}

function contentTypeFor(filePath) {
  return contentTypes.get(path.extname(filePath).toLowerCase()) || 'application/octet-stream';
}

function tagFor(localPath) {
  if (/\.css$/i.test(localPath)) return 'link';
  if (/\.js$/i.test(localPath)) return 'script';
  if (/\.(?:png|jpe?g|gif|svg)$/i.test(localPath)) return 'image';
  return 'asset';
}

function kindFor(filePath) {
  if (filePath.startsWith(xkresRoot + path.sep)) return 'xkres-public';
  if (filePath.startsWith(appStaticRoot + path.sep)) return 'app-static';
  return 'static';
}

function inferredUrlFor(filePath) {
  if (filePath.startsWith(xkresRoot + path.sep)) {
    const rel = toPosix(path.relative(xkresRoot, filePath));
    return `https://xkres.nwafu.edu.cn/products/jwfw/xsxkapp/${rel}`;
  }
  return '';
}

async function fileExists(filePath) {
  try {
    const info = await stat(filePath);
    return info.isFile();
  } catch {
    return false;
  }
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

async function sha256(filePath) {
  const bytes = await readFile(filePath);
  return createHash('sha256').update(bytes).digest('hex');
}

async function loadJson(filePath) {
  try {
    return JSON.parse(await readFile(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function localPathFromXkresUrl(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    return '';
  }
  if (url.origin !== 'https://xkres.nwafu.edu.cn') return '';
  if (!url.pathname.startsWith('/products/jwfw/xsxkapp/')) return '';
  const rel = url.pathname.slice('/products/jwfw/xsxkapp/'.length);
  return relativeToRoot(path.join(xkresRoot, rel));
}

async function collectKnownUrls() {
  const byLocalPath = new Map();
  const current = await loadJson(path.join(root, outputPath));
  if (current?.assets) {
    for (const asset of current.assets) {
      if (asset.localPath && asset.url) byLocalPath.set(asset.localPath, asset.url);
    }
  }

  const artifactManifest = await loadJson(artifactAssetsManifestPath);
  if (artifactManifest?.assets) {
    for (const asset of artifactManifest.assets) {
      if (!asset.url || !asset.localPath) continue;
      const rel = asset.localPath.replace(/^artifacts\/latest\/assets\//, '');
      const localPath = `static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/${rel}`;
      byLocalPath.set(localPath, asset.url);
    }
  }

  try {
    const dom = await readFile(artifactDomPath, 'utf8');
    for (const match of dom.matchAll(/(?:src|href)=["'](https:\/\/xkres\.nwafu\.edu\.cn\/products\/jwfw\/xsxkapp\/[^"']+)["']/g)) {
      const localPath = localPathFromXkresUrl(match[1]);
      if (localPath) byLocalPath.set(localPath, match[1]);
    }
  } catch {
    // Runtime DOM is optional and intentionally not required for offline checks.
  }

  return byLocalPath;
}

function stripCssComments(css) {
  return css.replace(/\/\*[\s\S]*?\*\//g, '');
}

async function collectCssReferenceFindings() {
  const findings = [];
  const files = await collectFiles(xkresPublicRoot);
  const cssFiles = files.filter((file) => /\.css$/i.test(file));

  for (const filePath of cssFiles) {
    const source = stripCssComments(await readFile(filePath, 'utf8'));
    for (const match of source.matchAll(/url\(([^)]+)\)/g)) {
      const raw = match[1].trim().replace(/^['"]|['"]$/g, '');
      if (!raw || raw.startsWith('data:') || raw.startsWith('//')) continue;
      if (/^[a-z][a-z0-9+.-]*:/i.test(raw)) continue;

      const target = path.normalize(path.join(path.dirname(filePath), raw));
      if (!target.startsWith(xkresRoot + path.sep)) continue;
      if (!(await fileExists(target))) {
        findings.push({
          source: relativeToRoot(filePath),
          reference: raw,
          expectedLocalPath: relativeToRoot(target),
        });
      }
    }
  }

  return findings;
}

async function collectDomReferenceFindings() {
  const findings = [];
  let dom;
  try {
    dom = await readFile(artifactDomPath, 'utf8');
  } catch {
    return findings;
  }

  for (const match of dom.matchAll(/(?:src|href)=["'](https:\/\/xkres\.nwafu\.edu\.cn\/products\/jwfw\/xsxkapp\/[^"']+)["']/g)) {
    const localPath = localPathFromXkresUrl(match[1]);
    if (!localPath) continue;
    const filePath = path.join(root, localPath);
    if (!(await fileExists(filePath))) {
      findings.push({
        source: 'artifacts/latest/snapshot/dom.html',
        reference: match[1],
        expectedLocalPath: localPath,
      });
    }
  }

  return findings;
}

async function collectRequiredStaticFindings() {
  const findings = [];
  const requirements = [
    {
      localPath: 'static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/js/des.min.js',
      snippets: ['function strEnc', 'function strDec'],
      reason: 'login password DES encoder',
    },
    {
      localPath: 'static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/js/jquery.base64.min.js',
      snippets: ['base64=function', 'd.btoa=d.encode'],
      reason: 'login password Base64 encoder',
    },
    {
      localPath: 'static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/js/index/index.min.js',
      snippets: ['student/check/login.do', 'strEnc', '$.base64.encode'],
      reason: 'login request construction',
    },
    {
      localPath: 'static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/js/index/indexBS.min.js',
      snippets: ['function getDesKeys', 'this', 'password', 'is'],
      reason: 'login DES key source',
    },
  ];

  for (const requirement of requirements) {
    const filePath = path.join(root, requirement.localPath);
    if (!(await fileExists(filePath))) {
      findings.push({
        source: 'required static resource',
        reference: requirement.reason,
        expectedLocalPath: requirement.localPath,
      });
      continue;
    }

    const source = await readFile(filePath, 'utf8');
    for (const snippet of requirement.snippets) {
      if (!source.includes(snippet)) {
        findings.push({
          source: requirement.localPath,
          reference: `${requirement.reason}: missing ${snippet}`,
          expectedLocalPath: requirement.localPath,
        });
      }
    }
  }

  return findings;
}

const knownUrls = await collectKnownUrls();
const files = (await collectFiles(snapshotRoot)).sort((a, b) => relativeToRoot(a).localeCompare(relativeToRoot(b)));
const assets = [];

for (const filePath of files) {
  const localPath = relativeToRoot(filePath);
  const info = await stat(filePath);
  const url = knownUrls.get(localPath) || inferredUrlFor(filePath);
  const asset = {
    id: stableId(localPath),
    kind: kindFor(filePath),
    tag: tagFor(localPath),
    localPath,
    bytes: info.size,
    sha256: await sha256(filePath),
    contentType: contentTypeFor(filePath),
  };
  if (url) asset.url = url;
  if (filePath.startsWith(appStaticRoot + path.sep)) {
    asset.logicalPath = `static/${path.basename(filePath)}`;
  }
  assets.push(asset);
}

const output = {
  schemaVersion: 1,
  generatedFrom: ['static-snapshot/'],
  assetCount: assets.length,
  sourceSets: [
    {
      kind: 'app-static',
      localRoot: 'static-snapshot/bksxk.nwafu.edu.cn/xsxkapp/static/',
      description: '业务前端脚本快照，用于离线提取接口、函数和请求构造逻辑。',
    },
    {
      kind: 'xkres-public',
      localRoot: 'static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/',
      sourceOrigin: 'https://xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/',
      description: '页面引用的公开 JS、CSS、图片和 CSS 背景图。',
    },
  ],
  assets,
};

const serialized = `${JSON.stringify(output, null, 2)}\n`;
const cssFindings = await collectCssReferenceFindings();
const domFindings = await collectDomReferenceFindings();
const requiredStaticFindings = await collectRequiredStaticFindings();
const missingReferenceFindings = [...cssFindings, ...domFindings, ...requiredStaticFindings];

if (missingReferenceFindings.length > 0) {
  console.error('Static asset reference check failed. Missing or invalid local files:');
  for (const finding of missingReferenceFindings) {
    console.error(`- ${finding.source} -> ${finding.reference} expected ${finding.expectedLocalPath}`);
  }
  process.exit(1);
}

if (checkOnly) {
  const current = await readFile(outputPath, 'utf8');
  if (current !== serialized) {
    console.error(`${outputPath} is stale. Run: npm run static-assets`);
    process.exit(1);
  }
  console.log(`Static assets check passed: ${assets.length} files are current.`);
} else {
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, serialized);
  console.log(`Wrote ${outputPath} with ${assets.length} static files.`);
}
