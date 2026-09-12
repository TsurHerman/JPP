# Writing and inspecting binaries

Status: OPEN artifact design. The current tool emits Zig method data and builds
native programs. It does not load persisted jpp units, expose a stable external
ABI, implement invalidation, or hot-swap compiled code.

The target is a unit whose meaning is inspectable from its interface and method
data, whether authored as text or produced by another tool. Reconstructing
intent from source spelling should not be necessary.

A future artifact needs:

- Its public word identities and declaration-only requirements.
- Method signatures: positional and named fields, static values, type/predicate
  constraints, and any explicit result contracts.
- Original lexical homes and private identities, even inside a mutual-import unit.
- Body data or ground identity, dependency edges, source provenance, and a versioned
  encoding. Content hashes and compatibility rules remain to be implemented.
- The context dependencies determining a specialization. Runtime data is not an
  instance key; static selector values are.

The current REQUIREMENTS data records lexical call/gate names. It proves name
availability, not universal generic coverage or result compatibility. Ordinary
method signatures describe candidate domains; they are not a universal contract
for every future implementation of the word.

Source imports establish the unit graph. Mutual imports form one unit; folder
imports expose a combined public interface; neither permits access to another
file's private definitions. Compiled replacements must preserve those boundaries.
A context change can alter method selection or return type, so artifact reuse
must either prove compatibility or rebuild the affected specialization.

Portable exported function layout is a separate boundary. Canonical named pack
order makes language identity predictable but does not itself promise C layout,
cross-version serialization, or stable pointers into compiled code.
