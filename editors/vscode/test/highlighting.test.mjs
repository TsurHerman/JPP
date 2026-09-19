import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, test } from 'node:test';
import textmate from 'vscode-textmate';
import oniguruma from 'vscode-oniguruma';
import zig from 'shiki/langs/zig.mjs';

const require = createRequire(import.meta.url);
const extension = fileURLToPath(new URL('../', import.meta.url));
const repo = fileURLToPath(new URL('../../../', import.meta.url));
const rawGrammar = JSON.parse(await readFile(join(extension, 'syntaxes/jpp.tmLanguage.json'), 'utf8'));
await oniguruma.loadWASM(await readFile(require.resolve('vscode-oniguruma/release/onig.wasm')));

const registries = [];
after(() => registries.forEach(registry => registry.dispose()));

function tokenize(grammar, source) {
  let state = textmate.INITIAL;
  const lines = source.split('\n').map(line => {
    const result = grammar.tokenizeLine(line, state);
    assert.equal(result.stoppedEarly, false);
    state = result.ruleStack;
    return result.tokens.map(token => ({
      text: line.slice(token.startIndex, token.endIndex),
      scopes: token.scopes,
    }));
  });
  return { lines, state };
}

function has(tokens, text, scope) {
  const scoped = tokens.map(token => token.scopes.some(s => s.startsWith(scope)) ? token.text : '\0').join('');
  assert.ok(scoped.includes(text),
    `Expected ${JSON.stringify(text)} in ${scope}: ${JSON.stringify(tokens)}`);
}

async function sources(directory) {
  const found = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) found.push(...await sources(path));
    else if (entry.name.endsWith('.jpp')) found.push(path);
  }
  return found;
}

for (const embedded of [false, true]) {
  const mode = embedded ? 'installed Zig grammar' : 'Zig fallback';
  const registry = new textmate.Registry({
    onigLib: Promise.resolve({
      createOnigScanner: patterns => new oniguruma.OnigScanner(patterns),
      createOnigString: value => new oniguruma.OnigString(value),
    }),
    loadGrammar: async scope => scope === 'source.jpp' ? rawGrammar
      : embedded ? zig.find(grammar => grammar.scopeName === scope) ?? null : null,
  });
  registries.push(registry);
  const grammar = await registry.loadGrammar('source.jpp');

  test(`JPP lexical roles with ${mode}`, () => {
    const source = [
      'using Base.Arithmetic # explicit imports',
      'using folder.*; export sum, <: ',
      'sum(x::T, rest<:Any...; scale::float64)::T where T = x',
      'main() = { saved = sum(1, 2.5; scale = 3.0); saved.payload; saved.0.1 }',
      '<:(Signed, Wide) = true',
      'literal() = "# where zig{ \\" still a string" # outside',
      'Any thing cases for mutable = false',
    ].join('\n');
    const { lines, state } = tokenize(grammar, source);
    has(lines[0], 'using', 'keyword.control.import.jpp');
    has(lines[0], 'Base.Arithmetic', 'entity.name.namespace.jpp');
    has(lines[0], '# explicit imports', 'comment.line.number-sign.jpp');
    has(lines[1], 'folder.*', 'entity.name.namespace.jpp');
    has(lines[1], 'export', 'keyword.control.jpp');
    has(lines[2], 'sum', 'entity.name.function.jpp');
    has(lines[2], '::', 'keyword.operator.annotation.jpp');
    has(lines[2], 'T', 'entity.name.type.jpp');
    has(lines[2], '<:', 'keyword.operator.annotation.jpp');
    has(lines[2], 'Any', 'entity.name.type.jpp');
    has(lines[2], '...', 'keyword.operator.spread.jpp');
    has(lines[2], 'where', 'keyword.control.jpp');
    has(lines[3], '2.5', 'constant.numeric.jpp');
    has(lines[3], 'payload', 'variable.other.property.jpp');
    has(lines[3], '0', 'variable.other.property.jpp');
    has(lines[3], '1', 'variable.other.property.jpp');
    has(lines[4], '<:', 'keyword.operator.jpp');
    has(lines[4], 'true', 'constant.language.boolean.jpp');
    has(lines[5], '# where zig{', 'string.quoted.double.jpp');
    has(lines[5], '\\"', 'constant.character.escape.jpp');
    has(lines[5], '# outside', 'comment.line.number-sign.jpp');
    for (const name of ['Any', 'thing', 'cases', 'for', 'mutable']) {
      has(lines[6], name, 'variable.other.jpp');
    }
    assert.equal(state.depth, 1);
  });

  test(`Zig boundaries with ${mode}`, () => {
    const source = [
      'ground(x)::type = zig{ blk: {',
      '    const T = struct { value: i64, };',
      '    const text = "} # not JPP"; // } not the end',
      "    const brace = '}';",
      '    const lines =',
      '        \\\\ } still Zig text',
      '    ;',
      '    break :blk @TypeOf(T{ .value = x });',
      '} }',
      'after() = true # back in JPP',
    ].join('\n');
    const { lines, state } = tokenize(grammar, source);
    has(lines[0], 'zig', 'keyword.control.ground.jpp');
    has(lines[1], 'const', 'keyword');
    has(lines[1], 'i64', embedded ? 'keyword.type' : 'storage.type');
    has(lines[2], '} # not JPP', 'string');
    has(lines[2], '// } not the end', 'comment');
    has(lines[3], '}', 'string');
    has(lines[5], '} still Zig text', 'string');
    has(lines[7], '@TypeOf', 'support.function');
    has(lines[7], '@TypeOf', 'meta.embedded.block.zig');
    has(lines[9], 'after', 'entity.name.function.jpp');
    has(lines[9], '# back in JPP', 'comment.line.number-sign.jpp');
    assert.ok(lines[9].every(token => !token.scopes.includes('meta.embedded.block.zig')));
    assert.equal(state.depth, 1);
  });

  test(`repository source boundaries with ${mode}`, async () => {
    const files = [...await sources(join(repo, 'Base')), ...await sources(join(repo, 'tests'))];
    assert.ok(files.length > 200);
    for (const file of files) {
      const { state } = tokenize(grammar, await readFile(file, 'utf8'));
      assert.equal(state.depth, 1, `Unclosed highlighting scope in ${file}`);
    }
  });
}

test('standalone rendering escapes source and filenames and preserves its input', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'jpp-highlight-'));
  try {
    const input = join(directory, '<img onerror=alert(1)>.jpp');
    const output = join(directory, 'preview.html');
    const source = '# <script>alert(1)</script>\nmain() = "<&>"\n';
    await writeFile(input, source);
    execFileSync(process.execPath, [join(extension, 'scripts/render.mjs'), input, output]);
    const html = await readFile(output, 'utf8');
    assert.ok(html.includes('&lt;img onerror=alert(1)&gt;.jpp'));
    assert.match(html, /(?:&lt;|&#x3C;)script(?:&gt;|>)alert\(1\)(?:&lt;|&#x3C;)\/script(?:&gt;|>)/);
    assert.ok(html.includes('class="shiki'));
    assert.ok(html.includes('--shiki-dark'));
    assert.doesNotMatch(html, /<script|<img|https?:\/\//i);
    assert.throws(() => execFileSync(process.execPath,
      [join(extension, 'scripts/render.mjs'), input, input], { stdio: 'pipe' }));
    assert.equal(await readFile(input, 'utf8'), source);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
