// jpp.zig — the runtime library. THE only magic:
//   call(ctx, "f", raw) = resolve(collapse(ctx), "f", @TypeOf(raw)) -> bind -> interpret
//
// methods are FIVE FACTS, all data (name, signature, body, hash, span);
// the machinery interprets them: the SIGNATURE interpreter (construct)
// and the BODY interpreter (exec — comptime-unrolled, compiles to the
// same code as hand-written zig). specificity is a shadowable WORD with
// a ground default (pointwise dominance); the judge is chosen by
// seniority, not by judging. contexts collapse to the resolving module
// before memoization (decl-level canon — validated in spike/).
//
// encoding (what the transpiler emits per module file):
//   pub const STATIC = .{ @This(), ...usings in order };
//   const G0 = struct { pub fn Ret(comptime B: type) type ...
//                       pub fn run(bound: anytype) Ret(@TypeOf(bound)) ... };
//   pub const @"print" = jpp.MultiMethod("print", &.{ ...five-fact data... });

const std = @import("std");

// --- the data model: a method is five facts ---------------------------------------

pub const Qual = union(enum) {
    exact: type, //          x::int64
    pred: fn (type) bool, // x<:Integer (predicate on the slot's type)
    bare, //                 x
};

pub const Section = enum { positional, named };

pub const Slot = struct {
    name: []const u8,
    section: Section = .positional,
    qual: Qual,
};

pub const ValRef = union(enum) {
    param: usize, //  bound pack field, by slot index
    local: usize, //  result of an earlier op
    lit_i: i64, //    integer literal (jpp default: int64)
    lit_f: f64, //    float literal   (jpp default: float64)
};

pub const Op = struct { callee: []const u8, args: []const ValRef };
pub const Flat = struct { ops: []const Op, result: ValRef };

pub const Body = union(enum) {
    ops: Flat, //   jpp-level: vector of Expr in ANF
    ground: type, // axiom: printed zig fn struct (Ret(B) + run(bound))
};

pub const Method = struct {
    name: []const u8,
    signature: []const Slot,
    ret: ?type = null, // declared return; null = inferred (bodies AND grounds)
    body: Body,
    hash: u64 = 0,
    span: [2]u32 = .{ 0, 0 },
};

pub fn MultiMethod(comptime word: []const u8, comptime list: []const Method) type {
    return struct {
        pub const is_mm = true;
        pub const name = word;
        pub const methods = list;
    };
}

// --- signature interpreter ----------------------------------------------------------

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

/// raw call-site pack type -> bound pack type (declared slot order) or null.
pub fn construct(comptime sig: []const Slot, comptime Raw: type) ?type {
    comptime {
        @setEvalBranchQuota(1_000_000);
        const rf = @typeInfo(Raw).@"struct".fields;
        if (rf.len != sig.len) return null;
        var types = [_]?type{null} ** (sig.len + 1); // +1: zig disallows zero-len undefined arrays cleanly
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
        if (sig.len == 0) return @Struct(.auto, null, &.{}, &.{}, &.{});
        var names: [sig.len][]const u8 = undefined;
        var ts: [sig.len]type = undefined;
        for (sig, 0..) |s, i| {
            names[i] = s.name;
            ts[i] = types[i] orelse return null;
        }
        return @Struct(.auto, null, &names, &ts, &@splat(.{}));
    }
}

/// value routing raw -> bound (machinery, not per-method code).
pub fn bindValues(comptime sig: []const Slot, comptime B: type, raw: anytype) B {
    var out: B = undefined;
    inline for (@typeInfo(@TypeOf(raw)).@"struct".fields) |f| {
        const target = comptime if (positionOf(f.name)) |p| sig[p].name else f.name;
        @field(out, target) = @field(raw, f.name);
    }
    return out;
}

// --- specificity: a shadowable word, ground default = pointwise dominance -----------

// --- the order is a WORD: `<:` -------------------------------------------------------
// implication between predicates is AUTHORED, never proven: modules
// declare edges under the decl name @"<:" and the machinery consults
// them through the context (entitlement extends to the order itself).
// reflexivity is free (P == Q); transitivity is NOT automatic — declared
// pairs only (closure: future nicety). undeclared pairs stay ties.
// deciding <:(F1, F2) dispatches on function IDENTITY — it never needs
// pred-implication itself, so no circularity (judge-by-seniority again).
// v1 encoding: edge data (dissolves into ordinary methods on the word
// `<:` when value-exact quals land in construct — pending §4 rework).

/// a FACT: may hold or explicitly NOT hold — negative facts are how a
/// context shadows an edge OFF (first answer by position wins).
pub const Edge = struct { sub: fn (type) bool, sup: fn (type) bool, holds: bool = true };

/// a GATED rule: bare binders + where. never quantified over by the
/// system — predLeq queries arrive with BOTH arguments concrete, so the
/// gate is point-evaluated at the query's witnesses (decidable,
/// memoized). tri-valued: true/false are ANSWERS (stop the search),
/// null is "not my domain" (keep looking). gates receive only (P, Q) —
/// no ctx BY SIGNATURE: a rule physically cannot recurse into
/// resolution; stratification enforced by type, not discipline.
pub const OrderRule = struct { when: fn (fn (type) bool, fn (type) bool) ?bool };

pub fn Order(comptime fact_list: []const Edge, comptime rule_list: []const OrderRule) type {
    return struct {
        pub const is_edges = true;
        pub const edges = fact_list;
        pub const rules = rule_list;
    };
}

pub fn Edges(comptime list: []const Edge) type {
    return Order(list, &.{});
}

/// P <: Q — "any type answering P is below any type answering Q" —
/// authored order. identity is an UNSHADOWABLE axiom; then, module by
/// module in context order: facts first (they beat rules within a
/// module), then rules; the FIRST ANSWER wins, whatever it is. miss
/// everywhere = false (the no-prover floor). no transitive closure —
/// chains must be authored.
pub fn predLeq(comptime ctx: anytype, comptime P: fn (type) bool, comptime Q: fn (type) bool) bool {
    comptime {
        if (P == Q) return true;
        for (0..ctx.len) |i| {
            if (!@hasDecl(ctx[i], "<:")) continue;
            const E = @field(ctx[i], "<:");
            if (@TypeOf(E) != type or !@hasDecl(E, "is_edges")) continue;
            for (E.edges) |e| if (e.sub == P and e.sup == Q) return e.holds;
            for (E.rules) |r| if (r.when(P, Q)) |answer| return answer;
        }
        return false;
    }
}

// STRATUM 0: the bare ladder — rank-only dominance, no edge refinement,
// no policy word. the machinery's own words resolve HERE, because the
// order must never consult itself (the recursion-break pattern, third
// instance: matcher is ground; judge by seniority; order by bare ladder).
const stratum0_policy = struct {
    pub fn moreSpecific(comptime ctx: anytype, comptime a: []const Slot, comptime b: []const Slot) bool {
        _ = ctx;
        comptime {
            if (a.len != b.len) return false;
            var strictly: bool = false;
            for (a, b) |sa, sb| {
                const ra = slotRank(sa.qual);
                const rb = slotRank(sb.qual);
                if (ra < rb) return false;
                if (ra > rb) strictly = true;
            }
            return strictly;
        }
    }
};

const ground_policy = struct {
    pub fn moreSpecific(comptime ctx: anytype, comptime a: []const Slot, comptime b: []const Slot) bool {
        comptime {
            if (a.len != b.len) return false;
            var strictly: bool = false;
            for (a, b) |sa, sb| {
                const ra = slotRank(sa.qual);
                const rb = slotRank(sb.qual);
                if (ra < rb) return false;
                if (ra > rb) {
                    strictly = true;
                    continue;
                }
                // equal rank: pred-vs-pred refines through the <: word —
                // f(x<:Integer) beats f(x<:Real) where the edge is declared
                if (sa.qual == .pred and sb.qual == .pred) {
                    const ab = predLeq(ctx, sa.qual.pred, sb.qual.pred);
                    const ba = predLeq(ctx, sb.qual.pred, sa.qual.pred);
                    if (ab and !ba) {
                        strictly = true;
                        continue;
                    }
                    if (ba and !ab) return false; // b strictly narrower here
                }
            }
            return strictly;
        }
    }
};

fn slotRank(comptime q: Qual) u32 {
    return switch (q) {
        .exact => 3,
        .pred => 2,
        .bare => 1,
    };
}

/// the judge is chosen by SENIORITY, not by judging.
fn policyOf(comptime ctx: anytype) type {
    comptime {
        for (0..ctx.len) |i| {
            if (@hasDecl(ctx[i], "specificity")) return @field(ctx[i], "specificity");
        }
        return ground_policy;
    }
}

// --- context building ----------------------------------------------------------------

pub fn contains(comptime ctx: anytype, comptime mod: type) bool {
    inline for (ctx) |m| if (m == mod) return true;
    return false;
}

fn ExtendAllT(comptime ctx: anytype, comptime mods: anytype, comptime i: usize) type {
    if (i == mods.len) return @TypeOf(ctx);
    if (contains(ctx, mods[i])) return ExtendAllT(ctx, mods, i + 1);
    return ExtendAllT(ctx ++ .{mods[i]}, mods, i + 1);
}

fn extendAllFrom(comptime ctx: anytype, comptime mods: anytype, comptime i: usize) ExtendAllT(ctx, mods, i) {
    if (i == mods.len) return ctx;
    if (comptime contains(ctx, mods[i])) return extendAllFrom(ctx, mods, i + 1);
    return extendAllFrom(ctx ++ .{mods[i]}, mods, i + 1);
}

pub fn extendAll(comptime ctx: anytype, comptime mods: anytype) ExtendAllT(ctx, mods, 0) {
    return extendAllFrom(ctx, mods, 0);
}

fn StaticOf(comptime home: type) if (@hasDecl(home, "STATIC")) @TypeOf(home.STATIC) else @TypeOf(.{home}) {
    if (comptime @hasDecl(home, "STATIC")) return home.STATIC;
    return .{home};
}

// --- context collapse (decl-level canon — validated) ---------------------------------

fn containsWord(comptime words: []const []const u8, comptime w: []const u8) bool {
    for (words) |x| if (std.mem.eql(u8, x, w)) return true;
    return false;
}

fn footprint(comptime ctx: anytype, comptime word: []const u8) []const []const u8 {
    comptime {
        @setEvalBranchQuota(1_000_000);
        var words: [128][]const u8 = undefined;
        var n: usize = 1;
        words[0] = word;
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
        if (@hasDecl(mod, "<:")) return true; // and so does the order
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

pub fn canon(comptime ctx: anytype, comptime word: []const u8) CanonT(.{}, ctx, footprint(ctx, word), 0) {
    return canonFrom(.{}, ctx, footprint(ctx, word), 0);
}

// --- resolution ------------------------------------------------------------------------

const Resolved = struct { m: Method, B: type, home: type };

/// julia-parity ambiguity semantics, jpp deviation where ratified:
/// collect ALL constructing candidates, compute the MAXIMA under the
/// policy's dominance; two maxima in the SAME module = comptime
/// ambiguity error at the call (julia's MethodError venue — ambiguity
/// may exist harmlessly until a call actually hits it); maxima across
/// DIFFERENT modules = context position, earliest wins (the ordered
/// context doing its ratified job).
pub fn resolve(comptime ctx: anytype, comptime word: []const u8, comptime Raw: type) ?Resolved {
    comptime {
        @setEvalBranchQuota(1_000_000);
        var cands: [64]Resolved = undefined;
        var n: usize = 0;
        for (0..ctx.len) |i| {
            const mod = ctx[i];
            if (!@hasDecl(mod, word)) continue;
            const MM = @field(mod, word);
            if (@TypeOf(MM) != type or !@hasDecl(MM, "is_mm")) continue;
            for (MM.methods) |m| {
                const B = construct(m.signature, Raw) orelse continue;
                cands[n] = .{ .m = m, .B = B, .home = mod };
                n += 1;
            }
        }
        if (n == 0) return null;

        // stratification: the machinery's own words resolve at stratum 0 —
        // resolving `<:` must not consult `<:` (or any shadowable policy).
        const P = if (std.mem.eql(u8, word, "<:") or std.mem.eql(u8, word, "specificity"))
            stratum0_policy
        else
            policyOf(ctx);
        // maxima: candidates no other candidate strictly dominates
        var first_max: ?Resolved = null;
        var max_count: usize = 0;
        var same_home_clash = false;
        for (0..n) |i| {
            var dominated = false;
            for (0..n) |j| {
                if (i == j) continue;
                if (P.moreSpecific(ctx, cands[j].m.signature, cands[i].m.signature)) {
                    dominated = true;
                    break;
                }
            }
            if (dominated) continue;
            max_count += 1;
            if (first_max == null) {
                first_max = cands[i]; // gather order = context order = position
            } else if (cands[i].home == first_max.?.home) {
                same_home_clash = true;
            }
        }
        if (same_home_clash)
            @compileError("jpp: call of '" ++ word ++ "' is AMBIGUOUS — " ++
                "two maximally specific methods in one module (define the intersection method)." ++
                candidatesText(ctx, word));
        return first_max;
    }
}

fn candidatesText(comptime ctx: anytype, comptime word: []const u8) []const u8 {
    comptime {
        var msg: []const u8 = "";
        for (0..ctx.len) |i| {
            if (!@hasDecl(ctx[i], word)) continue;
            const MM = @field(ctx[i], word);
            if (@TypeOf(MM) != type or !@hasDecl(MM, "is_mm")) continue;
            for (MM.methods) |m| {
                msg = msg ++ "\n  candidate: " ++ m.name ++ "(";
                for (m.signature, 0..) |s, k| {
                    if (k > 0) msg = msg ++ ", ";
                    msg = msg ++ s.name;
                    switch (s.qual) {
                        .exact => |E| msg = msg ++ "::" ++ @typeName(E),
                        .pred => msg = msg ++ "<:pred",
                        .bare => {},
                    }
                }
                msg = msg ++ ")";
            }
        }
        return msg;
    }
}

// --- body interpreter ---------------------------------------------------------------

fn fieldTypeAt(comptime B: type, comptime i: usize) type {
    return @typeInfo(B).@"struct".fields[i].type;
}

fn fieldAt(s: anytype, comptime i: usize) fieldTypeAt(@TypeOf(s), i) {
    return @field(s, @typeInfo(@TypeOf(s)).@"struct".fields[i].name);
}

fn refType(comptime r: ValRef, comptime B: type, comptime lt: []const type) type {
    return switch (r) {
        .param => |p| fieldTypeAt(B, p),
        .local => |l| lt[l],
        .lit_i => i64,
        .lit_f => f64,
    };
}

fn localTypes(comptime ctx: anytype, comptime flat: Flat, comptime B: type) [flat.ops.len]type {
    comptime {
        @setEvalBranchQuota(1_000_000);
        var lt: [flat.ops.len]type = undefined;
        for (flat.ops, 0..) |op, i| {
            var ats: [op.args.len]type = undefined;
            for (op.args, 0..) |r, j| ats[j] = refType(r, B, lt[0..i]);
            lt[i] = RetOf(ctx, op.callee, std.meta.Tuple(&ats));
        }
        return lt;
    }
}

fn flatRet(comptime ctx: anytype, comptime flat: Flat, comptime B: type) type {
    const lt = comptime localTypes(ctx, flat, B);
    return comptime refType(flat.result, B, &lt);
}

fn methodRet(comptime xctx: anytype, comptime m: Method, comptime B: type) type {
    if (m.ret) |T| return T; // declared wins
    return switch (m.body) {
        .ground => |G| G.Ret(B), // inferred across the boundary (@TypeOf mirror)
        .ops => |flat| flatRet(xctx, flat, B),
    };
}

/// return type of a call — public because inferred returns are context-derived.
pub fn RetOf(comptime ctx: anytype, comptime word: []const u8, comptime Raw: type) type {
    const c = comptime canon(ctx, word);
    const r = comptime resolve(c, word, Raw) orelse
        @compileError("jpp: no method '" ++ word ++ "' matches in context." ++ candidatesText(ctx, word));
    return methodRet(extendAll(c, StaticOf(r.home)), r.m, r.B);
}

fn RawOf(comptime ctx: anytype, comptime flat: Flat, comptime B: type, comptime i: usize) type {
    comptime {
        const lt = localTypes(ctx, flat, B);
        const op = flat.ops[i];
        var ats: [op.args.len]type = undefined;
        for (op.args, 0..) |r, j| ats[j] = refType(r, B, &lt);
        return std.meta.Tuple(&ats);
    }
}

/// comptime-unrolled execution of an ANF body. `inline for` unrolls: the
/// compiled result is as if the calls had been written by hand.
fn exec(comptime ctx: anytype, comptime flat: Flat, bound: anytype) flatRet(ctx, flat, @TypeOf(bound)) {
    const B = @TypeOf(bound);
    const lt = comptime localTypes(ctx, flat, B);
    var locals: std.meta.Tuple(&lt) = undefined;
    inline for (flat.ops, 0..) |op, i| {
        var raw: RawOf(ctx, flat, B, i) = undefined;
        inline for (op.args, 0..) |r, j| {
            raw[j] = switch (comptime r) {
                .param => |p| fieldAt(bound, p),
                .local => |l| locals[l],
                .lit_i => |v| @as(i64, v),
                .lit_f => |v| @as(f64, v),
            };
        }
        locals[i] = call(ctx, op.callee, raw);
    }
    return switch (comptime flat.result) {
        .param => |p| fieldAt(bound, p),
        .local => |l| locals[l],
        .lit_i => |v| @as(i64, v),
        .lit_f => |v| @as(f64, v),
    };
}

/// THE call: collapse, resolve, bind, interpret. entering a resolved
/// method, the effective context is caller ++ home STATIC (dedup,
/// caller ahead) — context reaches downward and accumulates.
pub fn call(comptime ctx: anytype, comptime word: []const u8, raw: anytype) RetOf(ctx, word, @TypeOf(raw)) {
    const c = comptime canon(ctx, word);
    const r = comptime resolve(c, word, @TypeOf(raw)).?;
    const bound = bindValues(r.m.signature, r.B, raw);
    if (comptime r.m.body == .ground) {
        return r.m.body.ground.run(bound); // axioms take no context
    } else {
        return exec(comptime extendAll(c, StaticOf(r.home)), r.m.body.ops, bound);
    }
}

/// delegation: M.f(x) — resolve the word in M's context (selection),
/// execute with the caller's accumulated context (propagation).
pub fn delegate(comptime rctx: anytype, comptime xctx: anytype, comptime word: []const u8, raw: anytype) DelegateRet(rctx, xctx, word, @TypeOf(raw)) {
    const r = comptime resolve(rctx, word, @TypeOf(raw)) orelse
        @compileError("jpp: no method '" ++ word ++ "' in delegated context");
    const bound = bindValues(r.m.signature, r.B, raw);
    if (comptime r.m.body == .ground) {
        return r.m.body.ground.run(bound);
    } else {
        return exec(comptime extendAll(xctx, StaticOf(r.home)), r.m.body.ops, bound);
    }
}

fn DelegateRet(comptime rctx: anytype, comptime xctx: anytype, comptime word: []const u8, comptime Raw: type) type {
    const r = comptime resolve(rctx, word, Raw) orelse
        @compileError("jpp: no method '" ++ word ++ "' in delegated context");
    return methodRet(extendAll(xctx, StaticOf(r.home)), r.m, r.B);
}

// --- signature order (STATIC half: ledger, audits, intersection hints) ---------------
// signatures denote SETS of packs; <= is inclusion ("smaller = more
// specific"). resolution never needs this — at a call the pack itself
// witnesses the intersection, and dominance-on-projections answers "who
// is smaller HERE". the static order serves tooling: enumerate ambiguous
// pairs without calls, check a disambiguator covers the meet, print the
// fix. three-valued: pred<=pred is IMPLICATION — undecidable for
// arbitrary predicates (the honest price of predicates replacing the
// type tree; recovery: implication declarations as data, later).
// unknown never changes semantics — it only widens a lint.

pub const Tri = enum { yes, no, unknown };

fn triAll(comptime acc: Tri, comptime x: Tri) Tri {
    if (acc == .no or x == .no) return .no;
    if (acc == .unknown or x == .unknown) return .unknown;
    return .yes;
}

pub fn qualLeq(comptime ctx: anytype, comptime a: Qual, comptime b: Qual) Tri {
    return switch (b) {
        .bare => .yes,
        .exact => |S| switch (a) {
            .exact => |T| if (T == S) Tri.yes else Tri.no,
            .pred => .unknown, // P could denote exactly {S} — unknowable
            .bare => .no,
        },
        .pred => |Q| switch (a) {
            .exact => |T| if (Q(T)) Tri.yes else Tri.no, // point witness
            .pred => |P| if (predLeq(ctx, P, Q)) Tri.yes else Tri.unknown,
            .bare => .unknown, // bare <= Q iff Q is total — unknowable
        },
    };
}

/// sig_a <= sig_b (pack-set inclusion), pointwise over aligned slots.
pub fn sigLeq(comptime ctx: anytype, comptime a: []const Slot, comptime b: []const Slot) Tri {
    comptime {
        if (a.len != b.len) return .no; // no defaults yet: arity must agree
        var acc: Tri = .yes;
        for (a, b) |sa, sb| {
            if (!std.mem.eql(u8, sa.name, sb.name) and sa.section == .named) return .no;
            acc = triAll(acc, qualLeq(ctx, sa.qual, sb.qual));
            if (acc == .no) return .no;
        }
        return acc;
    }
}

fn conj(comptime P: fn (type) bool, comptime Q: fn (type) bool) fn (type) bool {
    return struct {
        fn h(comptime T: type) bool {
            return P(T) and Q(T);
        }
    }.h;
}

/// slot-wise meet: the INTERSECTION signature (julia's suggested fix is
/// exactly this, printed). null = provably empty intersection.
pub fn sigMeet(comptime a: []const Slot, comptime b: []const Slot) ?[]const Slot {
    comptime {
        if (a.len != b.len) return null;
        var out: [a.len]Slot = undefined;
        for (a, b, 0..) |sa, sb, i| {
            const q: Qual = switch (sa.qual) {
                .exact => |T| switch (sb.qual) {
                    .exact => |S| if (T == S) sa.qual else return null,
                    .pred => |Q| if (Q(T)) sa.qual else return null,
                    .bare => sa.qual,
                },
                .pred => |P| switch (sb.qual) {
                    .exact => |S| if (P(S)) sb.qual else return null,
                    .pred => |Q| if (P == Q) sa.qual else Qual{ .pred = conj(P, Q) },
                    .bare => sa.qual,
                },
                .bare => sb.qual,
            };
            out[i] = .{ .name = sa.name, .section = sa.section, .qual = q };
        }
        const frozen = out;
        return &frozen;
    }
}

/// ledger primitive: is (a, b) an ambiguous pair? (neither contains the
/// other, intersection not provably empty.) .unknown widens the lint.
pub fn ambiguousPair(comptime ctx: anytype, comptime a: []const Slot, comptime b: []const Slot) Tri {
    comptime {
        if (sigLeq(ctx, a, b) == .yes or sigLeq(ctx, b, a) == .yes) return .no;
        if (sigMeet(a, b) == null) return .no; // disjoint — no overlap to fight over
        if (sigLeq(ctx, a, b) == .unknown or sigLeq(ctx, b, a) == .unknown) return .unknown;
        return .yes;
    }
}

/// does c resolve the (a, b) ambiguity? c must contain the whole meet
/// and sit inside both.
pub fn resolves(comptime ctx: anytype, comptime c: []const Slot, comptime a: []const Slot, comptime b: []const Slot) Tri {
    comptime {
        const m = sigMeet(a, b) orelse return .yes; // nothing to resolve
        var acc = triAll(sigLeq(ctx, c, a), sigLeq(ctx, c, b));
        acc = triAll(acc, sigLeq(ctx, m, c));
        return acc;
    }
}

// --- tests: julia's dispatch patterns, from the manual --------------------------------

fn isNum(comptime T: type) bool {
    return T == i64 or T == f64;
}

fn GroundStr(comptime s: []const u8) type {
    return struct {
        pub fn Ret(comptime B: type) type {
            _ = B;
            return []const u8;
        }
        pub fn run(bound: anytype) []const u8 {
            _ = bound;
            return s;
        }
    };
}

// manning's `bar` lattice: the full specificity ladder in one module.
//   bar(x, y)                 = "none"    (bare, bare)
//   bar(x<:Num, y)            = "first"   (pred, bare)
//   bar(x, y<:Num)            = "second"  (bare, pred)
//   bar(x<:Num, y<:Num)       = "both"    (pred, pred — the intersection:
//                                          without it, (i64,i64) would be
//                                          julia's MethodError, our comptime
//                                          ambiguity error at the call)
const bar_mod = struct {
    pub const bar = MultiMethod("bar", &.{
        .{ .name = "bar", .signature = &.{
            .{ .name = "x", .qual = .bare },
            .{ .name = "y", .qual = .bare },
        }, .body = .{ .ground = GroundStr("none") } },
        .{ .name = "bar", .signature = &.{
            .{ .name = "x", .qual = .{ .pred = isNum } },
            .{ .name = "y", .qual = .bare },
        }, .body = .{ .ground = GroundStr("first") } },
        .{ .name = "bar", .signature = &.{
            .{ .name = "x", .qual = .bare },
            .{ .name = "y", .qual = .{ .pred = isNum } },
        }, .body = .{ .ground = GroundStr("second") } },
        .{ .name = "bar", .signature = &.{
            .{ .name = "x", .qual = .{ .pred = isNum } },
            .{ .name = "y", .qual = .{ .pred = isNum } },
        }, .body = .{ .ground = GroundStr("both") } },
    });
};

test "julia's bar lattice: every cell picks by dominance" {
    const CTX = .{bar_mod};
    var b: bool = true;
    b = !!b;
    var n: i64 = 1;
    n += 0;
    try std.testing.expectEqualStrings("none", call(CTX, "bar", .{ b, b }));
    try std.testing.expectEqualStrings("first", call(CTX, "bar", .{ n, b }));
    try std.testing.expectEqualStrings("second", call(CTX, "bar", .{ b, n }));
    // the intersection method dominates BOTH generals: no ambiguity error
    try std.testing.expectEqualStrings("both", call(CTX, "bar", .{ n, n }));
}

// julia's manual crossing — g(x::Float64, y) vs g(x, y::Float64) — split
// across two modules: julia raises MethodError (no module order exists);
// jpp resolves by position, and flipping the context flips the winner.
// the same crossing in ONE module is a comptime ambiguity error at the
// call site (julia parity — cannot be a passing test, verified by hand).
const gm_a = struct {
    pub const g = MultiMethod("g", &.{.{ .name = "g", .signature = &.{
        .{ .name = "x", .qual = .{ .exact = f64 } },
        .{ .name = "y", .qual = .bare },
    }, .body = .{ .ground = GroundStr("float-first") } }});
};
const gm_b = struct {
    pub const g = MultiMethod("g", &.{.{ .name = "g", .signature = &.{
        .{ .name = "x", .qual = .bare },
        .{ .name = "y", .qual = .{ .exact = f64 } },
    }, .body = .{ .ground = GroundStr("float-second") } }});
};

test "two generals collide across modules: position decides, flip flips" {
    var x: f64 = 2.0;
    x += 0;
    try std.testing.expectEqualStrings("float-first", call(.{ gm_a, gm_b }, "g", .{ x, x }));
    try std.testing.expectEqualStrings("float-second", call(.{ gm_b, gm_a }, "g", .{ x, x }));
    // mixed calls are NOT ambiguous — only one general constructs:
    var n: i64 = 3;
    n += 0;
    try std.testing.expectEqualStrings("float-first", call(.{ gm_a, gm_b }, "g", .{ x, n }));
    try std.testing.expectEqualStrings("float-second", call(.{ gm_a, gm_b }, "g", .{ n, x }));
}

// aqua.jl's mixed-rank crossing: f(x::Int, y<:Integer) vs f(x<:Integer,
// y::Int) — ranks (3,2) vs (2,3), incomparable. across modules: position.
const aq_a = struct {
    pub const f = MultiMethod("f", &.{.{ .name = "f", .signature = &.{
        .{ .name = "x", .qual = .{ .exact = i64 } },
        .{ .name = "y", .qual = .{ .pred = isNum } },
    }, .body = .{ .ground = GroundStr("exact-pred") } }});
};
const aq_b = struct {
    pub const f = MultiMethod("f", &.{.{ .name = "f", .signature = &.{
        .{ .name = "x", .qual = .{ .pred = isNum } },
        .{ .name = "y", .qual = .{ .exact = i64 } },
    }, .body = .{ .ground = GroundStr("pred-exact") } }});
};

test "aqua's mixed-rank crossing across modules: position, not arithmetic" {
    // under SUM these would be 5 vs 5 "tied" by coincidence; under
    // dominance they are incomparable BY STRUCTURE — position decides.
    var n: i64 = 1;
    n += 0;
    try std.testing.expectEqualStrings("exact-pred", call(.{ aq_a, aq_b }, "f", .{ n, n }));
    try std.testing.expectEqualStrings("pred-exact", call(.{ aq_b, aq_a }, "f", .{ n, n }));
}

test "signature order: julia's g-pair is ambiguous, the intersection resolves it" {
    const sig_a = &[_]Slot{ // g(x::f64, y)
        .{ .name = "x", .qual = .{ .exact = f64 } },
        .{ .name = "y", .qual = .bare },
    };
    const sig_b = &[_]Slot{ // g(x, y::f64)
        .{ .name = "x", .qual = .bare },
        .{ .name = "y", .qual = .{ .exact = f64 } },
    };
    // neither contains the other; overlap exists -> ambiguous pair
    try std.testing.expect(comptime sigLeq(.{}, sig_a, sig_b) == .no);
    try std.testing.expect(comptime sigLeq(.{}, sig_b, sig_a) == .no);
    try std.testing.expect(comptime ambiguousPair(.{}, sig_a, sig_b) == .yes);

    // the meet IS julia's printed fix: (x::f64, y::f64)
    const m = comptime sigMeet(sig_a, sig_b).?;
    try std.testing.expect(m[0].qual.exact == f64);
    try std.testing.expect(m[1].qual.exact == f64);

    // and the intersection method resolves the pair
    try std.testing.expect(comptime resolves(.{}, m, sig_a, sig_b) == .yes);
    // an off-target method does NOT (covers (f64,i64), not the meet)
    const off = &[_]Slot{
        .{ .name = "x", .qual = .{ .exact = f64 } },
        .{ .name = "y", .qual = .{ .exact = i64 } },
    };
    try std.testing.expect(comptime resolves(.{}, off, sig_a, sig_b) != .yes);
}

test "signature order: decidable and honest cells" {
    const ex = Qual{ .exact = i64 };
    const pn = Qual{ .pred = isNum };
    // exact <= pred: decided by RUNNING the predicate on the type —
    // the point-witness cell; the only cell dispatch ever needs
    try std.testing.expect(comptime qualLeq(.{}, ex, pn) == .yes);
    try std.testing.expect(comptime qualLeq(.{}, .{ .exact = bool }, pn) == .no);
    // pred <= pred: identity yes, implication otherwise UNKNOWN
    try std.testing.expect(comptime qualLeq(.{}, pn, pn) == .yes);
    const other = Qual{ .pred = struct {
        fn h(comptime T: type) bool {
            return T == f64;
        }
    }.h };
    try std.testing.expect(comptime qualLeq(.{}, other, pn) == .unknown);
    // disjoint exacts: provably empty meet -> not an ambiguous pair
    const sa = &[_]Slot{.{ .name = "x", .qual = .{ .exact = i64 } }};
    const sb = &[_]Slot{.{ .name = "x", .qual = .{ .exact = f64 } }};
    try std.testing.expect(comptime sigMeet(sa, sb) == null);
    try std.testing.expect(comptime ambiguousPair(.{}, sa, sb) == .no);
}

fn isInt(comptime T: type) bool {
    return T == i64;
}

test "the order is a word: a declared <: edge refines pred-vs-pred dispatch" {
    // narrow and wide in ONE module: without the edge, an i64 call hits
    // two same-rank maxima in one module = comptime ambiguity error
    // (verified by hand); WITH the edge, narrow strictly dominates.
    const sizes = struct {
        pub const size = MultiMethod("size", &.{
            .{ .name = "size", .signature = &.{.{ .name = "x", .qual = .{ .pred = isNum } }}, .body = .{ .ground = GroundStr("wide") } },
            .{ .name = "size", .signature = &.{.{ .name = "x", .qual = .{ .pred = isInt } }}, .body = .{ .ground = GroundStr("narrow") } },
        });
    };
    const num_edges = struct {
        pub const @"<:" = Edges(&.{.{ .sub = isInt, .sup = isNum }});
    };
    const CTX = .{ num_edges, sizes };
    var n: i64 = 1;
    n += 0;
    var x: f64 = 1.0;
    x += 0;
    try std.testing.expectEqualStrings("narrow", call(CTX, "size", .{n}));
    try std.testing.expectEqualStrings("wide", call(CTX, "size", .{x}));
    // the static order sees the edge too: isInt <= isNum becomes YES
    try std.testing.expect(comptime qualLeq(CTX, .{ .pred = isInt }, .{ .pred = isNum }) == .yes);
    try std.testing.expect(comptime qualLeq(.{}, .{ .pred = isInt }, .{ .pred = isNum }) == .unknown);
}

test "gated order rule: where evaluated at the query's witnesses" {
    // `<:(P, Q) where rankOf(P) < rankOf(Q) = true` — a rule, not facts
    // (where sits BEFORE `=`: the gate is part of the constructor).
    // the tower ranks live in ordinary comptime code; the gate runs at
    // each concrete (P, Q) query — point evaluation, never quantified.
    const tower = struct {
        fn rankOf(comptime F: fn (type) bool) ?u8 {
            if (F == isInt) return 1;
            if (F == isNum) return 2;
            return null;
        }
        fn below(comptime P: fn (type) bool, comptime Q: fn (type) bool) ?bool {
            const rp = rankOf(P) orelse return null; // not my domain
            const rq = rankOf(Q) orelse return null;
            return rp < rq; // an ANSWER, either way
        }
        pub const @"<:" = Order(&.{}, &.{.{ .when = below }});
    };
    try std.testing.expect(comptime predLeq(.{tower}, isInt, isNum));
    try std.testing.expect(comptime !predLeq(.{tower}, isNum, isInt));
    // and it refines dispatch exactly like a fact would
    const sizes = struct {
        pub const size = MultiMethod("size", &.{
            .{ .name = "size", .signature = &.{.{ .name = "x", .qual = .{ .pred = isNum } }}, .body = .{ .ground = GroundStr("wide") } },
            .{ .name = "size", .signature = &.{.{ .name = "x", .qual = .{ .pred = isInt } }}, .body = .{ .ground = GroundStr("narrow") } },
        });
    };
    var n: i64 = 1;
    n += 0;
    try std.testing.expectEqualStrings("narrow", call(.{ tower, sizes }, "size", .{n}));
}

test "ironing: negative facts — a context shadows an edge OFF by position" {
    const on = struct {
        pub const @"<:" = Edges(&.{.{ .sub = isInt, .sup = isNum }});
    };
    const off = struct {
        pub const @"<:" = Edges(&.{.{ .sub = isInt, .sup = isNum, .holds = false }});
    };
    try std.testing.expect(comptime predLeq(.{ on, off }, isInt, isNum));
    try std.testing.expect(comptime !predLeq(.{ off, on }, isInt, isNum));
}

test "ironing: within a module, a fact beats a rule" {
    const contrarian = struct {
        fn always(comptime P: fn (type) bool, comptime Q: fn (type) bool) ?bool {
            _ = P;
            _ = Q;
            return true; // rule would order EVERYTHING
        }
        pub const @"<:" = Order(
            &.{.{ .sub = isInt, .sup = isNum, .holds = false }}, // fact says NO
            &.{.{ .when = always }},
        );
    };
    // the fact answers first: isInt is NOT below isNum here
    try std.testing.expect(comptime !predLeq(.{contrarian}, isInt, isNum));
    // outside the fact's pair, the rule speaks
    try std.testing.expect(comptime predLeq(.{contrarian}, isNum, isInt));
}

fn isAny(comptime T: type) bool {
    _ = T;
    return true;
}

test "ironing: no transitive closure — chains must be authored" {
    const chain = struct {
        pub const @"<:" = Edges(&.{
            .{ .sub = isInt, .sup = isNum },
            .{ .sub = isNum, .sup = isAny },
        });
    };
    try std.testing.expect(comptime predLeq(.{chain}, isInt, isNum));
    try std.testing.expect(comptime predLeq(.{chain}, isNum, isAny));
    // the composite is NOT derived: author it or live without it
    try std.testing.expect(comptime !predLeq(.{chain}, isInt, isAny));
}

test "ironing: a cycle IS an equivalence — the members are one class" {
    const cyclic = struct {
        pub const @"<:" = Edges(&.{
            .{ .sub = isInt, .sup = isNum },
            .{ .sub = isNum, .sup = isInt }, // mutual edges = DECLARED IDENTITY
        });
    };
    // cycle means identity: the two predicates are one class wearing two
    // names. dominance sees equal specificity — exactly right for
    // identical classes (same-module methods on one class genuinely
    // collide; cross-module resolves by position). a declaration form,
    // not a smell: the preorder quotients, the cycle is the type.
    try std.testing.expect(comptime predLeq(.{cyclic}, isInt, isNum));
    try std.testing.expect(comptime predLeq(.{cyclic}, isNum, isInt));

    const denier = struct {
        pub const @"<:" = Edges(&.{.{ .sub = isInt, .sup = isInt, .holds = false }});
    };
    // identity short-circuits BEFORE tables: self-facts are dead letters
    try std.testing.expect(comptime predLeq(.{denier}, isInt, isInt));
}

test "specificity ladder: exact > pred > bare, all three rungs" {
    const ladder = struct {
        pub const h = MultiMethod("h", &.{
            .{ .name = "h", .signature = &.{.{ .name = "x", .qual = .bare }}, .body = .{ .ground = GroundStr("bare") } },
            .{ .name = "h", .signature = &.{.{ .name = "x", .qual = .{ .pred = isNum } }}, .body = .{ .ground = GroundStr("pred") } },
            .{ .name = "h", .signature = &.{.{ .name = "x", .qual = .{ .exact = i64 } }}, .body = .{ .ground = GroundStr("exact") } },
        });
    };
    const CTX = .{ladder};
    var b: bool = true;
    b = !!b;
    var x: f64 = 1.5;
    x += 0;
    var n: i64 = 7;
    n += 0;
    try std.testing.expectEqualStrings("bare", call(CTX, "h", .{b})); // only bare fits
    try std.testing.expectEqualStrings("pred", call(CTX, "h", .{x})); // pred beats bare
    try std.testing.expectEqualStrings("exact", call(CTX, "h", .{n})); // exact beats both
}
