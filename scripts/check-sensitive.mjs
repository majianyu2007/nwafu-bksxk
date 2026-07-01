import { readdir, readFile, stat } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const scanRoots = [
  'README.md',
  '.gitignore',
  'package.json',
  'package-lock.json',
  'docs',
  'scripts',
  'snapshots',
  'static-snapshot',
  'userscripts',
  'extensions',
];

const ignoredPathParts = new Set([
  '.git',
  '.playwright-mcp',
  'artifacts',
  'node_modules',
]);

const ignoredFiles = new Set([
  path.normalize('extensions/bksxk-guard/bksxk-guard.user.js'),
]);

const textExtensions = new Set(['', '.css', '.html', '.js', '.mjs', '.json', '.md', '.txt', '.yml', '.yaml']);

const rules = [
  {
    name: 'uuid-token',
    pattern: /\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/gi,
  },
  {
    name: 'token-query',
    pattern: /token=(?!$|<token>|<redacted>)[0-9a-f-]{20,}/gi,
  },
  {
    name: 'token-header',
    pattern: /token:\s*(?!<token>|<redacted>)[0-9a-f-]{20,}/gi,
  },
  {
    name: 'student-path',
    pattern: /\/student\/\d{6,}\.do\b/gi,
  },
  {
    name: 'numeric-login-name-query',
    pattern: /loginName=(?!<studentCode>|<redacted>|$)\d{6,}/gi,
  },
  {
    name: 'password-query',
    pattern: /loginPwd=(?!<password>|<redacted>|$)[^&\s"'`]+/gi,
  },
  {
    name: 'captcha-query',
    pattern: /verifyCode=(?!<captcha>|<redacted>|$)[^&\s"'`]+/gi,
  },
  {
    name: 'captcha-token-query',
    pattern: /vtoken=(?!<vtoken>|<redacted>|$)[^&\s"'`]+/gi,
  },
  {
    name: 'student-code-query',
    pattern: /studentCode=(?!<studentCode>|<redacted>|\{studentCode\}|$)\d{6,}/gi,
  },
  {
    name: 'student-xh-query',
    pattern: /xh=(?!<studentCode>|<redacted>|\{xh\}|$)\d{6,}/gi,
  },
  {
    name: 'sensitive-json-string',
    pattern: /"(studentCode|xh|loginName|loginPwd|verifyCode|vtoken)"\s*:\s*"(?!<[^>]+>|string|<redacted>)[^"]+"/gi,
  },
  {
    name: 'sensitive-json-string-escaped',
    pattern: /\\"(studentCode|xh|loginName|loginPwd|verifyCode|vtoken)\\"\s*:\s*\\"(?!<[^>]+>|string|<redacted>)[^"\\]+\\"/gi,
  },
  {
    name: 'encoded-student-code',
    pattern: /studentCode%22%3A%22(?!%3Credacted%3E|%3CstudentCode%3E)[^%&"]+%22/gi,
  },
  {
    name: 'encoded-xh',
    pattern: /xh%22%3A%22(?!%3Credacted%3E|%3CstudentCode%3E)[^%&"]+%22/gi,
  },
];

function shouldIgnore(relativePath) {
  const normalized = path.normalize(relativePath);
  if (ignoredFiles.has(normalized)) return true;
  return normalized.split(path.sep).some((part) => ignoredPathParts.has(part));
}

function isTextFile(filePath) {
  return textExtensions.has(path.extname(filePath));
}

function isAllowedMatch(matchText) {
  return matchText.includes('<redacted>')
    || matchText.includes('<token>')
    || matchText.includes('<vtoken>')
    || matchText.includes('<studentCode>')
    || matchText.includes('<password>')
    || matchText.includes('<captcha>');
}

function isAllowedRuleLine(line) {
  return line.includes('.replace(/')
    || /\+\s*(?:studentCode|xh|loginName|loginPwd|verifyCode|vtoken)\s*\+/.test(line);
}

async function collectFiles(entryPath, out = []) {
  const relativePath = path.relative(root, entryPath);
  if (shouldIgnore(relativePath)) return out;

  let info;
  try {
    info = await stat(entryPath);
  } catch {
    return out;
  }

  if (info.isDirectory()) {
    const entries = await readdir(entryPath);
    for (const entry of entries) {
      await collectFiles(path.join(entryPath, entry), out);
    }
    return out;
  }

  if (info.isFile() && isTextFile(entryPath)) out.push(entryPath);
  return out;
}

const files = [];
for (const scanRoot of scanRoots) {
  await collectFiles(path.join(root, scanRoot), files);
}

const findings = [];

for (const filePath of files.sort()) {
  const relativePath = path.relative(root, filePath);
  const raw = await readFile(filePath, 'utf8');
  const lines = raw.split(/\r?\n/);

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (isAllowedRuleLine(line)) continue;

    for (const rule of rules) {
      rule.pattern.lastIndex = 0;
      for (const match of line.matchAll(rule.pattern)) {
        if (isAllowedMatch(match[0])) continue;
        findings.push({
          file: relativePath,
          line: index + 1,
          rule: rule.name,
          match: match[0].slice(0, 120),
        });
      }
    }
  }
}

if (findings.length > 0) {
  console.error('Sensitive check failed. Review these possible leaks:');
  for (const finding of findings) {
    console.error(`- ${finding.file}:${finding.line} [${finding.rule}] ${finding.match}`);
  }
  process.exit(1);
}

console.log(`Sensitive check passed: scanned ${files.length} text files.`);
