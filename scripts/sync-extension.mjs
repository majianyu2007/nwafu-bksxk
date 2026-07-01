import { copyFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

const ROOT = process.cwd();
const source = path.join(ROOT, 'userscripts', 'bksxk-guard.user.js');
const extensionDir = path.join(ROOT, 'extensions', 'bksxk-guard');
const target = path.join(extensionDir, 'bksxk-guard.user.js');

await mkdir(extensionDir, { recursive: true });
await copyFile(source, target);
console.log(`Synced ${path.relative(ROOT, source)} -> ${path.relative(ROOT, target)}`);
