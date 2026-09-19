import { readFile, writeFile } from 'node:fs/promises';
import { basename, resolve } from 'node:path';
import { createHighlighter } from 'shiki';

const [input, output = 'preview.html', ...extra] = process.argv.slice(2);
if (!input || extra.length || resolve(input) === resolve(output)) {
  console.error('Usage: npm run render -- input.jpp [output.html] (use a separate output file)');
  process.exit(1);
}

const grammar = JSON.parse(await readFile(new URL('../syntaxes/jpp.tmLanguage.json', import.meta.url), 'utf8'));
const source = await readFile(input, 'utf8');
const highlighter = await createHighlighter({
  themes: ['github-dark', 'github-light'],
  langs: ['zig', { ...grammar, name: 'jpp' }],
});

try {
  const code = highlighter.codeToHtml(source, {
    lang: 'jpp',
    themes: { light: 'github-light', dark: 'github-dark' },
  });
  const title = basename(input).replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[c]);
  await writeFile(output, `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} · JPP</title>
<style>
  :root { color-scheme: light dark; }
  body { margin: 0; padding: 32px; background: #f6f8fa; color: #24292e; font-family: system-ui, sans-serif; }
  header { max-width: 1120px; margin: 0 auto 20px; }
  h1 { margin: 6px 0; font-size: 24px; font-weight: 600; }
  .label { color: #57606a; font-size: 12px; letter-spacing: .12em; }
  p { margin: 0; color: #57606a; font-size: 14px; }
  pre { max-width: 1120px; box-sizing: border-box; margin: auto; padding: 24px; overflow: auto; border: 1px solid #d0d7de; border-radius: 8px; }
  code { font: 13px/1.7 ui-monospace, SFMono-Regular, Consolas, monospace; tab-size: 4; }
  @media (prefers-color-scheme: dark) {
    body { background: #0d1117; color: #e6edf3; }
    .label, p { color: #8b949e; }
    pre { border-color: #30363d; }
    .shiki, .shiki span { color: var(--shiki-dark) !important; background-color: var(--shiki-dark-bg) !important; }
  }
  @media (max-width: 600px) { body { padding: 16px; } pre { padding: 16px; } }
  @media print { body { padding: 0; } pre { white-space: pre-wrap; overflow-wrap: anywhere; } }
</style>
<header><div class="label">JPP SOURCE</div><h1>${title}</h1><p>JPP with embedded Zig · follows your system appearance</p></header>
<main>${code}</main>
</html>
`);
  console.log(resolve(output));
} finally {
  highlighter.dispose();
}
