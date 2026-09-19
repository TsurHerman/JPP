# JPP syntax coloring

A declarative TextMate grammar for `.jpp` files in VS Code, Cursor, and other
editors that accept VS Code language extensions. It follows the running syntax
in `src/jppc.zig`: `#` comments, strings and escapes, numbers, booleans, imports,
exports, `where`, words/calls, type and predicate annotations, operators,
projections, packs, and `...` rests/splats. Colors come from your editor theme.
The extension also supplies comment toggling, bracket pairing, and indentation.

`zig{...}` embeds `source.zig` when a Zig extension is installed. A small fallback
colors Zig keywords, builtins, types, literals, and comments without it. Nested
braces, strings, characters, comments, and multiline Zig strings stay inside the
ground. Full Zig editing features require a Zig extension such as
`ziglang.vscode-zig`.

This is lexical coloring, not a language server: it does not resolve imports,
infer types, select methods, diagnose errors, or distinguish a defined signature
value from a fresh binder. `Any` remains an ordinary name. Coloring a construct
does not establish that it compiles. In particular, the editor handles Zig
comments/characters/multiline strings while the current transpiler's ground
capture only skips double-quoted strings when counting braces.

## Install in VS Code or Cursor

Building the package and local previews uses **Node.js 22+ and npm**. These are
optional editor tooling dependencies; the JPP compiler still needs only Zig 0.16.
From this directory:

```sh
npm ci
npm test
npm run package
cursor --install-extension ./jpp-language.vsix
# Or, for VS Code:
code --install-extension ./jpp-language.vsix
```

Alternatively, run **Extensions: Install from VSIX…** in the editor's command
palette and select `jpp-language.vsix`. Reload the editor window if a file was
already open. `.jpp` files select **JPP** automatically; you can also choose JPP
from the language indicator. No workspace settings or theme changes are needed.
The local extension ID is `jpp-local.jpp-language`; this is not a marketplace
publication. The installed extension has no executable code or npm dependencies.

For development, launch a separate window with this directory as
`--extensionDevelopmentPath` (an absolute path), then open a `.jpp` file.
**Developer: Inspect Editor Tokens and Scopes** shows the assigned scopes.

## Render a local file

The same grammar works with Shiki to generate a standalone HTML file:

```sh
npm run render -- ../../tests/local_bindings/main.jpp preview.html
```

Open `preview.html` in any browser. It includes embedded Zig highlighting,
automatically follows the system light/dark appearance, and can be printed.
Rendering runs locally. The resulting page contains static HTML/CSS, needs no
server or network access, and can be shared as one file. Re-run the command after
editing the source. Input/output paths are relative to the current directory;
the output defaults to `preview.html`.

Other local renderers can load `syntaxes/jpp.tmLanguage.json` as a TextMate
grammar (`source.jpp`). With Shiki, register that object with `name: 'jpp'` and
load `zig` as well; see `scripts/render.mjs`. An Electron shell by itself does not
provide syntax support: its editor/renderer must load the grammar. This does not
automatically add JPP coloring to GitHub or unrelated Markdown viewers.

## Validation

`npm test` runs the actual TextMate/Oniguruma tokenizer, both with and without
Shiki's Zig grammar. It checks JPP scopes, embedded-language boundaries, and
tokenizes the repository's Base and test sources. It also checks the rendered
HTML with hostile-looking source text and filenames. These tooling checks are
separate from `zig build test`; they do not change language semantics.

References: [VS Code syntax highlighting](https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide),
[installing VSIX files](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace),
[Cursor extensions](https://prod.cursor.com/help/customization/extensions),
and [Shiki custom grammars](https://shiki.style/guide/load-lang).
