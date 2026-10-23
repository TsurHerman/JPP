# Explicit callable reflection

`Base.Reflection` exposes ordinary values describing a closure or an explicitly
bound word. `reflect` reports its kind, identity, original source location,
declaration home, captured creation context, signature, and captured field types
and static facts. Describing a value does not execute its body.
Word descriptions also list their visible authored methods. Creation-context
positions agree between this inventory and later call analysis, even when an
irrelevant module precedes the provider. Receiver modules do not enter the
captured context. Captured type values retain their exact static identity.

`analyze(f, pack)` checks the actual pack's types and explicit static facts.
For a fixed closure this checks binding to its single signature. For a bound
word it uses the same resolver as invocation and returns selected, missing,
ambiguous, or cyclic-order outcomes. Candidate records retain declaration
sources, homes, applicability rejection stages, an actual dominating candidate
when present, and maximality. Context position decides between modules only
after pointwise dominance; conflicting maxima in the winning module remain
ambiguous. Analysis does not instantiate the chosen body. `returnType` is the
separate, strict body-typing query and can issue ordinary compiler errors.
The intrinsic identity floor and pairwise fallback of `<:` are reported as
explicit selection kinds with no selected authored candidate. Rejected methods
seen again through another module view remain one candidate.

Runtime enum, tagged-union and error inputs can need injected branches. The
initial word analysis reports `incomplete` for unresolved inputs of those kinds;
it does not pretend that an unsplit fallback is the final winner. Known enum
facts can be analyzed. Reflection does not inspect runtime payloads, execute
callbacks, or give native grounds an ambient dispatch context.
