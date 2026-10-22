# Dispatched cleanup with one scope primitive

Status: VALIDATED native probe, 2026-10-22. `zig build scope-probe` runs
`spike/scopeprobe.zig` against the active `src/jpp.zig`, plus a cleanup-error
rejection check. It is also part of `zig build probes`. Source callable values,
scope syntax, ownership and borrowing rules remain OPEN. Nothing here changes
the compiler or gives ordinary Zig grounds access to caller context.

## The useful split

The host controls **when** cleanup happens. Ordinary jpp methods control **what**
cleanup does. The primitive is small:

```zig
pub fn ensure(body: anytype, cleanup: anytype) @TypeOf(body).Return {
    if (@TypeOf(cleanup).Return != void)
        @compileError("cleanup must return void");
    defer cleanup.run();
    return body.run();
}
```

Both actions can be deferred jpp calls: a word, its captured argument pack and
its caller context. Capturing evaluates/copies arguments now but does not call
the word. `run` uses the normal `jpp.call`; it retains type identity and runtime
enum dispatch. Each action carries its own context. No runtime registry or
function-name lookup is needed; the existing specializer resolves the calls.

The resource adapter composes ordinary `acquire`, `use` and `release` words:

```zig
const acquired = jpp.call(ctx, "acquire", .{request});
const resource = try acquired; // for the fallible acquisition case
return ensure(
    bindCall(ctx, "use", .{ job, resource }),
    bindCall(ctx, "release", .{resource}),
);
```

The implementation also accepts infallible acquisition and preserves the body's
return type in that case. Fallible acquisition joins its finite error set with
the body's error set. This explicit adapter performs the `try`; dispatch itself
still supplies no implicit propagation. Failed acquisition installs no cleanup.

`release` can be an ordinary body calling `beforeRelease` and `destroy`. A
caller can override the audit hook deep inside that body, or replace `release`
with a pooling policy. The body has the same extension mechanism: the probe's
`use` calls `compute`, which the caller can override. Caller-first context,
specificity, declaration homes and dependency collapse remain the active
resolver's responsibility. Keep the full context when constructing actions:
collapsing it for `use` and reusing that reduced context for `release` would lose
cleanup-only overrides.

## What a source interface could look like

This is illustrative, NOT runnable syntax or a ratified API:

```text
withResource(bufferRequest(1024), checksumJob(seed))

use(job::Checksum, buffer::Buffer) = checksum(buffer, job.seed)
```

The public call can pass a job value carrying its inputs; it need not require a
closure at every use site. The internal composition would still need delayed
calls or regions:

```text
withResource(request, job) =
    withAcquired(acquire(request), job)

withAcquired(resource, job) =
    ensure(() -> use(job, resource), () -> release(resource))

release(buffer::Buffer) = destroy(buffer)
# A caller's policy module can instead define:
release(buffer::Buffer) = recycle(buffer)
```

`withAcquired` would need explicit error/success methods or another explicit
error-handling composition. The lambdas stand for unevaluated bodies with
captures; their syntax and callable application do not exist yet. A plain eager
`ensure(use(job, resource), release(resource))` cannot work: both arguments would
run before `ensure` gains control. Nor does a `defer` inside a short registration
helper attach cleanup to that helper's caller; it runs when the helper exits.

Two possible implementations remain OPEN: first-class context-bound actions,
or a staged block/region primitive which emits this same control flow. Either
must retain lexical call validation, private declaration homes and dependencies
through context collapse. The native host in this probe constructs actions
explicitly; it does not prove that source elaboration work is already done.

The recommendation is to keep the synchronous exit rule fixed and make the
actions ordinary dispatch points. Overriding the entire scheduling primitive
could skip, duplicate or retain cleanup, defeating its guarantee. The same
primitive could bracket allocation, a lease, a lock, or temporary state, with
resource-specific methods. Only allocation and a test lease are exercised here;
thread synchronization and transaction outcome policies are not implemented.

## Evidence and limits

The probe exercises real allocations through `std.testing.allocator`, so leaked
buffers fail tests. It checks acquisition and request production once, cleanup
after result production, body-error cleanup, acquisition-error bypass, finite
error sets, caller overrides in body/cleanup dependencies, pooling, caller order,
an infallible non-memory lease, delayed execution with captured values and runtime
enum cases, and nested error exits in reverse acquisition order. A negative
compilation check rejects fallible cleanup instead of silently dropping errors.
These are native probe promises, not new source-language promises.

Cleanup returns `void`; a fallible close operation must choose an explicit policy
inside its adapter. Reporting a close failure alongside the body result would
need a separate result-combining protocol. The guarantee covers normal returns
and returned errors, not panic unwinding, process termination, or asynchronous
cancellation. Zig `defer` executes on ordinary scope exits; it is not a general
unwinding mechanism. See the [Zig reference](https://ziglang.org/documentation/0.16.0/#defer).

This is deterministic cleanup, not a borrow checker. Captures are shallow copies;
actions are copyable and can be invoked again. A body can return a borrowed slice,
store an alias elsewhere, or release the resource itself. The final probe test
returns a slice descriptor after cleanup and inspects only its length, never the
freed allocation: the API does not reject that escape. Returning pointers cannot
simply be prohibited, because independently owned and static pointers can be valid
results. Ownership transfer, lifetime relationships and exclusive access remain
separate contracts. Scoped cleanup removes repetitive release calls while leaving
those memory-model decisions open.
