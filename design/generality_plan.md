# Generality implementation sequence

Revised 2026-09-12 after review and the module/unit decisions. This supersedes
the earlier feature-by-feature sequence, which postponed dependency visibility
and static fields until after consumers were already built.

The purpose is reusable libraries and inspectable binary units, exercised in
real module trees. Membership, identity, preference, and conversion remain
distinct. Keep caller-first context, pointwise dominance, and explicit pairwise
order. The active compiler and tests determine RUNS status.

## 1. Foundations

RUNS — verified 2026-09-12:

- An export without a body declares a word and supplies no dispatch candidate.
  Check calls and gates in every source body against real local/imported/exported
  declarations. A caller cannot introduce a missing source name.
- Explicit folder imports recursively collect public exports. Base is the
  namespace root; Base.Arithmetic, Base.Any, Base.Test and Base.Tuple are leaves.
  Remove hidden imports; optional same-name facades select package exports,
  while Folder.* explicitly imports siblings excluding the facade.
- Mutual imports form one dispatch/compilation unit. Private definitions remain
  file-local. Public candidates share one unit position; same-unit ambiguity
  cannot depend on which member was imported first.
- Specify static fields before extending packs: their values participate in
  specialization, ordinary runtime fields contribute only their types. Preserve
  static fields through projection and forwarding without deleting effects.
- Settle current named-field comparison and the next varargs decision table in
  [packs.md](packs.md). Varargs remain unbuilt.

Evidence: declaration_tunnel, override, undeclared_call, undeclared_unused_call,
undeclared_gate, undefined_export, base_folder, folder_modules, folder_collision,
Base shadowing cases, unit cases, and pack_static. Full typed contracts remain
OPEN; name availability is not a universal implementation-coverage proof.

## 2. Tuples and required named arguments

RUNS — verified 2026-09-12:

- Tuple, named-record, and mixed pack values share a representation with calls.
  Grouping, empty, singleton, heterogeneous values, and named identity are explicit.
- Static positional and named projections; ordinary Tuple utilities.
- Required named inputs bind by name and participate in dispatch. No cross-fill,
  defaults, splats, or rest capture yet.
- Preserve source evaluation order while canonicalizing value identity and bound
  method instances. Compare matching coordinates across declaration permutations.
- Checkout uses tuple basket storage, named quote construction, and surface field
  access. It retains its two-line public basket contract until varargs land.

Evidence: pack_values, pack_static, named_arguments, named_specificity,
named_context, named_instances, type-witness mismatch and malformed pack cases,
and the existing checkout receipts under two fresh caller contexts.

The build must regenerate source trees and rerun negative compilation checks;
a cached process result for an old generated file is not fresh validation.

Verification on 2026-09-12: `zig build test demo probes --summary all` passed
all 246 build steps, covering 97 language cases (including 41 expected compile
rejections and 11 expected frontend rejections) and 45 machinery/probe tests.
`zig test src/ast.zig` passed all three AST tests. The obsolete emitter and
hand-transpiled demos were subsequently removed; the research probes remain.

## 3. Varargs and forwarding

Next implementation slice. Implement the decision table in packs.md first,
then one trailing positional rest and call-side splat, followed by named-rest
capture. Apply specificity to actual supplied coordinates and accepted pack
shape. Preserve empty-tail unification and ambiguity rules.

Use shrinking reductions with explicit empty identities and separate one/two/many
arity domains. A missing binary promotion must fail rather than recurse forever.
Evolve checkout to zero/one/many heterogeneous physical and digital lines. Measure
0, 1, 2, 8 and 32-element cases; runtime-sized collections are separate work.

## 4. Static computation and callable types

Generalize static calculations, expose brace application with the same semantic
pack and word table, and reject unavailable runtime selectors. Constructor aliases
and known callable values need dependency discovery and private-home preservation
before context collapse. Test deep caller overrides through an alias.

Compare literal/computed static selectors, keyword permutations, and different
runtime data at the bound method's instance identity. Runtime closed-domain
selector bridging and general closures are later extensions.

## 5. Independent library increments

Develop [type families](type_families.md) and [mixed arithmetic](numerics.md)
as separate increments; neither needs to wait for every feature in the other.
Ordinary predicate families can grow throughout all stages.

Type families need supported selector patterns, repeated identity constraints,
re-application provenance, and explicit nominal-record construction. Anonymous
structural values must keep their existing identity rules.

Numerics need a finite promotion/conversion matrix and explicit failure behavior.
Resolve the exact-conversion policy before copying any ground implementation.
Add expected runtime-failure support before testing value-dependent conversion
errors. Keep richer arithmetic explicitly imported initially.

## 6. Integration and binary interface evidence

Add a numerical module tree with mixed-element vectors and dot products sharing
a dimension binder. Exercise named options, forwarding, predicates, private
helpers, and caller policies through several modules. Mismatched dimensions and
missing implementations must diagnose the actual boundary.

At every implementation milestone: add meaningful test.md promises and positive/
negative programs, run zig build test, demo and affected probes, update verified
status, then commit and push. Measure representative compilation cost. Binary
artifact loading, hot replacement, ownership and compiler bootstrapping remain
future work described in [binary_units.md](binary_units.md).
