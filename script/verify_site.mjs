#!/usr/bin/env node

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, extname, join, normalize, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const siteRoot = join(repoRoot, 'site');
const failures = [];

function walk(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? walk(path) : [path];
  });
}

function fail(file, message) {
  failures.push(`${relative(repoRoot, file)}: ${message}`);
}

const htmlFiles = walk(siteRoot).filter((file) => extname(file) === '.html');

for (const file of htmlFiles) {
  const html = readFileSync(file, 'utf8');
  const h1Count = (html.match(/<h1(?:\s|>)/g) || []).length;
  const launchStatePage = /<body class="dl-(?:soon|live)">/.test(html);
  if (h1Count !== 1 && !(launchStatePage && h1Count === 2)) {
    fail(file, `expected one active h1, found ${h1Count}`);
  }
  if (!/<title>[^<]+<\/title>/.test(html)) fail(file, 'missing title');
  if (!/<meta name="description" content="[^"]+">/.test(html)) fail(file, 'missing meta description');
  if (!/<link rel="canonical" href="https:\/\/bulong\.app\/[^"]*">/.test(html)) fail(file, 'missing Bulong canonical URL');
  if (!/<meta property="og:image:alt" content="[^"]+">/.test(html)) fail(file, 'missing og:image:alt');

  for (const match of html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) {
    try {
      JSON.parse(match[1]);
    } catch (error) {
      fail(file, `invalid JSON-LD (${error.message})`);
    }
  }

  for (const match of html.matchAll(/\b(?:href|src|poster|data-src)="([^"]+)"/g)) {
    const value = match[1];
    if (/^(?:https?:|mailto:|tel:|#|data:)/.test(value)) continue;
    const clean = value.split(/[?#]/, 1)[0];
    if (!clean) continue;
    const target = clean.startsWith('/')
      ? join(siteRoot, clean)
      : resolve(dirname(file), clean);
    if (!existsSync(normalize(target))) fail(file, `missing local target ${value}`);
  }
}

const allPublicText = htmlFiles.map((file) => readFileSync(file, 'utf8')).join('\n');
for (const phrase of ['fonts.googleapis.com', 'The contact form is warming up', 'The calendar is warming up']) {
  if (allPublicText.includes(phrase)) failures.push(`public HTML still contains "${phrase}"`);
}

if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}

console.log(`Verified ${htmlFiles.length} HTML pages and their local assets.`);
