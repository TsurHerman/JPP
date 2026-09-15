# JSON serialization by injected dispatch tables

Starting point: Zig 0.16 `std.json.Value.jsonStringify`. This case consumes the
actual std union and uses std parsing/writing leaves. The complete walkthrough
and before/after comparison are in [dispatch_tables](../../design/dispatch_tables.md).

Read the small behavior modules first:

- `json/scalars.jpp`: one shared scalar rule, null and raw-number rules.
- `json/containers.jpp`: one container body with declarations for differences.
- `json/traversal.jpp`: runtime cursor steps dispatch to done/item/field methods;
  nested values re-enter the caller-derived emit word.
- `policy/masked.jpp`, `policy/numbers.jpp`: independent string/integer policies
  restricted to Masked writers, using ordinary predicates and authored order.
- `model.jpp`: native union predicates, cursor constructors and bounded writer
  leaves. No copied std.json.Value definition and no context callbacks in grounds.
- `suite.jpp`: shared checks; `plain.jpp` and `custom.jpp` are fresh contexts.

Promises:

- Four scalar variants share a definition; arrays/objects share their traversal.
- Both writer families behave normally in the base context. In the custom context
  Plain keeps ordinary behavior while Masked changes strings and integers inside
  nested arrays/objects. Keys and raw-number strings remain distinct domains.
- Default output equals std's serializer for all eight tags, escaping, empty and
  nested containers, large raw numbers, and arrays of 0/1/8/128 runtime elements.
- A two-byte sink reports the first write error. No later write or cursor advance
  occurs after the failure. Only selected arms perform IO.
- Explicit static writer policy fields and refined union identity survive helpers,
  source imports, the facade, type computation and recursive calls.

The fixture is limited to 8192 output bytes, valid input, and std's safety-mode
nesting limit. It stores the first output error in writer state; general error
syntax is unbuilt. Payload snapshots retain references into the parsed document,
which remains alive until rendering ends. This case does not promise bounded
stack consumption for arbitrary document depth/length or replace std.json.

Verified 2026-09-15: 38 assertions across two programs pass under Debug and
ReleaseSafe. The full test/demo/probe build passes 309/309 steps and 52/52
machinery/probe tests. See the implementation plan for the local build sample.
