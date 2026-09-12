# Declared words and implementation obligations

Status: RUNS for export-only declarations and lexical call/gate checking — verified
by the complete suite on 2026-09-12. Typed word contracts remain OPEN.

## What a declaration means

```text
# api.jpp
export probe, tag
probe(x) = tag(x)
```

`tag` has a source-visible identity. An export with public imported providers
re-exports their implementations without wrapper methods. With no provider,
the declaration adds no method, cannot win
a tie, and does not claim that every input is supported. A caller must supply an
applicable implementation for each concrete call. An unused exported requirement
need not have an implementation. A meaningful real fallback remains optional.

Without `export tag`, a definition, or an import, the reference is an error even
when a later caller exports tag. Check unused bodies too: an uninstantiated typo
is still a missing declaration. A caller chooses implementation, not spelling.

Imports expose public words. Private definitions remain file-local, including
inside a mutual-import unit. Unit/folder assembly preserves the original home
of method bodies and predicates. An aggregate does not erase lexical ownership.

The emitted REQUIREMENTS metadata records each body's called/gate words. It is
checked by the machinery against lexical declarations; jppc emits the facts and
assembles the module graph without resolving calls or inferring argument types.

## What this does not prove

A word name alone describes neither its complete domain nor a result contract.
An implemented `tag(::int64)` supplies one domain, not a limit on future methods.
`Any` is an ordinary predicate, not proof that a required operation is total.
An authored order fact is not evidence of logical implication between predicates.

The next contract feature should describe input packs and result constraints
without contributing a dispatch candidate. One word may need multiple signatures.
Generic requirements remain conditional on concrete bound types and context unless
an explicit proof mechanism is added.

At instantiation, a contract must check the selected caller implementation,
not just the library's fallback. A violated result contract or missing dependency
must not silently discard the winning method and retry a less preferred method.
That would change dispatch applicability.

## Decisions still required

- How input/result contracts are written using the existing pack vocabulary.
- How compatible contracts fuse by exported word identity, and how conflicts fail.
- Whether a contract predicate uses declaration context or accumulated caller context.
- How generic obligations and their source provenance appear in an inspection tool.
- What a persisted binary retains and which changes invalidate its instances.

Universal implication between arbitrary predicates cannot be inferred from `<:`,
rank, spelling, or missing edges. Concrete pack/result checks are evidence for
that specialization only. Keep that boundary explicit in documentation and errors.

Precedents informed the separation of declaration and behavior: Julia empty
generics, Dylan generic-function protocols, Rust required trait methods, and
OCaml module signatures. They do not dictate jpp's scope, fusion, or order rules.
