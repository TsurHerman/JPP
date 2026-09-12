# Modules, visibility, and compilation units

Status: RUNS — verified by the complete suite on 2026-09-12. See the
[implementation plan](generality_plan.md) for the checks.

## Names come from paths

A file is a lexical home. `shop/tax.jpp` is `shop.tax`; `using shop.tax`
imports its exported words. Paths are absolute within the source tree.
`using shop` selects `shop/shop.jpp` as a package facade when it exists;
only its exports form the package interface. Otherwise shop aggregates its
children recursively. `using shop.*` explicitly imports the sibling files and
subfolder interfaces, excluding shop/shop.jpp. Child facades keep their own
public boundaries. The facade remains explicitly addressable as shop.shop.
A same-source `shop.jpp` and `shop/` collision is an error.

```text
# shop/shop.jpp
using shop.*
export create, quote
```

Exporting an imported word without a local body re-exports its implementations,
with original method homes intact. If there is no provider, the export is an
empty dependency declaration. Local method bodies remain the file's authored
contribution. No wrapper methods or synthetic fallback bodies are needed.

The bundled library has a namespace: Base/Arithmetic.jpp is Base.Arithmetic;
Base/Base.jpp is the facade used by `using Base`. That facade imports Base.*
and selects arithmetic, Any/order, Tuple utilities and check. No import is
hidden. Each program or library declares the foundation it needs; narrow leaf
imports remain useful for focused interfaces and tests.

Source definitions can replace bundled modules at the same qualified path.
A source `Base/Any.jpp` replaces that leaf. A source-root `Base.jpp` explicitly
replaces the bundled root interface; it is not combined with that interface.
This cross-root replacement is distinct from an ambiguous same-source collision.

## Visibility is a source fact

Private definitions belong to their file. Exported words are the public interface;
imports do not automatically re-export their dependencies. A sibling's words do
not appear merely because the sibling exists. Import that sibling, or declare
an intentional public dependency with `export word`.

```text
# shop/quote.jpp
using shop.tax
export quote
quote(net) = tax(net)
```

Importing shop in a program does not retrospectively declare tax in quote's
source. Declarations are checked even for bodies that are never called. A later
caller can choose an implementation of a declared word; it cannot cure a typo.

## Cycles form one unit

The user decision is that files connected by mutual imports are one unit,
including longer cycles. Private visibility remains file-local. Shared public
methods occupy one dispatch position; entry through a different member must not
silently choose a different winner. Separate maximal methods in that unit are
ambiguous at a call unless another candidate dominates them. A facade retains
its authored public view even when it participates in the unit; internal unit
visibility must not leak sibling exports through a restricted package API.

Unit formation is about import connectivity, not the `<:` relation. It must
neither add type-order edges nor infer transitive predicate membership.

## Context and folder composition

Caller context remains first. A selected method brings its home dependencies
behind that context. Specificity is pointwise; position breaks ties across
separate units/modules. A folder combines its descendants' exported methods;
it does not use alphabetical file order to resolve an ambiguity inside the
combined interface. Private helpers keep their original homes after aggregation.

Direct child enumeration is deterministic across files and subfolders. A folder
is an interface choice: importing two files separately retains separate context
positions, whereas importing their folder combines their public methods.

General qualified call syntax, separately persisted binary units, and hot
replacement remain future work. Dotted `using` paths already work.
