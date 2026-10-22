import { readFile, writeFile } from 'node:fs/promises';
import { parse, modify, applyEdits } from 'jsonc-parser';

const [mode, file, ...extra] = process.argv.slice(2);
if (!['dark', 'light'].includes(mode) || !file || extra.length) {
  console.error('Usage: npm run colors -- dark|light /path/to/editor/User/settings.json');
  process.exit(1);
}

const palette = JSON.parse(await readFile(new URL(`../palettes/${mode}.json`, import.meta.url), 'utf8'));
const original = await readFile(file, 'utf8');
const errors = [];
const settings = parse(original, errors, { allowTrailingComma: true });
if (errors.length || !settings || Array.isArray(settings) || typeof settings !== 'object') {
  throw new Error('Settings must be a valid JSON/JSONC object; no changes written.');
}
const current = settings['editor.tokenColorCustomizations']?.textMateRules ?? [];
if (!Array.isArray(current)) throw new Error('Existing textMateRules is not an array; no changes written.');
const rules = [
  ...current.filter(rule => !rule.name?.startsWith('JPP vivid: ')),
  ...palette.textMateRules,
];
const edits = modify(original, ['editor.tokenColorCustomizations', 'textMateRules'], rules, {
  formattingOptions: { insertSpaces: true, tabSize: 2, eol: original.includes('\r\n') ? '\r\n' : '\n' },
});
await writeFile(file, applyEdits(original, edits));
console.log(`Applied ${mode} JPP colors to ${file}`);
