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

// --- test support (used by Base/Test.jpp's grounds) ----------------------------------
// the program judges itself: checks record failures here; the generated
// harness prints the verdict and exits 0/1. DCE'd when unused.

pub var test_failures: usize = 0;

pub fn testFail() void {
    test_failures += 1;
}

// --- the data model: a method is five facts ---------------------------------------

pub const Qual = union(enum) {
    type_value: type, //    int64: this particular type VALUE, not an integer
    exact: type, //          x::int64
    pred: fn (type) bool, // x<:Integer (predicate on the slot's type)
    bare, //                 x
    tvar: []const u8, //     x::T  (T declared in `where`; unconstrained per slot)
};

pub const Section = enum { positional, named };

pub const Slot = struct {
    name: []const u8,
    section: Section = .positional,
    qual: Qual,
};

pub const ValRef = union(enum) {
    param_type: usize, // a where-bound type, obtained from an input field
    type_value: type,
    param: usize, //  bound pack field, by slot index
    local: usize, //  result of an earlier op
    lit_i: i64, //    integer literal (jpp default: int64)
    lit_f: f64, //    float literal   (jpp default: float64)
    lit_s: []const u8, // string literal (jpp string = []const u8)
    lit_b: bool, //    boolean literal (`<:` facts are the motivating use)
};

pub const Op = struct { callee: []const u8, args: []const ValRef };
pub const Flat = struct { ops: []const Op, result: ValRef };

pub const Body = union(enum) {
    ops: Flat, //   jpp-level: vector of Expr in ANF
    ground: type, // axiom: printed zig fn struct (Ret(B) + run(bound))
};

/// a `where T == S` equality constraint: types bound to T and S must
/// satisfy both direct `<:` queries (identity, or an authored mutual pair).
pub const Eq = struct { a: []const u8, b: []const u8 };

/// a `where T <: Integer` predicate gate. SUGAR for `Integer(T)`: the
/// predicate is an ordinary word resolved through the CALLER's context,
/// so applicability is caller-derived like everything else. the gate is
/// METHOD data, not a slot qual — that is what lets it compose with
/// repeated-binder identity (`f(a::T, b::T) where T <: Integer` keeps
/// both the same-type constraint and the gate).
pub const Gate = struct { tvar: []const u8, word: []const u8 };

pub const Method = struct {
    declaration_home: ?type = null, // preserved when a folder merges methods
    name: []const u8,
    signature: []const Slot,
    ret_variable: ?[]const u8 = null,
    ret: ?type = null, // declared return; null = inferred (bodies AND grounds)
    body: Body,
    eqs: []const Eq = &.{}, // `where T == S` pairs; empty = none
    variables: []const []const u8 = &.{},
    gates: []const Gate = &.{}, // `where T <: Integer` gates; empty = none
    hash: u64 = 0,
    span: [2]u32 = .{ 0, 0 },
};

fn hasTypeBinding(comptime m: Method, comptime name: []const u8) bool {
    for (m.signature) |slot| {
        if (slot.qual == .tvar and std.mem.eql(u8, slot.qual.tvar, name)) return true;
        if (slot.qual == .exact and slot.qual.exact == type and std.mem.eql(u8, slot.name, name)) return true;
    }
    return false;
}

pub fn MultiMethod(comptime word: []const u8, comptime list: []const Method) type {
    for (list) |m| {
        for (m.signature, 0..) |slot, i| {
            for (m.signature[0..i]) |previous| if (std.mem.eql(u8, slot.name, previous.name) and
                !(slot.section == .positional and previous.section == .positional and slot.qual == .type_value and previous.qual == .type_value))
                @compileError("jpp: duplicate input '" ++ slot.name ++ "'; use distinct inputs and an explicit type constraint.");
        }
        for (m.variables) |v| if (!hasTypeBinding(m, v))
            @compileError("jpp: unbound where variable '" ++ v ++ "' in '" ++ word ++ "'.");
        for (m.gates) |g| if (!hasTypeBinding(m, g.tvar))
            @compileError("jpp: unbound gate variable '" ++ g.tvar ++ "' in '" ++ word ++ "'.");
        for (m.eqs) |e| if (!hasTypeBinding(m, e.a) or !hasTypeBinding(m, e.b))
            @compileError("jpp: unbound equality variable in '" ++ word ++ "'.");
        if (std.mem.eql(u8, word, "<:")) {
            if (m.signature.len != 2) @compileError("jpp: '<:' requires two type-value inputs.");
            for (m.signature) |slot| {
                if (slot.qual == .pred or (slot.qual == .exact and slot.qual.exact != type))
                    @compileError("jpp: '<:' input domains must be type values.");
            }
        }
        if (std.mem.eql(u8, word, "<:") and m.eqs.len > 0)
            @compileError("jpp: '<:' cannot use an equality gate derived from itself; use a type-identity predicate.");
    }
    return struct {
        pub const is_mm = true;
        pub const name = word;
        pub const methods = list;
    };
}

/// FOLDER-AS-MODULE aggregation: one word, methods concatenated from the
/// child modules that export it (order = child order: position semantics
/// inside the aggregate). methods are data, so merging is concatenation.
pub fn MergedWord(comptime word: []const u8, comptime mods: anytype) type {
    comptime {
        var list: []const Method = &.{};
        for (0..mods.len) |i| {
            if (!@hasDecl(mods[i], word)) continue;
            const MM = @field(mods[i], word);
            if (@TypeOf(MM) != type or !@hasDecl(MM, "is_mm")) continue;
            list = list ++ MM.methods;
        }
        return MultiMethod(word, list);
    }
}

// --- signature interpreter ----------------------------------------------------------

fn positionOf(comptime name: []const u8) ?usize {
    return std.fmt.parseInt(usize, name, 10) catch null;
}

fn qualOk(comptime q: Qual, comptime f: std.builtin.Type.StructField) bool {
    const T = f.type;
    return switch (q) {
        .type_value => |V| T == type and f.is_comptime and f.defaultValue().? == V,
        .exact => |E| T == E,
        .pred => |P| P(T),
        .bare, .tvar => true,
    };
}

/// raw call-site pack type -> bound pack type (declared slot order) or null.
pub fn construct(comptime sig: []const Slot, comptime Raw: type) ?type {
    comptime {
        @setEvalBranchQuota(1_000_000);
        const rf = @typeInfo(Raw).@"struct".fields;
        if (rf.len != sig.len) return null;
        var types = [_]?type{null} ** (sig.len + 1); // +1: zig disallows zero-len undefined arrays cleanly
        var attrs: [sig.len]std.builtin.Type.StructField.Attributes = @splat(.{});
        for (rf) |f| {
            if (positionOf(f.name)) |p| {
                if (p >= sig.len or sig[p].section != .positional) return null;
                if (types[p] != null) return null;
                if (!qualOk(sig[p].qual, f)) return null;
                types[p] = f.type;
                if (f.type == type) attrs[p] = .{ .@"comptime" = true, .default_value_ptr = f.default_value_ptr };
            } else {
                const idx = for (sig, 0..) |s, i| {
                    if (s.section == .named and std.mem.eql(u8, s.name, f.name)) break i;
                } else return null;
                if (types[idx] != null) return null;
                if (!qualOk(sig[idx].qual, f)) return null;
                types[idx] = f.type;
                if (f.type == type) attrs[idx] = .{ .@"comptime" = true, .default_value_ptr = f.default_value_ptr };
            }
        }
        if (sig.len == 0) return @Struct(.auto, null, &.{}, &.{}, &.{});
        var names: [sig.len][]const u8 = undefined;
        var ts: [sig.len]type = undefined;
        for (sig, 0..) |s, i| {
            names[i] = s.name;
            for (names[0..i]) |previous| if (std.mem.eql(u8, previous, s.name)) {
                names[i] = std.fmt.comptimePrint("__fixed{d}", .{i});
                break;
            };
            ts[i] = types[i] orelse return null;
        }
        // repeated tvar = identity: A::T, B::T requires typeof(A) is typeof(B)
        var bn: [16][]const u8 = undefined;
        var bt: [16]type = undefined;
        var nb: usize = 0;
        for (sig, 0..) |s, i| {
            switch (s.qual) {
                .tvar => |v| {
                    const existing: ?usize = for (0..nb) |bi| {
                        if (std.mem.eql(u8, bn[bi], v)) break bi;
                    } else null;
                    if (existing) |bi| {
                        if (bt[bi] != ts[i]) return null;
                    } else {
                        bn[nb] = v;
                        bt[nb] = ts[i];
                        nb += 1;
                    }
                },
                else => {},
            }
        }
        return @Struct(.auto, null, &names, &ts, &attrs);
    }
}

/// value routing raw -> bound (machinery, not per-method code).
pub fn bindValues(comptime sig: []const Slot, comptime B: type, raw: anytype) B {
    _ = sig; // positional routing follows the canonical bound field order
    var out: B = undefined;
    inline for (@typeInfo(@TypeOf(raw)).@"struct".fields) |f| {
        const target = comptime if (positionOf(f.name)) |p| @typeInfo(B).@"struct".fields[p].name else f.name;
        if (comptime !@typeInfo(B).@"struct".fields[std.meta.fieldIndex(B, target).?].is_comptime)
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
// Legacy Zig probes use edge data. Surface modules use ordinary methods
// with exact type-value constraints and type-domain binders.

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
/// authored order. REFLEXIVITY (P <: P) is an UNSHADOWABLE machinery
/// axiom: the two arguments are the same predicate (Zig identity of
/// the fn values). It is NOT jpp `==` — that word is defined FROM
/// `<:` (`=={T,S} = T<:S && S<:T`); writing `<:(P,Q) where P == Q`
/// would be circular. Then, module by module in context order: facts
/// first (they beat rules within a module), then rules; the FIRST
/// ANSWER wins. miss everywhere = false (the no-prover floor). no
/// transitive closure — chains must be authored.
pub fn predLeq(comptime ctx: anytype, comptime P: fn (type) bool, comptime Q: fn (type) bool) bool {
    comptime {
        if (P == Q) return true; // reflexivity of <:  (same predicate)
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

/// interned "exactly this type" predicate — type-literal `<:` facts and
/// `=={T,S}` share these, so function identity matches.
pub fn Exact(comptime X: type) fn (type) bool {
    return struct {
        fn p(comptime Y: type) bool {
            return Y == X;
        }
    }.p;
}

/// Mutual direct relation, derived from `<:`. Without transitive closure this
/// is not a general equivalence relation and cannot justify quotienting types.
pub fn typesEquiv(comptime ctx: anytype, comptime T: type, comptime S: type) bool {
    return typeLeq(ctx, T, S) and typeLeq(ctx, S, T);
}

// A word has a stable type-level identity across module contributions. Only a
// declaration or exported import introduces that value into a source scope.
pub fn Word(comptime name: []const u8) type {
    return struct {
        pub const word_name = name;
    };
}

pub fn builtinType(comptime name: []const u8) ?type {
    const names = .{ "int64", "int32", "int16", "int8", "uint64", "uint32", "uint16", "uint8", "float64", "float32", "bool", "nothing", "string", "type" };
    const types = .{ i64, i32, i16, i8, u64, u32, u16, u8, f64, f32, bool, void, []const u8, type };
    inline for (names, types) |n, T| if (std.mem.eql(u8, name, n)) return T;
    return null;
}

fn exportedName(comptime mod: type, comptime name: []const u8) bool {
    inline for (mod.EXPORTED) |n| if (std.mem.eql(u8, name, n)) return true;
    return false;
}

pub fn validateExports(comptime declared: anytype, comptime exported: anytype) void {
    inline for (exported) |name| {
        const found = blk: {
            inline for (declared) |d| if (std.mem.eql(u8, name, d)) break :blk true;
            break :blk false;
        };
        if (!found) @compileError("jpp: export '" ++ name ++ "' has no local definition.");
    }
}

pub fn declaredValue(comptime scope: anytype, comptime name: []const u8) ?type {
    if (builtinType(name)) |T| return T;
    inline for (scope, 0..) |mod, i| {
        const names = if (i == 0) mod.DECLARED else mod.EXPORTED;
        inline for (names) |n| if (std.mem.eql(u8, name, n)) {
            if (i == 0 and !exportedName(mod, name) and !std.mem.eql(u8, name, "main"))
                return Word(mod.MODULE_NAME ++ "#" ++ name);
            return Word(name);
        };
    }
    return null;
}

pub fn requireValue(comptime scope: anytype, comptime name: []const u8) type {
    return declaredValue(scope, name) orelse @compileError("jpp: undefined value '" ++ name ++ "' (define it or import its definition).");
}

/// Declaration lookup is lexical; dispatch remains caller-contextual. A fresh
/// name binds an input. An explicit annotation gives it a signature role even
/// when the body ignores its value. Only unused, unannotated fresh names error:
/// they can accidentally turn a misspelled class constraint into a generic rule.
pub fn declarationQual(comptime scope: anytype, comptime name: []const u8, comptime q: Qual, comptime used: bool) Qual {
    if (declaredValue(scope, name)) |V| {
        if (q != .bare and !(q == .exact and q.exact == type))
            @compileError("jpp: defined value '" ++ name ++ "' cannot be rebound by an input annotation.");
        return .{ .type_value = V };
    }
    if (!used and q == .bare) @compileError("jpp: unused input '" ++ name ++ "'; annotate it, use '_', or define/import the intended value.");
    return q;
}

/// Pairwise order, with an identity floor and no implicit closure. Both
/// arguments are type values; a class word's identity comes from a definition.
fn wordLeq(comptime ctx: anytype, comptime a: []const u8, comptime b: []const u8) bool {
    return typeLeq(ctx, Word(a), Word(b));
}

pub fn typeLeq(comptime ctx: anytype, comptime a: type, comptime b: type) bool {
    comptime {
        if (a == b) return true;
        const args = .{ a, b };
        if (resolve(canon(ctx, "<:"), "<:", @TypeOf(args)) == null) return predLeq(ctx, Exact(a), Exact(b));
        return call(ctx, "<:", args);
    }
}

fn gatesAt(comptime m: Method, comptime i: usize) []const Gate {
    comptime {
        const slot = m.signature[i];
        var result: []const Gate = &.{};
        for (m.gates) |g| {
            const bound = if (slot.qual == .tvar) slot.qual.tvar else if (slot.qual == .exact and slot.qual.exact == type) slot.name else continue;
            if (std.mem.eql(u8, bound, g.tvar)) result = result ++ .{g};
        }
        return result;
    }
}

/// A conjunction entails another when each required predicate has a direct
/// witness. Never infer transitivity or treat an unknown relation as equality.
fn gatesLeq(comptime ctx: anytype, comptime a: []const Gate, comptime b: []const Gate) bool {
    comptime {
        for (b) |required| {
            const found = for (a) |given| {
                if (wordLeq(ctx, given.word, required.word)) break true;
            } else false;
            if (!found) return false;
        }
        return true;
    }
}

fn typeOfVar(comptime sig: []const Slot, comptime B: type, comptime name: []const u8) ?type {
    comptime {
        for (sig, 0..) |s, i| {
            const f = @typeInfo(B).@"struct".fields[i];
            if (std.mem.eql(u8, s.name, name) and f.type == type) return f.defaultValue().?;
            switch (s.qual) {
                .tvar => |v| if (std.mem.eql(u8, v, name)) return fieldTypeAt(B, i),
                else => {},
            }
        }
        return null;
    }
}

fn eqsOk(comptime ctx: anytype, comptime m: Method, comptime B: type) bool {
    comptime {
        for (m.eqs) |e| {
            const Ta = typeOfVar(m.signature, B, e.a) orelse return false;
            const Tb = typeOfVar(m.signature, B, e.b) orelse return false;
            if (!typesEquiv(ctx, Ta, Tb)) return false;
        }
        return true;
    }
}

/// `where T <: Integer` — run the predicate WORD on the type bound to T,
/// resolved through the caller's context. the predicate's slot is qualed
/// on `type`, so the bound type travels as an ordinary argument value.
fn gatesOk(comptime ctx: anytype, comptime m: Method, comptime B: type) bool {
    comptime {
        for (m.gates) |g| {
            const T = typeOfVar(m.signature, B, g.tvar) orelse return false;
            if (!call(ctx, g.word, .{T})) return false;
        }
        return true;
    }
}

// STRATUM 0: the bare ladder — rank-only dominance, no edge refinement,
// no policy word. the machinery's own words resolve HERE, because the
// order must never consult itself (the recursion-break pattern, third
// instance: matcher is ground; judge by seniority; order by bare ladder).
const stratum0_policy = struct {
    pub fn moreSpecific(comptime ctx: anytype, comptime a: Method, comptime b: Method) bool {
        _ = ctx;
        comptime {
            if (a.signature.len != b.signature.len) return false;
            var strictly: bool = false;
            for (0..a.signature.len) |i| {
                const ra = effRank(a, i);
                const rb = effRank(b, i);
                if (ra < rb) return false;
                if (ra > rb) strictly = true;
            }
            return strictly;
        }
    }
};

const ground_policy = struct {
    pub fn moreSpecific(comptime ctx: anytype, comptime a: Method, comptime b: Method) bool {
        comptime {
            if (a.signature.len != b.signature.len) return false;
            var strictly: bool = false;
            for (a.signature, b.signature, 0..) |sa, sb, i| {
                const ra = effRank(a, i);
                const rb = effRank(b, i);
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
                    if (!ab) return false; // worse OR incomparable in this coordinate
                }
                const ga = gatesAt(a, i);
                const gb = gatesAt(b, i);
                if (ga.len > 0 or gb.len > 0) {
                    // Legacy function predicates and surface word predicates
                    // have no authored identity bridge: keep them incomparable.
                    if (sa.qual == .pred or sb.qual == .pred) return false;
                    const ab = gatesLeq(ctx, ga, gb);
                    const ba = gatesLeq(ctx, gb, ga);
                    if (!ab) return false;
                    if (!ba) strictly = true;
                }
            }
            return strictly;
        }
    }
};

fn slotRank(comptime q: Qual) u32 {
    return switch (q) {
        .type_value => 4,
        .exact => 3,
        .pred => 2,
        .bare, .tvar => 1,
    };
}

/// specificity is a property of the METHOD, not of the slot alone: a
/// binder carrying a `where` gate sits on the predicate rung, because
/// `x<:Integer` and `x::T where T <: Integer` are the same statement
/// (README §4) and must therefore rank the same.
fn effRank(comptime m: Method, comptime i: usize) u32 {
    comptime {
        const s = m.signature[i];
        switch (s.qual) {
            .tvar => |v| {
                for (m.gates) |g| {
                    if (std.mem.eql(u8, g.tvar, v)) return 2;
                }
                return 1;
            },
            else => return slotRank(s.qual),
        }
    }
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
                        // a gate is a dependency edge like any call: the
                        // predicate word must survive context collapse or
                        // matching itself becomes unresolvable.
                        for (m.gates) |gt| {
                            if (!containsWord(words[0..n], gt.word)) {
                                words[n] = gt.word;
                                n += 1;
                                changed = true;
                            }
                        }
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
        if (std.mem.eql(u8, word, "<:")) {
            const fields = @typeInfo(Raw).@"struct".fields;
            if (fields.len != 2) @compileError("jpp: '<:' requires two type values.");
            for (fields) |f| if (f.type != type or !f.is_comptime)
                @compileError("jpp: '<:' requires two type values.");
        }
        var cands: [64]Resolved = undefined;
        var n: usize = 0;
        for (0..ctx.len) |i| {
            const mod = ctx[i];
            if (!@hasDecl(mod, word)) continue;
            const MM = @field(mod, word);
            if (@TypeOf(MM) != type or !@hasDecl(MM, "is_mm")) continue;
            for (MM.methods) |m| {
                const B = construct(m.signature, Raw) orelse continue;
                const candidate_ctx = extendAll(ctx, StaticOf(m.declaration_home orelse mod));
                if (!eqsOk(candidate_ctx, m, B)) continue;
                // gates resolve caller-first with the home's static as
                // fallback — the same reach a BODY gets. applicability
                // stays caller-derived (a caller extending `Integer` leads
                // by position) without forcing every caller to import the
                // predicate module.
                if (!gatesOk(candidate_ctx, m, B)) continue;
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
                if (P.moreSpecific(ctx, cands[j].m, cands[i].m)) {
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
        if (first_max == null) @compileError("jpp: call of '" ++ word ++ "' has no maximal method (cyclic strict order).");
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
                        .type_value => |V| msg = msg ++ "=" ++ @typeName(V),
                        .exact => |E| msg = msg ++ "::" ++ @typeName(E),
                        .pred => msg = msg ++ "<:pred",
                        .bare => {},
                        .tvar => |v| msg = msg ++ "::" ++ v,
                    }
                }
                msg = msg ++ ")";
                for (m.gates, 0..) |g, k| {
                    msg = msg ++ (if (k == 0) " where " else ", ") ++ g.tvar ++ " <: " ++ g.word;
                }
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

const ValueInfo = struct { T: type, value: ?type = null };

fn refInfo(comptime r: ValRef, comptime B: type, comptime locals: []const ValueInfo) ValueInfo {
    return switch (r) {
        .param_type => |p| .{ .T = type, .value = fieldTypeAt(B, p) },
        .type_value => |V| .{ .T = type, .value = V },
        .param => |p| blk: {
            const f = @typeInfo(B).@"struct".fields[p];
            break :blk .{ .T = f.type, .value = if (f.type == type) f.defaultValue().? else null };
        },
        .local => |l| locals[l],
        .lit_i => .{ .T = i64 },
        .lit_f => .{ .T = f64 },
        .lit_s => .{ .T = []const u8 },
        .lit_b => .{ .T = bool },
    };
}

fn infoPack(comptime infos: []const ValueInfo) type {
    comptime {
        var names: [infos.len][]const u8 = undefined;
        var ts: [infos.len]type = undefined;
        var attrs: [infos.len]std.builtin.Type.StructField.Attributes = @splat(.{});
        for (infos, 0..) |info, i| {
            names[i] = std.fmt.comptimePrint("{d}", .{i});
            ts[i] = info.T;
            if (info.value) |V| attrs[i] = .{ .@"comptime" = true, .default_value_ptr = &V };
        }
        return @Struct(.auto, null, &names, &ts, &attrs);
    }
}

fn argPack(comptime args: []const ValRef, comptime B: type, comptime locals: []const ValueInfo) type {
    comptime {
        var infos: [args.len]ValueInfo = undefined;
        for (args, 0..) |r, j| infos[j] = refInfo(r, B, locals);
        return infoPack(&infos);
    }
}

fn localInfo(comptime ctx: anytype, comptime flat: Flat, comptime B: type) [flat.ops.len]ValueInfo {
    comptime {
        @setEvalBranchQuota(1_000_000);
        var infos: [flat.ops.len]ValueInfo = undefined;
        for (flat.ops, 0..) |op, i| {
            const Raw = argPack(op.args, B, infos[0..i]);
            const T = RetOf(ctx, op.callee, Raw);
            infos[i] = .{ .T = T, .value = if (T == type) call(ctx, op.callee, @as(Raw, undefined)) else null };
        }
        return infos;
    }
}

fn flatRet(comptime ctx: anytype, comptime flat: Flat, comptime B: type) type {
    const infos = comptime localInfo(ctx, flat, B);
    return comptime refInfo(flat.result, B, &infos).T;
}

fn methodRet(comptime xctx: anytype, comptime m: Method, comptime B: type) type {
    if (m.ret_variable) |v| return typeOfVar(m.signature, B, v) orelse @compileError("jpp: unbound return type variable.");
    if (m.ret) |T| return T; // declared wins
    return switch (m.body) {
        .ground => |G| G.Ret(B), // inferred across the boundary (@TypeOf mirror)
        .ops => |flat| flatRet(xctx, flat, B),
    };
}

fn orderIdentity(comptime Raw: type) bool {
    const fields = @typeInfo(Raw).@"struct".fields;
    if (fields.len != 2) @compileError("jpp: '<:' requires two type values.");
    inline for (fields) |f| if (f.type != type or !f.is_comptime)
        @compileError("jpp: '<:' requires two type values.");
    return fields[0].defaultValue().? == fields[1].defaultValue().?;
}

/// Return type of a call; inferred returns are context-derived.
pub fn RetOf(comptime ctx: anytype, comptime word: []const u8, comptime Raw: type) type {
    if (comptime std.mem.eql(u8, word, "<:") and orderIdentity(Raw)) return bool;
    const c = comptime canon(ctx, word);
    const r = comptime resolve(c, word, Raw) orelse {
        if (std.mem.eql(u8, word, "<:")) return bool;
        @compileError("jpp: no method '" ++ word ++ "' matches in context." ++ candidatesText(ctx, word));
    };
    const Ret = methodRet(extendAll(c, StaticOf(r.m.declaration_home orelse r.home)), r.m, r.B);
    if (std.mem.eql(u8, word, "<:") and Ret != bool) @compileError("jpp: '<:' must return bool.");
    return Ret;
}

fn refValue(comptime r: ValRef, bound: anytype, locals: anytype) refInfo(r, @TypeOf(bound), &packInfo(@TypeOf(locals))).T {
    return switch (r) {
        .param_type => |p| fieldTypeAt(@TypeOf(bound), p),
        .type_value => |V| V,
        .param => |p| fieldAt(bound, p),
        .local => |l| fieldAt(locals, l),
        .lit_i => |v| @as(i64, v),
        .lit_f => |v| @as(f64, v),
        .lit_s => |v| @as([]const u8, v),
        .lit_b => |v| v,
    };
}

fn packInfo(comptime B: type) [@typeInfo(B).@"struct".fields.len]ValueInfo {
    comptime {
        const fields = @typeInfo(B).@"struct".fields;
        var infos: [fields.len]ValueInfo = undefined;
        for (fields, 0..) |f, i| infos[i] = .{ .T = f.type, .value = if (f.type == type) f.defaultValue().? else null };
        return infos;
    }
}

/// Static type values remain in pack types through every ANF call boundary.
/// Ordinary fields remain runtime data; incidental literals do not specialize
/// an instance. A type result may depend only on information known at comptime.
fn exec(comptime ctx: anytype, comptime flat: Flat, bound: anytype) flatRet(ctx, flat, @TypeOf(bound)) {
    const B = @TypeOf(bound);
    const infos = comptime localInfo(ctx, flat, B);
    var locals: infoPack(&infos) = undefined;
    inline for (flat.ops, 0..) |op, i| {
        if (comptime infos[i].T != type) {
            const Raw = argPack(op.args, B, &infos);
            var raw: Raw = undefined;
            inline for (op.args, 0..) |r, j| {
                if (comptime !@typeInfo(Raw).@"struct".fields[j].is_comptime)
                    @field(raw, std.fmt.comptimePrint("{d}", .{j})) = refValue(r, bound, locals);
            }
            @field(locals, std.fmt.comptimePrint("{d}", .{i})) = call(ctx, op.callee, raw);
        }
    }
    if (comptime refInfo(flat.result, B, &infos).value) |V| return V;
    return refValue(flat.result, bound, locals);
}

/// THE call: collapse, resolve, bind, interpret. entering a resolved
/// method, the effective context is caller ++ home STATIC (dedup,
/// caller ahead) — context reaches downward and accumulates.
pub fn call(comptime ctx: anytype, comptime word: []const u8, raw: anytype) RetOf(ctx, word, @TypeOf(raw)) {
    const c = comptime canon(ctx, word);
    if (comptime std.mem.eql(u8, word, "<:") and orderIdentity(@TypeOf(raw))) return true;
    const resolved = comptime resolve(c, word, @TypeOf(raw));
    const r = resolved orelse {
        if (comptime std.mem.eql(u8, word, "<:")) {
            const fields = @typeInfo(@TypeOf(raw)).@"struct".fields;
            return comptime typeLeq(ctx, fields[0].defaultValue().?, fields[1].defaultValue().?);
        }
        unreachable;
    };
    const bound = bindValues(r.m.signature, r.B, raw);
    if (comptime r.m.body == .ground) {
        return r.m.body.ground.run(bound); // axioms take no context
    } else {
        return exec(comptime extendAll(c, StaticOf(r.m.declaration_home orelse r.home)), r.m.body.ops, bound);
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
        return exec(comptime extendAll(xctx, StaticOf(r.m.declaration_home orelse r.home)), r.m.body.ops, bound);
    }
}

fn DelegateRet(comptime rctx: anytype, comptime xctx: anytype, comptime word: []const u8, comptime Raw: type) type {
    const r = comptime resolve(rctx, word, Raw) orelse
        @compileError("jpp: no method '" ++ word ++ "' in delegated context");
    return methodRet(extendAll(xctx, StaticOf(r.m.declaration_home orelse r.home)), r.m, r.B);
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
        .bare, .tvar => .yes,
        .type_value => |S| switch (a) {
            .type_value => |T| if (T == S) .yes else .no,
            else => .no,
        },
        .exact => |S| switch (a) {
            .type_value => if (S == type) .yes else .no,
            .exact => |T| if (T == S) Tri.yes else Tri.no,
            .pred => .unknown, // P could denote exactly {S} — unknowable
            .bare, .tvar => .no,
        },
        .pred => |Q| switch (a) {
            .type_value => if (Q(type)) .yes else .no,
            .exact => |T| if (Q(T)) Tri.yes else Tri.no, // point witness
            .pred => |P| if (predLeq(ctx, P, Q)) Tri.yes else Tri.unknown,
            .bare, .tvar => .unknown, // bare <= Q iff Q is total — unknowable
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
                .type_value => |T| switch (sb.qual) {
                    .type_value => |S| if (T == S) sa.qual else return null,
                    .exact => |S| if (S == type) sa.qual else return null,
                    .pred => |Q| if (Q(type)) sa.qual else return null,
                    .bare, .tvar => sa.qual,
                },
                .exact => |T| switch (sb.qual) {
                    .type_value => if (T == type) sb.qual else return null,
                    .exact => |S| if (T == S) sa.qual else return null,
                    .pred => |Q| if (Q(T)) sa.qual else return null,
                    .bare, .tvar => sa.qual,
                },
                .pred => |P| switch (sb.qual) {
                    .type_value => if (P(type)) sb.qual else return null,
                    .exact => |S| if (P(S)) sb.qual else return null,
                    .pred => |Q| if (P == Q) sa.qual else Qual{ .pred = conj(P, Q) },
                    .bare, .tvar => sa.qual,
                },
                .bare, .tvar => sb.qual,
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

test "ironing: a mutual pair ties; identity is unshadowable" {
    const cyclic = struct {
        pub const @"<:" = Edges(&.{
            .{ .sub = isInt, .sup = isNum },
            .{ .sub = isNum, .sup = isInt }, // mutual edges tie this pair
        });
    };
    // These two direct answers tie specificity. No transitive equivalence
    // closure or structural type identity is inferred from the pair.
    try std.testing.expect(comptime predLeq(.{cyclic}, isInt, isNum));
    try std.testing.expect(comptime predLeq(.{cyclic}, isNum, isInt));

    const denier = struct {
        pub const @"<:" = Edges(&.{.{ .sub = isInt, .sup = isInt, .holds = false }});
    };
    // identity short-circuits BEFORE tables: self-facts are dead letters
    try std.testing.expect(comptime predLeq(.{denier}, isInt, isInt));
}

test "tvar: repeating T is identity; T == S queries a mutual pair" {
    const diag = [_]Slot{
        .{ .name = "a", .qual = .{ .tvar = "T" } },
        .{ .name = "b", .qual = .{ .tvar = "T" } },
    };
    const Same = struct { @"0": i64, @"1": i64 };
    const Diff = struct { @"0": i64, @"1": f64 };
    try std.testing.expect(comptime construct(&diag, Same) != null);
    try std.testing.expect(comptime construct(&diag, Diff) == null);

    const mix = struct {
        pub const @"<:" = Edges(&.{
            .{ .sub = Exact(i64), .sup = Exact(u64) },
            .{ .sub = Exact(u64), .sup = Exact(i64) },
        });
        pub const check = MultiMethod("check", &.{.{
            .name = "check",
            .signature = &.{
                .{ .name = "a", .qual = .{ .tvar = "T" } },
                .{ .name = "b", .qual = .{ .tvar = "S" } },
            },
            .eqs = &.{.{ .a = "T", .b = "S" }},
            .body = .{ .ground = GroundConst(1) },
        }});
    };
    const IU = struct { @"0": i64, @"1": u64 };
    const IF = struct { @"0": i64, @"1": f64 };
    try std.testing.expect(comptime typesEquiv(.{mix}, i64, u64));
    try std.testing.expect(comptime !typesEquiv(.{mix}, i64, f64));
    try std.testing.expect(comptime typesEquiv(.{}, i64, i64)); // T<:T via reflexivity, no shortcut
    try std.testing.expect(comptime resolve(.{mix}, "check", IU) != null);
    try std.testing.expect(comptime resolve(.{mix}, "check", IF) == null);
}

// --- boundary tests: promises pinned on THIS machinery ------------------------

fn GroundConst(comptime v: i64) type {
    return struct {
        pub fn Ret(comptime B: type) type {
            _ = B;
            return i64;
        }
        pub fn run(bound: anytype) i64 {
            _ = bound;
            return v;
        }
    };
}

const GroundIsInt = struct {
    pub fn Ret(comptime B: type) type {
        _ = B;
        return bool;
    }
    pub fn run(bound: anytype) bool {
        return switch (@typeInfo(bound.T)) {
            .int => true,
            else => false,
        };
    }
};

// a predicate is an ordinary word whose slot is qualed on `type`, so the
// ARGUMENT is a type carried as a value. this is the whole basis of
// `where T <: Integer` desugaring to the gate `Integer(T)`.
test "a `type`-qualed slot carries a type as a value" {
    const preds = struct {
        pub const Integer = MultiMethod("Integer", &.{.{
            .name = "Integer",
            .signature = &.{.{ .name = "T", .qual = .{ .exact = type } }},
            .ret = bool,
            .body = .{ .ground = GroundIsInt },
        }});
    };
    try std.testing.expect(comptime call(.{preds}, "Integer", .{i32}));
    try std.testing.expect(comptime !call(.{preds}, "Integer", .{f64}));
}

fn GroundAdd(comptime T: type) type {
    return struct {
        pub fn Ret(comptime B: type) type {
            _ = B;
            return T;
        }
        pub fn run(bound: anytype) T {
            return @field(bound, "a") +% @field(bound, "b");
        }
    };
}

fn GroundPlus100(comptime T: type) type {
    return struct {
        pub fn Ret(comptime B: type) type {
            _ = B;
            return T;
        }
        pub fn run(bound: anytype) T {
            return @field(bound, "a") + @field(bound, "b") + 100;
        }
    };
}

const t_ints = struct {
    pub const @"+" = MultiMethod("+", &.{.{
        .name = "+",
        .signature = &.{
            .{ .name = "a", .qual = .{ .exact = i64 } },
            .{ .name = "b", .qual = .{ .exact = i64 } },
        },
        .body = .{ .ground = GroundAdd(i64) },
    }});
};

const t_lib = struct { // double(x) = x + x — meaning of `+` from context
    pub const double = MultiMethod("double", &.{.{
        .name = "double",
        .signature = &.{.{ .name = "x", .qual = .bare }},
        .body = .{ .ops = .{ .ops = &.{
            .{ .callee = "+", .args = &.{ .{ .param = 0 }, .{ .param = 0 } } },
        }, .result = .{ .local = 0 } } },
    }});
};

const R1 = struct { i64 };

fn Inst(comptime ctx: anytype, comptime word: []const u8, comptime Raw: type) type {
    return struct {
        fn go(raw: Raw) RetOf(ctx, word, Raw) {
            return call(ctx, word, raw);
        }
    };
}

test "export gating: a non-pub word is invisible to resolution" {
    const fixture = @import("mixed_vis_fixture.zig");
    var n: i64 = 1;
    n += 0;
    try std.testing.expectEqualStrings("from fixture", call(.{fixture}, "visible", .{n}));
    try std.testing.expect(comptime resolve(.{fixture}, "hidden", R1) == null);
}

test "collapse: an inert caller converges to the library's own instance" {
    const inert = struct {
        pub const unrelated = 17;
    };
    const full = canon(.{ inert, t_ints, t_lib }, "double");
    const own = canon(.{ t_ints, t_lib }, "double");
    try std.testing.expect(&Inst(full, "double", R1).go == &Inst(own, "double", R1).go);

    const shadow = struct {
        pub const @"+" = MultiMethod("+", &.{.{
            .name = "+",
            .signature = &.{
                .{ .name = "a", .qual = .{ .exact = i64 } },
                .{ .name = "b", .qual = .{ .exact = i64 } },
            },
            .body = .{ .ground = GroundPlus100(i64) },
        }});
    };
    const shadowed = canon(.{ shadow, t_ints, t_lib }, "double");
    try std.testing.expect(&Inst(shadowed, "double", R1).go != &Inst(own, "double", R1).go);
}

test "delegation: M.f picks M's method, the body speaks the caller's language" {
    const my_double = struct {
        pub const double = MultiMethod("double", &.{.{
            .name = "double",
            .signature = &.{.{ .name = "x", .qual = .{ .exact = i64 } }},
            .body = .{ .ground = GroundConst(0) },
        }});
    };
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
    const CALLER = .{ my_double, plus100, t_ints, t_lib };

    var n: i64 = 21;
    n += 0;
    try std.testing.expectEqual(@as(i64, 0), call(CALLER, "double", .{n}));
    try std.testing.expectEqual(@as(i64, 142), delegate(.{ t_ints, t_lib }, CALLER, "double", .{n}));
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

test "bound packs preserve type values but erase incidental data constants" {
    const sig = [_]Slot{
        .{ .name = "T", .section = .named, .qual = .{ .exact = type } },
        .{ .name = "x", .section = .named, .qual = .{ .exact = i64 } },
    };
    const first = .{ .x = @as(i64, 1), .T = i64 };
    const second = .{ .T = i64, .x = @as(i64, 2) };
    const other = .{ .x = @as(i64, 1), .T = u64 };
    const B = comptime construct(&sig, @TypeOf(first)).?;
    try std.testing.expect(B == comptime construct(&sig, @TypeOf(second)).?);
    try std.testing.expect(B != comptime construct(&sig, @TypeOf(other)).?);
    const bound = bindValues(&sig, B, first);
    try std.testing.expect(bound.T == i64);
    try std.testing.expectEqual(@as(i64, 1), bound.x);
    try std.testing.expect(@typeInfo(B).@"struct".fields[0].is_comptime);
    try std.testing.expect(!@typeInfo(B).@"struct".fields[1].is_comptime);
}

test "type-value signature inclusion and intersection agree with construction" {
    const literal = [_]Slot{.{ .name = "v", .qual = .{ .type_value = i64 } }};
    const domain = [_]Slot{.{ .name = "v", .qual = .{ .exact = type } }};
    const other = [_]Slot{.{ .name = "v", .qual = .{ .type_value = f64 } }};
    const data = [_]Slot{.{ .name = "v", .qual = .{ .exact = i64 } }};
    try std.testing.expectEqual(Tri.yes, comptime sigLeq(.{}, &literal, &domain));
    try std.testing.expectEqual(Tri.no, comptime sigLeq(.{}, &domain, &literal));
    const meet = comptime sigMeet(&literal, &domain).?;
    try std.testing.expect(comptime construct(meet, @TypeOf(.{i64})) != null);
    try std.testing.expect(comptime construct(meet, @TypeOf(.{f64})) == null);
    try std.testing.expect(comptime sigMeet(&literal, &other) == null);
    try std.testing.expect(comptime sigMeet(&literal, &data) == null);
}

test "an explicit surface negative is not replaced by a legacy positive" {
    const negative = struct {
        pub const @"<:" = MultiMethod("<:", &.{.{
            .name = "<:",
            .signature = &.{
                .{ .name = "a", .qual = .{ .type_value = i32 } },
                .{ .name = "b", .qual = .{ .type_value = u32 } },
            },
            .body = .{ .ops = .{ .ops = &.{}, .result = .{ .lit_b = false } } },
        }});
    };
    const legacy = struct {
        pub const @"<:" = Edges(&.{
            .{ .sub = Exact(i32), .sup = Exact(u32) },
            .{ .sub = Exact(u32), .sup = Exact(i32) },
        });
    };
    const ctx = .{ negative, legacy };
    try std.testing.expect(!comptime typesEquiv(ctx, i32, u32));
    try std.testing.expect(!call(ctx, "<:", .{ i32, u32 }));
    try std.testing.expect(call(ctx, "<:", .{ u32, i32 }));
}
