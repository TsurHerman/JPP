# JPP syntax coloring

A declarative TextMate grammar for `.jpp` files in VS Code, Cursor, and other
editors that accept VS Code language extensions. It follows the running syntax
in `src/jppc.zig`: `#` comments, strings and escapes, numbers, booleans, imports,
exports, `where`, words/calls, type and predicate annotations, operators,
projections, packs, and `...` rests/splats. Separate scopes identify method
declarations, signature inputs, module constants, local binding sites, named
fields, exact member-path patterns (including enum/error cases), guard calls,
and type versus predicate annotations. Standard scopes work with editor themes;
the optional vivid palettes below give these roles more distinct colors.
The extension also supplies comment toggling, bracket pairing, and indentation.

`zig{...}` embeds `source.zig` when a Zig extension is installed. A small fallback
colors Zig keywords, builtins, types, literals, and comments without it. Nested
braces, strings, characters, comments, and multiline Zig strings stay inside the
ground. Full Zig editing features require a Zig extension such as
`ziglang.vscode-zig`.

This is lexical coloring, not a language server: it does not resolve imports,
infer types, select methods, diagnose errors, or distinguish a defined signature
value from a fresh binder. Signature input coloring describes a syntactic role;
it does not imply that the name is a new variable. Declaration recognition is
lexical, so an unfinished or multiline bare call can resemble a signature.
References are not recolored by looking up their declarations. `Any` remains
an ordinary name, and capitalization is not treated as a type declaration. Coloring a construct
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

## More distinct colors

From this directory, apply the JPP palette to your editor's user settings:

```sh
npm run colors -- dark "$HOME/Library/Application Support/Cursor/User/settings.json"
# For VS Code on macOS, use .../Code/User/settings.json instead.
# Use light instead of dark when editing on a light background.
```

The command updates only its own `JPP vivid:` rules in
`editor.tokenColorCustomizations.textMateRules`. It preserves unrelated settings,
JSONC comments, existing color rules, and the selected editor theme. Every rule
targets JPP scopes; other languages and embedded Zig retain their theme colors.
Re-running replaces the palette without duplicating rules. If a theme-specific
customization already overrides these scopes, that customization takes priority.
The palette does not automatically switch when you change editor themes; rerun
with the matching mode. To undo, remove the rules named `JPP vivid:`.

| Role | Dark palette |
|---|---|
| Method declarations / calls | Bold gold / pale gold |
| Signature inputs | Orange |
| Type annotations / predicate annotations and guard calls | Teal / pink |
| Module constants / local binding sites | Violet / lavender, bold |
| Exact member-path cases | Coral, bold |
| Projected members / named fields | Blue / lime |
| Strings / numbers / booleans | Green / amber / rose |
| Named-section `;` / rest and splat `...` | Pink / violet, bold |

The palette files in `palettes/` can also be copied into settings manually.

## Render a local file

The same grammar works with Shiki to generate a standalone HTML file:

```sh
npm run render -- ../../tests/local_bindings/main.jpp preview.html
```

Open `preview.html` in any browser. It includes embedded Zig highlighting,
uses the same vivid palettes, automatically follows the system light/dark
appearance, and can be printed.
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
separate from `zig build test`; they do not change language semantics. Color
checks verify that key roles render differently, that both palettes provide at
least 4.5:1 contrast against the preview's backgrounds, and that applying a
palette preserves unrelated settings without adding duplicate rules.

References: [VS Code syntax highlighting](https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide),
[installing VSIX files](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace),
[Cursor extensions](https://prod.cursor.com/help/customization/extensions),
and [Shiki custom grammars](https://shiki.style/guide/load-lang).
