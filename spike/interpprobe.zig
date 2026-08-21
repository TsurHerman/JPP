// interpprobe.zig — the two interpreters: methods as PURE DATA.
//
// ratified: a transpiled method is five facts (name, signature, body,
// hash, span), all data. per-method functions (bind/bindValues/Ret/call)
// are replaced by ONE interpreter each in the machinery:
//
//   signature interpreter — construct(sig, Raw): walks the signature
//     datum against a raw call-site pack; returns the bound pack type or
//     null. specificity is COMPUTED from the datum during resolution
//     (rank is a byproduct, never stored).
//   body interpreter — exec(ctx, flat, bound): comptime-unrolled walk of
//     the ANF op vector; inferred return types come from the type-level
//     twin of the same walk. `inline for` unrolls, so the compiled code
//     is as if hand-written.
//
// ground bodies are the exception by design: the transpiler prints
// zig{} source as real functions in the module file; the method datum
// references them. axioms in the machinery, data in the modules.

const std = @import("std");

// --- the data model: a method is five facts -----------------------------------

const Qual = union(enum) {
    exact: type, //          x::int64
    pred: fn (type) bool, // x<:Integer (probe: direct fn; real: word in ctx)
    bare, //                 x
};

const Slot = struct {
    name: []const u8,
    section: enum { positional, named } = .positional,
    qual: Qual,
};

const ValRef = union(enum) { param: usize, local: usize };
const Op = struct { callee: []const u8, args: []const ValRef };
const Flat = struct { ops: []const Op, result: ValRef };

const Body = union(enum) {
    ops: Flat, //   jpp-level: vector of Expr in ANF
    ground: type, // axiom: printed zig fn (pub const ret; pub fn run)
};

const Method = struct {
    name: []const u8,
    signature: []const Slot,
    body: Body,
    hash: u64 = 0, //        over the normalized body (carried, unused here)
    span: [2]u32 = .{ 0, 0 },
};

fn MultiMethod(comptime word: []const u8, comptime list: []const Method) type {
    return struct {
        pub const is_mm = true;
        pub const name = word;
        pub const methods = list;
    };
}

// --- signature interpreter ------------------------------------------------------

fn positionOf(comptime name: []const u8) ?usize {
    return std.fmt.parseInt(usize, name, 10) catch null;
}

fn qualOk(comptime q: Qual, comptime T: type) bool {
    return switch (q) {
        .exact => |E| T == E,
        .pred => |P| P(T),
        .bare => true,
    };
}

/// raw pack type -> bound pack type (declared slot order) or null.
fn construct(comptime sig: []const Slot, comptime Raw: type) ?type {
    comptime {
        @setEvalBranchQuota(100_000);
        const rf = @typeInfo(Raw).@"struct".fields;
        if (rf.len != sig.len) return null;
        var types = [_]?type{null} ** sig.len;
        for (rf) |f| {
            if (positionOf(f.name)) |p| {
                if (p >= sig.len or sig[p].section != .positional) return null;
                if (types[p] != null) return null;
                if (!qualOk(sig[p].qual, f.type)) return null;
                types[p] = f.type;
            } else {
                const idx = for (sig, 0..) |s, i| {
                    if (s.section == .named and std.mem.eql(u8, s.name, f.name)) break i;
                } else return null;
                if (types[idx] != null) return null;
                if (!qualOk(sig[idx].qual, f.type)) return null;
                types[idx] = f.type;
            }
        }
        var names: [sig.len][]const u8 = undefined;
        var ts: [sig.len]type = undefined;
        for (sig, 0..) |s, i| {
            names[i] = s.name;
            ts[i] = types[i] orelse return null;
        }
        return @Struct(.auto, null, &names, &ts, &@splat(.{}));
    }
}

// --- specificity policy — A SHADOWABLE WORD ---------------------------------------
// the entitlement principle: importing grants standing to shadow — methods
// AND decisions. the policy is a word (`specificity`) resolved through the
// context; the ground default (pointwise dominance) lives here. circularity
// break: the judge is chosen by SENIORITY, not by judging — first module in
// the context that declares `specificity` wins, position only, no ranking
// involved in selecting the ranker.
//
// policy contract: moreSpecific(ctx, a, b) — STRICT: true iff a displaces
// b; false on equal AND incomparable, so both fall to position. ground
// policy: pointwise dominance (a >= everywhere, > somewhere). within-module
// equal/incomparable overlap is the transpiler's ambiguity error, not ours.
// (probe simplification: slot-by-slot alignment; the full rule compares
// per-pack PROJECTIONS — variadic 0, record slots aligned by name.)

const ground_policy = struct {
    pub fn moreSpecific(comptime ctx: anytype, comptime a: []const Slot, comptime b: []const Slot) bool {
        _ = ctx; // ground dominance needs no context; shadowing policies may
        comptime {
            if (a.len != b.len) return false;
            var strictly: bool = false;
            for (a, b) |sa, sb| {
                const ra = slotRank(sa.qual);
                const rb = slotRank(sb.qual);
                if (ra < rb) return false; // b wins somewhere: not dominant
                if (ra > rb) strictly = true;
            }
            return strictly;
        }
    }
};

fn policyOf(comptime ctx: anytype) type {
    comptime {
        for (0..ctx.len) |i| {
            if (@hasDecl(ctx[i], "specificity")) return @field(ctx[i], "specificity");
        }
        return ground_policy;
    }
}

fn slotRank(comptime q: Qual) u32 {
    return switch (q) {
        .exact => 3,
        .pred => 2,
        .bare => 1,
    };
}

/// value routing raw -> bound (machinery, not per-method code).
fn bindValues(comptime sig: []const Slot, comptime B: type, raw: anytype) B {
    var out: B = undefined;
    inline for (@typeInfo(@TypeOf(raw)).@"struct".fields) |f| {
        const target = comptime if (positionOf(f.name)) |p| sig[p].name else f.name;
        @field(out, target) = @field(raw, f.name);
    }
    return out;
}

// --- resolution (rank computed on the fly) --------------------------------------

// --- context collapse: project the context onto the word FOOTPRINT ---------------
// the instance cache keys on the context; accumulated contexts carry
// irrelevant sediment. resolution only reads modules that DECLARE the
// words involved — and bodies are DATA, so the reachable word set is a
// closure computable before instantiation: word + all body callees,
// transitively, over every candidate in context (over-approximation:
// safe). collapse = keep only modules declaring a footprint word (or
// the policy word), order preserved. identical collapsed tuples ->
// zig memoizes ONE instantiation -> one instance, one symbol.
// (real machinery must also add signature predicate WORDS to the
// footprint; probe predicates are raw fns, so only the policy word.)

fn containsWord(comptime words: []const []const u8, comptime w: []const u8) bool {
    for (words) |x| if (std.mem.eql(u8, x, w)) return true;
    return false;
}

fn footprint(comptime ctx: anytype, comptime word: []const u8) []const []const u8 {
    comptime {
        @setEvalBranchQuota(1_000_000);
        var words: [64][]const u8 = undefined;
        var n: usize = 0;
        words[0] = word;
        n = 1;
        var changed = true;
        while (changed) {
            changed = false;
            for (0..n) |wi| {
                const w = words[wi];
                for (0..ctx.len) |mi| {
                    if (!@hasDecl(ctx[mi], w)) continue;
                    const MM = @field(ctx[mi], w);
                    if (@TypeOf(MM) != type or !@hasDecl(MM, "is_mm")) continue;
                    for (MM.methods) |m| {
                        if (m.body != .ops) continue;
                        for (m.body.ops.ops) |op| {
                            if (!containsWord(words[0..n], op.callee)) {
                                words[n] = op.callee;
                                n += 1;
                                changed = true;
                            }
                        }
                    }
                }
            }
        }
        const count = n;
        var out: [count][]const u8 = undefined;
        for (0..count) |i| out[i] = words[i];
        const frozen = out;
        return &frozen;
    }
}

fn keeps(comptime mod: type, comptime words: []const []const u8) bool {
    comptime {
        if (@hasDecl(mod, "specificity")) return true; // the judge travels
        for (words) |w| {
            if (!@hasDecl(mod, w)) continue;
            const MM = @field(mod, w);
            if (@TypeOf(MM) == type and @hasDecl(MM, "is_mm")) return true;
        }
        return false;
    }
}

fn CanonT(comptime acc: anytype, comptime ctx: anytype, comptime words: []const []const u8, comptime i: usize) type {
    if (i == ctx.len) return @TypeOf(acc);
    if (keeps(ctx[i], words)) return CanonT(acc ++ .{ctx[i]}, ctx, words, i + 1);
    return CanonT(acc, ctx, words, i + 1);
}

fn canonFrom(comptime acc: anytype, comptime ctx: anytype, comptime words: []const []const u8, comptime i: usize) CanonT(acc, ctx, words, i) {
    if (i == ctx.len) return acc;
    if (comptime keeps(ctx[i], words)) return canonFrom(acc ++ .{ctx[i]}, ctx, words, i + 1);
    return canonFrom(acc, ctx, words, i + 1);
}

/// shortest context with identical resolution behavior for `word`.
fn canon(comptime ctx: anytype, comptime word: []const u8) CanonT(.{}, ctx, footprint(ctx, word), 0) {
    return canonFrom(.{}, ctx, footprint(ctx, word), 0);
}

// --- v2 collapse: DECISION-level — winners only ------------------------------------
// all defs are comptime, so the decision profile is computable BEFORE
// instantiation: the same walk that infers types (localTypes) discovers
// every inner pack; recording which module's method WON at each step is
// a free byproduct. soundness theorem: removing a loser never changes
// the winners — dominance is pairwise among candidates and position
// order survives subsequence — so never-winning modules drop with no
// re-verification. the selected judge is a winner too; shadowed judges
// never judged and drop. (recursive bodies need the in-progress set —
// the known landmine venue; no recursion in this probe.)

fn addUniqueType(comptime list: []const type, comptime T: type) []const type {
    for (list) |x| if (x == T) return list;
    return list ++ &[_]type{T};
}

/// transitive winner-module set for (word, Raw) under the FULL ctx.
fn collectWinners(comptime ctx: anytype, comptime word: []const u8, comptime Raw: type, comptime acc0: []const type) []const type {
    comptime {
        @setEvalBranchQuota(1_000_000);
        const r = resolve(ctx, word, Raw) orelse return acc0;
        var acc = addUniqueType(acc0, r.home);
        if (r.m.body == .ops) {
            const flat = r.m.body.ops;
            var lt: [flat.ops.len]type = undefined;
            for (flat.ops, 0..) |op, i| {
                var ats: [op.args.len]type = undefined;
                for (op.args, 0..) |ref, j| ats[j] = switch (ref) {
                    .param => |p| fieldTypeAt(r.B, p),
                    .local => |l| lt[l],
                };
                const OpRaw = std.meta.Tuple(&ats);
                acc = collectWinners(ctx, op.callee, OpRaw, acc);
                lt[i] = RetOf(ctx, op.callee, OpRaw);
            }
        }
        return acc;
    }
}

fn judgeOf(comptime ctx: anytype) ?type {
    comptime {
        for (0..ctx.len) |i| if (@hasDecl(ctx[i], "specificity")) return ctx[i];
        return null;
    }
}

fn keeps2(comptime mod: type, comptime winners: []const type, comptime judge: ?type) bool {
    comptime {
        if (judge) |J| if (mod == J) return true;
        for (winners) |w| if (w == mod) return true;
        return false;
    }
}

fn Canon2T(comptime acc: anytype, comptime ctx: anytype, comptime winners: []const type, comptime judge: ?type, comptime i: usize) type {
    if (i == ctx.len) return @TypeOf(acc);
    if (keeps2(ctx[i], winners, judge)) return Canon2T(acc ++ .{ctx[i]}, ctx, winners, judge, i + 1);
    return Canon2T(acc, ctx, winners, judge, i + 1);
}

fn canon2From(comptime acc: anytype, comptime ctx: anytype, comptime winners: []const type, comptime judge: ?type, comptime i: usize) Canon2T(acc, ctx, winners, judge, i) {
    if (i == ctx.len) return acc;
    if (comptime keeps2(ctx[i], winners, judge)) return canon2From(acc ++ .{ctx[i]}, ctx, winners, judge, i + 1);
    return canon2From(acc, ctx, winners, judge, i + 1);
}

/// decision-level collapse: only modules whose methods actually WIN
/// somewhere in this instance's resolution tree survive (plus the judge).
fn canon2(comptime ctx: anytype, comptime word: []const u8, comptime Raw: type) Canon2T(.{}, ctx, collectWinners(ctx, word, Raw, &.{}), judgeOf(ctx), 0) {
    return canon2From(.{}, ctx, collectWinners(ctx, word, Raw, &.{}), judgeOf(ctx), 0);
}

const Resolved = struct { m: Method, B: type, home: type };

fn resolve(comptime ctx: anytype, comptime word: []const u8, comptime Raw: type) ?Resolved {
    comptime {
        @setEvalBranchQuota(100_000);
        var best: ?Resolved = null;
        for (0..ctx.len) |i| {
            const mod = ctx[i];
            if (!@hasDecl(mod, word)) continue;
            const MM = @field(mod, word);
            if (@TypeOf(MM) != type or !@hasDecl(MM, "is_mm")) continue;
            for (MM.methods) |m| {
                const B = construct(m.signature, Raw) orelse continue;
                // choosing is delegated whole to the policy word; resolve
                // itself knows nothing about what "specific" means.
                if (best == null or policyOf(ctx).moreSpecific(ctx, m.signature, best.?.m.signature))
                    best = .{ .m = m, .B = B, .home = mod };
            }
        }
        return best;
    }
}

// --- body interpreter -----------------------------------------------------------

fn fieldTypeAt(comptime B: type, comptime i: usize) type {
    return @typeInfo(B).@"struct".fields[i].type;
}

fn fieldAt(s: anytype, comptime i: usize) fieldTypeAt(@TypeOf(s), i) {
    return @field(s, @typeInfo(@TypeOf(s)).@"struct".fields[i].name);
}

/// type-level walk: the types of all locals, in op order.
fn localTypes(comptime ctx: anytype, comptime flat: Flat, comptime B: type) [flat.ops.len]type {
    comptime {
        @setEvalBranchQuota(100_000);
        var lt: [flat.ops.len]type = undefined;
        for (flat.ops, 0..) |op, i| {
            var ats: [op.args.len]type = undefined;
            for (op.args, 0..) |r, j| ats[j] = switch (r) {
                .param => |p| fieldTypeAt(B, p),
                .local => |l| lt[l],
            };
            lt[i] = RetOf(ctx, op.callee, std.meta.Tuple(&ats));
        }
        return lt;
    }
}

fn flatRet(comptime ctx: anytype, comptime flat: Flat, comptime B: type) type {
    const lt = comptime localTypes(ctx, flat, B);
    return switch (flat.result) {
        .param => |p| fieldTypeAt(B, p),
        .local => |l| lt[l],
    };
}

fn methodRet(comptime ctx: anytype, comptime m: Method, comptime B: type) type {
    return switch (m.body) {
        .ground => |G| G.ret,
        .ops => |flat| flatRet(ctx, flat, B),
    };
}

fn RetOf(comptime ctx: anytype, comptime word: []const u8, comptime Raw: type) type {
    const c = comptime canon(ctx, word); // collapse BEFORE memoization
    const r = comptime resolve(c, word, Raw) orelse
        @compileError("jpp: no method '" ++ word ++ "' in context");
    return methodRet(c, r.m, r.B);
}

/// comptime-unrolled execution of an ANF body.
fn exec(comptime ctx: anytype, comptime flat: Flat, bound: anytype) flatRet(ctx, flat, @TypeOf(bound)) {
    const B = @TypeOf(bound);
    const lt = comptime localTypes(ctx, flat, B);
    var locals: std.meta.Tuple(&lt) = undefined;
    inline for (flat.ops, 0..) |op, i| {
        var raw: RawOf(ctx, flat, B, i) = undefined;
        inline for (op.args, 0..) |r, j| {
            raw[j] = if (comptime r == .param) fieldAt(bound, r.param) else locals[r.local];
        }
        locals[i] = call(ctx, op.callee, raw);
    }
    return if (comptime flat.result == .param)
        fieldAt(bound, comptime flat.result.param)
    else
        locals[comptime flat.result.local];
}

fn RawOf(comptime ctx: anytype, comptime flat: Flat, comptime B: type, comptime i: usize) type {
    comptime {
        const lt = localTypes(ctx, flat, B);
        const op = flat.ops[i];
        var ats: [op.args.len]type = undefined;
        for (op.args, 0..) |r, j| ats[j] = switch (r) {
            .param => |p| fieldTypeAt(B, p),
            .local => |l| lt[l],
        };
        return std.meta.Tuple(&ats);
    }
}

/// THE call: collapse, resolve, bind, run through the right interpreter.
/// canon is semantics-preserving (only no-word modules drop), so every
/// test in this file doubles as a collapse-regression.
fn call(comptime ctx: anytype, comptime word: []const u8, raw: anytype) RetOf(ctx, word, @TypeOf(raw)) {
    const c = comptime canon(ctx, word);
    const r = comptime resolve(c, word, @TypeOf(raw)).?;
    const bound = bindValues(r.m.signature, r.B, raw);
    if (comptime r.m.body == .ground) {
        return r.m.body.ground.run(bound);
    } else {
        return exec(c, r.m.body.ops, bound);
    }
}

// --- the "transpiled" modules: pure data + printed ground fns --------------------

/// what the transpiler prints for `+(a::T, b::T)::T = zig{ ... }`
fn GroundAdd(comptime T: type) type {
    return struct {
        pub const ret = T;
        pub fn run(bound: anytype) T {
            const a = @field(bound, "a");
            const b = @field(bound, "b");
            return if (comptime @typeInfo(T) == .int) a +% b else a + b;
        }
    };
}

fn GroundScale(comptime T: type) type {
    return struct {
        pub const ret = f64;
        pub fn run(bound: anytype) f64 {
            _ = T;
            return @as(f64, @floatFromInt(@field(bound, "x"))) * @field(bound, "factor");
        }
    };
}

const ints = struct {
    pub const @"+" = MultiMethod("+", &.{
        .{
            .name = "+",
            .signature = &.{
                .{ .name = "a", .qual = .{ .exact = i64 } },
                .{ .name = "b", .qual = .{ .exact = i64 } },
            },
            .body = .{ .ground = GroundAdd(i64) },
        },
        .{
            .name = "+",
            .signature = &.{
                .{ .name = "a", .qual = .{ .exact = f64 } },
                .{ .name = "b", .qual = .{ .exact = f64 } },
            },
            .body = .{ .ground = GroundAdd(f64) },
        },
    });
};

const lib = struct {
    // double(x) = x + x                       — bare, rank 1 (computed)
    // double(x::i64) = x + x + x              — exact, rank 3 (computed)
    // scale(x::i64; factor::f64) = ground     — named record section
    pub const double = MultiMethod("double", &.{
        .{
            .name = "double",
            .signature = &.{.{ .name = "x", .qual = .bare }},
            .body = .{ .ops = .{
                .ops = &.{
                    .{ .callee = "+", .args = &.{ .{ .param = 0 }, .{ .param = 0 } } },
                },
                .result = .{ .local = 0 },
            } },
        },
        .{
            .name = "double",
            .signature = &.{.{ .name = "x", .qual = .{ .exact = i64 } }},
            .body = .{ .ops = .{
                .ops = &.{
                    .{ .callee = "+", .args = &.{ .{ .param = 0 }, .{ .param = 0 } } },
                    .{ .callee = "+", .args = &.{ .{ .local = 0 }, .{ .param = 0 } } },
                },
                .result = .{ .local = 1 },
            } },
        },
    });
    pub const scale = MultiMethod("scale", &.{
        .{
            .name = "scale",
            .signature = &.{
                .{ .name = "x", .qual = .{ .exact = i64 } },
                .{ .name = "factor", .section = .named, .qual = .{ .exact = f64 } },
            },
            .body = .{ .ground = GroundScale(i64) },
        },
    });
};

const CTX = .{ ints, lib };

// --- probes ----------------------------------------------------------------------

test "ground axiom dispatches from data" {
    try std.testing.expectEqual(@as(i64, 3), call(CTX, "+", .{ @as(i64, 1), @as(i64, 2) }));
    try std.testing.expectEqual(@as(f64, 3.5), call(CTX, "+", .{ @as(f64, 1.25), @as(f64, 2.25) }));
}

test "data body executes via comptime-unrolled interpretation" {
    var x: f64 = 1.25; // runtime value, f64 -> bare method (one op)
    x += 0;
    try std.testing.expectEqual(@as(f64, 2.5), call(CTX, "double", .{x}));
}

test "rank is a computed byproduct: exact datum beats bare datum" {
    var n: i64 = 21; // i64 -> the exact method (two chained ops = triple)
    n += 0;
    try std.testing.expectEqual(@as(i64, 63), call(CTX, "double", .{n}));
}

test "record section: named slot constructs from the datum" {
    try std.testing.expectEqual(
        @as(f64, 6.0),
        call(CTX, "scale", .{ .@"0" = @as(i64, 3), .factor = @as(f64, 2.0) }),
    );
}

test "inferred return type: type-level walk of the body vector" {
    try std.testing.expect(RetOf(CTX, "double", struct { f64 }) == f64);
    try std.testing.expect(RetOf(CTX, "double", struct { i64 }) == i64);
}

// --- crossing signatures: dominance refuses, position decides --------------------
// module A: pick(x::i64, y)      — exact, bare
// module B: pick(x, y::i64)      — bare, exact
// a call pick(i64, i64) fits both; NEITHER dominates (each is more
// specific in one slot). the ordered context is the tie-breaker the
// language ratified: whoever the caller put first speaks first.

fn GroundConst(comptime v: i64) type {
    return struct {
        pub const ret = i64;
        pub fn run(bound: anytype) i64 {
            _ = bound;
            return v;
        }
    };
}

const mod_a = struct {
    pub const pick = MultiMethod("pick", &.{.{
        .name = "pick",
        .signature = &.{
            .{ .name = "x", .qual = .{ .exact = i64 } },
            .{ .name = "y", .qual = .bare },
        },
        .body = .{ .ground = GroundConst(1) },
    }});
};

const mod_b = struct {
    pub const pick = MultiMethod("pick", &.{.{
        .name = "pick",
        .signature = &.{
            .{ .name = "x", .qual = .bare },
            .{ .name = "y", .qual = .{ .exact = i64 } },
        },
        .body = .{ .ground = GroundConst(2) },
    }});
};

test "incomparable across modules: context order decides, flipping flips" {
    const args = .{ @as(i64, 0), @as(i64, 0) };
    try std.testing.expectEqual(@as(i64, 1), call(.{ mod_a, mod_b }, "pick", args));
    try std.testing.expectEqual(@as(i64, 2), call(.{ mod_b, mod_a }, "pick", args));
}

test "dominance still beats position: a dominant later method displaces" {
    // mod_c dominates both crossings pointwise: exact, exact — even LAST
    // in the context it wins, because dominance decides before position.
    const mod_c = struct {
        pub const pick = MultiMethod("pick", &.{.{
            .name = "pick",
            .signature = &.{
                .{ .name = "x", .qual = .{ .exact = i64 } },
                .{ .name = "y", .qual = .{ .exact = i64 } },
            },
            .body = .{ .ground = GroundConst(3) },
        }});
    };
    const args = .{ @as(i64, 0), @as(i64, 0) };
    try std.testing.expectEqual(@as(i64, 3), call(.{ mod_a, mod_b, mod_c }, "pick", args));
}

// --- the policy is a WORD: a context can shadow the judge itself ------------------

/// demonstration policy: the ladder upside down (bare beats exact).
/// selected by seniority when its module leads the context.
const upside_down = struct {
    pub const specificity = struct {
        pub fn moreSpecific(comptime ctx: anytype, comptime a: []const Slot, comptime b: []const Slot) bool {
            _ = ctx;
            comptime {
                if (a.len != b.len) return false;
                var strictly: bool = false;
                for (a, b) |sa, sb| {
                    const ra = 4 - slotRank(sa.qual); // inverted ladder
                    const rb = 4 - slotRank(sb.qual);
                    if (ra < rb) return false;
                    if (ra > rb) strictly = true;
                }
                return strictly;
            }
        }
    };
};

// --- delegation: M.f selects in M's context, body propagates the CALLER's --------
// ratified: `M.f(x)` resolves the word in M's static context (selection),
// but the chosen method executes with the normal accumulated context —
// the caller's chain stays ahead, its overrides reach inside the body's
// ANF ops. delegation overrides WHO answers, not what words mean inside.
// grounds are de-facto hermetic (axioms — no dispatch inside).

fn DelegateRet(comptime rctx: anytype, comptime xctx: anytype, comptime word: []const u8, comptime Raw: type) type {
    const r = comptime resolve(rctx, word, Raw) orelse
        @compileError("jpp: no method '" ++ word ++ "' in delegated context");
    return methodRet(xctx, r.m, r.B); // return type walks the body in the EXEC ctx
}

fn delegate(comptime rctx: anytype, comptime xctx: anytype, comptime word: []const u8, raw: anytype) DelegateRet(rctx, xctx, word, @TypeOf(raw)) {
    const r = comptime resolve(rctx, word, @TypeOf(raw)).?;
    const bound = bindValues(r.m.signature, r.B, raw);
    if (comptime r.m.body == .ground) {
        return r.m.body.ground.run(bound);
    } else {
        return exec(xctx, r.m.body.ops, bound);
    }
}

fn GroundPlus100(comptime T: type) type {
    return struct {
        pub const ret = T;
        pub fn run(bound: anytype) T {
            return @field(bound, "a") + @field(bound, "b") + 100;
        }
    };
}

test "delegation: selection from M, propagation from the caller" {
    // the caller's world shadows BOTH words:
    const my_double = struct { // own double: exact i64 -> always 0
        pub const double = MultiMethod("double", &.{.{
            .name = "double",
            .signature = &.{.{ .name = "x", .qual = .{ .exact = i64 } }},
            .body = .{ .ground = GroundConst(0) },
        }});
    };
    const plus100 = struct { // own +: i64 addition plus 100
        pub const @"+" = MultiMethod("+", &.{.{
            .name = "+",
            .signature = &.{
                .{ .name = "a", .qual = .{ .exact = i64 } },
                .{ .name = "b", .qual = .{ .exact = i64 } },
            },
            .body = .{ .ground = GroundPlus100(i64) },
        }});
    };
    const CALLER = .{ my_double, plus100, ints, lib };

    var n: i64 = 21;
    n += 0;
    // unqualified: caller's own double wins (equal rank, earlier position)
    try std.testing.expectEqual(@as(i64, 0), call(CALLER, "double", .{n}));
    // lib.double(n): lib's method selected (the two-op exact body),
    // but `+` inside its ANF resolves in the CALLER's context:
    //   t0 = +(21,21) -> 142;  t1 = +(142,21) -> 263
    try std.testing.expectEqual(@as(i64, 263), delegate(.{ ints, lib }, CALLER, "double", .{n}));
}

// --- A->B->C collapse: the resolving module owns the instance ---------------------

const R1 = struct { i64 };

fn Inst(comptime ctx: anytype, comptime word: []const u8, comptime Raw: type) type {
    return struct {
        fn go(raw: Raw) RetOf(ctx, word, Raw) {
            return call(ctx, word, raw);
        }
    };
}

test "A->B->C: when the prefix changes nothing, B is the resolving module" {
    const A = struct { // an inert caller: declares NO footprint word
        pub const unrelated = 17;
    };
    // full chain [A, ints, lib] collapses to lib's own context [ints, lib]:
    // ONE instance, pointer-identical — main reuses what lib itself ships.
    const full = canon(.{ A, ints, lib }, "double");
    const own = canon(.{ ints, lib }, "double");
    try std.testing.expect(&Inst(full, "double", R1).go == &Inst(own, "double", R1).go);

    // a caller that ACTUALLY shadows `+` (a footprint word) must NOT collapse:
    const plus100 = struct {
        pub const @"+" = MultiMethod("+", &.{.{
            .name = "+",
            .signature = &.{
                .{ .name = "a", .qual = .{ .exact = i64 } },
                .{ .name = "b", .qual = .{ .exact = i64 } },
            },
            .body = .{ .ground = GroundPlus100(i64) },
        }});
    };
    const shadowed = canon(.{ plus100, ints, lib }, "double");
    try std.testing.expect(&Inst(shadowed, "double", R1).go != &Inst(own, "double", R1).go);

    // and the collapsed instance still computes correctly through the chain
    var n: i64 = 21;
    n += 0;
    try std.testing.expectEqual(@as(i64, 63), Inst(full, "double", R1).go(.{n}));
}

test "v2: a prefix that declares a footprint word but never WINS collapses away" {
    // plusU8 declares "+" — a footprint word of double — but only for u8:
    // it never constructs for i64 packs, so it never wins. decl-level
    // canon must KEEP it; decision-level canon2 must DROP it.
    const plusU8 = struct {
        pub const @"+" = MultiMethod("+", &.{.{
            .name = "+",
            .signature = &.{
                .{ .name = "a", .qual = .{ .exact = u8 } },
                .{ .name = "b", .qual = .{ .exact = u8 } },
            },
            .body = .{ .ground = GroundPlus100(u8) },
        }});
    };

    const own = canon2(.{ ints, lib }, "double", R1);
    const noisy = canon2(.{ plusU8, ints, lib }, "double", R1);

    // decl-level keeps the impostor (it declares a footprint word):
    try std.testing.expect(@TypeOf(canon(.{ plusU8, ints, lib }, "double")) !=
        @TypeOf(canon(.{ ints, lib }, "double")));
    // decision-level collapses to the identical context and instance:
    try std.testing.expect(@TypeOf(noisy) == @TypeOf(own));
    try std.testing.expect(&Inst(noisy, "double", R1).go == &Inst(own, "double", R1).go);

    // and a caller whose "+" actually WINS for i64 must survive canon2:
    const plusWins = struct {
        pub const @"+" = MultiMethod("+", &.{.{
            .name = "+",
            .signature = &.{
                .{ .name = "a", .qual = .{ .exact = i64 } },
                .{ .name = "b", .qual = .{ .exact = i64 } },
            },
            .body = .{ .ground = GroundPlus100(i64) },
        }});
    };
    const shadowed = canon2(.{ plusWins, ints, lib }, "double", R1);
    try std.testing.expect(@TypeOf(shadowed) != @TypeOf(own));
}

test "entitlement: importing a policy module shadows the specificity decision" {
    var n: i64 = 21;
    n += 0;
    // ground judge: exact double (triple-op body) wins -> 63
    try std.testing.expectEqual(@as(i64, 63), call(.{ ints, lib }, "double", .{n}));
    // upside_down leads the context: bare wins the SAME call -> 42
    try std.testing.expectEqual(@as(i64, 42), call(.{ upside_down, ints, lib }, "double", .{n}));
}
