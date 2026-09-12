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
    rest: bool = false,
    elementwise: bool = false, // short predicate annotation checks each captured element
    qual: Qual,
};

pub const ValRef = union(enum) {
    bound_type: []const u8, // a uniform type binding, including empty-rest witnesses
    param_type: usize, // a where-bound type, obtained from an input field
    type_value: type,
    param: usize, //  bound pack field, by slot index
    local: usize, //  result of an earlier op
    lit_i: i64, //    integer literal (jpp default: int64)
    lit_f: f64, //    float literal   (jpp default: float64)
    lit_s: []const u8, // string literal (jpp string = []const u8)
    lit_b: bool, //    boolean literal (`<:` facts are the motivating use)
};

pub const Op = struct {
    kind: enum { call, pack, project } = .call,
    callee: []const u8 = "",
    args: []const ValRef,
    // Empty labels are positional. Written order is retained through ANF.
    labels: []const []const u8 = &.{},
    splats: []const enum { none, positional, named } = &.{},
    field: []const u8 = "", // project: one operand, statically named field
};
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
    shape: ?[]const Slot = null, // original shape when comparing supplied coordinates
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
        if (!slot.rest and slot.qual == .exact and slot.qual.exact == type and std.mem.eql(u8, slot.name, name)) return true;
    }
    return false;
}

pub fn MultiMethod(comptime word: []const u8, comptime list: []const Method) type {
    for (list) |m| {
        for (m.signature, 0..) |slot, i| {
            for (m.signature[0..i]) |previous| if (previous.rest and previous.section == slot.section)
                @compileError("jpp: rest input must be last in its section.");
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
                if (slot.rest) @compileError("jpp: '<:' requires two fixed type-value inputs.");
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

/// Composition follows raw authored methods, never another forwarded field.
/// This prevents recursive declaration aliases in import cycles and preserves
/// each method's original lexical home. A word with no provider remains empty.
pub fn ReexportWord(comptime word: []const u8, comptime roots: anytype) type {
    comptime {
        @setEvalBranchQuota(1_000_000);
        var pending: [512]type = undefined;
        var n: usize = 0;
        for (roots) |mod| {
            if (contains(pending[0..n], mod)) continue;
            if (n == pending.len) @compileError("jpp: reexport module limit exceeded.");
            pending[n] = mod;
            n += 1;
        }
        var list: []const Method = &.{};
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const mod = pending[i];
            if (@hasDecl(mod, "LOCAL") and @hasDecl(mod.LOCAL, word)) {
                list = list ++ @field(mod.LOCAL, word).methods;
                continue;
            }
            // Legacy native fixtures have direct methods and no source metadata.
            if (!@hasDecl(mod, "EXPORTED")) {
                if (@hasDecl(mod, word)) {
                    const MM = @field(mod, word);
                    if (@TypeOf(MM) == type and @hasDecl(MM, "is_mm")) list = list ++ MM.methods;
                }
                continue;
            }
            if (!exportedName(mod, word)) continue;
            const is_sources = @hasDecl(mod, "SOURCES");
            const raw_members = @hasDecl(mod, "IS_DISPATCH_UNIT");
            const next = if (is_sources) mod.SOURCES else if (@hasDecl(mod, "STATIC")) mod.STATIC else .{};
            for (next) |source| {
                if (!is_sources and source == mod) continue;
                const target = if (raw_members) source else dispatchUnit(source);
                if (contains(pending[0..n], target)) continue;
                if (n == pending.len) @compileError("jpp: reexport module limit exceeded.");
                pending[n] = target;
                n += 1;
            }
        }
        return MultiMethod(word, list);
    }
}

pub fn MergedWord(comptime word: []const u8, comptime mods: anytype) type {
    return ReexportWord(word, extendAll(.{}, mods));
}

pub fn UnitWord(comptime word: []const u8, comptime mods: anytype) type {
    return ReexportWord(word, mods);
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

/// Route a supplied coordinate to its fixed slot or its section's rest.
fn slotFor(comptime sig: []const Slot, comptime name: []const u8) ?usize {
    if (positionOf(name)) |position| {
        var ordinal: usize = 0;
        for (sig, 0..) |slot, i| {
            if (slot.section != .positional) continue;
            if (slot.rest or ordinal == position) return i;
            ordinal += 1;
        }
    } else {
        for (sig, 0..) |slot, i| {
            if (slot.section == .named and !slot.rest and std.mem.eql(u8, slot.name, name)) return i;
        }
        for (sig, 0..) |slot, i| if (slot.section == .named and slot.rest) return i;
    }
    return null;
}

fn variableKey(comptime name: []const u8) []const u8 {
    return "#type#" ++ name;
}

pub fn boundType(comptime B: type, comptime name: []const u8) type {
    if (@hasField(B, variableKey(name))) return @field(@as(B, undefined), variableKey(name));
    if (@hasField(B, name)) return @field(@as(B, undefined), name);
    @compileError("jpp: unbound type variable '" ++ name ++ "'.");
}

/// raw call-site pack type -> bound pack type (declared slot order) or null.
pub fn construct(comptime sig: []const Slot, comptime Raw: type) ?type {
    comptime {
        @setEvalBranchQuota(1_000_000);
        const rf = @typeInfo(Raw).@"struct".fields;
        var names: [sig.len * 2][]const u8 = undefined;
        var ts: [sig.len * 2]type = undefined;
        var attrs: [sig.len * 2]std.builtin.Type.StructField.Attributes = @splat(.{});
        var vars: []const []const u8 = &.{};
        for (sig) |slot| {
            if (slot.qual == .tvar and !slot.elementwise and !containsWord(vars, slot.qual.tvar))
                vars = vars ++ .{slot.qual.tvar};
        }
        var bindings: [sig.len]?type = @splat(null);
        for (rf) |f| {
            const i = slotFor(sig, f.name) orelse return null;
            const slot = sig[i];
            if (!qualOk(slot.qual, f)) return null;
            for (vars, 0..) |v, vi| {
                const value = if (slot.qual == .tvar and !slot.elementwise and std.mem.eql(u8, slot.qual.tvar, v))
                    f.type
                else if (!slot.rest and slot.qual == .exact and slot.qual.exact == type and std.mem.eql(u8, slot.name, v))
                    f.defaultValue() orelse return null
                else
                    continue;
                if (bindings[vi]) |previous| {
                    if (previous != value) return null;
                } else bindings[vi] = value;
            }
        }
        for (sig, 0..) |slot, i| {
            names[i] = slot.name;
            for (names[0..i]) |previous| if (std.mem.eql(u8, previous, slot.name)) {
                names[i] = std.fmt.comptimePrint("__fixed{d}", .{i});
                break;
            };
            var infos: []const ValueInfo = &.{};
            var labels: []const []const u8 = &.{};
            for (rf) |f| {
                if (slotFor(sig, f.name).? != i) continue;
                infos = infos ++ .{fieldInfo(f)};
                labels = labels ++ .{if (slot.section == .named) f.name else ""};
            }
            if (slot.rest) {
                ts[i] = namedInfoPack(infos, labels, true);
            } else {
                if (infos.len != 1) return null;
                ts[i] = infos[0].T;
                if (infos[0].value) |ptr| attrs[i] = .{ .@"comptime" = true, .default_value_ptr = ptr };
            }
        }
        for (vars, 0..) |v, vi| {
            const T = bindings[vi] orelse return null; // an empty rest cannot invent T
            names[sig.len + vi] = variableKey(v);
            ts[sig.len + vi] = type;
            attrs[sig.len + vi] = .{ .@"comptime" = true, .default_value_ptr = &T };
        }
        return @Struct(.auto, null, names[0 .. sig.len + vars.len], ts[0 .. sig.len + vars.len], attrs[0 .. sig.len + vars.len]);
    }
}

/// Value routing follows the same coordinate map as construction.
pub fn bindValues(comptime sig: []const Slot, comptime B: type, raw: anytype) B {
    var out: B = undefined;
    inline for (sig, 0..) |slot, i| {
        const f = @typeInfo(B).@"struct".fields[i];
        if (comptime slot.rest) {
            var rest: f.type = undefined;
            comptime var ordinal: usize = 0;
            inline for (@typeInfo(@TypeOf(raw)).@"struct".fields) |source| {
                if (comptime slotFor(sig, source.name).? != i) continue;
                const name = comptime if (slot.section == .named) source.name else std.fmt.comptimePrint("{d}", .{ordinal});
                if (comptime !source.is_comptime) @field(rest, name) = @field(raw, source.name);
                ordinal += 1;
            }
            @field(out, f.name) = rest;
        } else if (comptime !f.is_comptime) {
            inline for (@typeInfo(@TypeOf(raw)).@"struct".fields) |source| {
                if (comptime slotFor(sig, source.name).? == i) @field(out, f.name) = @field(raw, source.name);
            }
        }
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

fn unitScopeHas(comptime mod: type, comptime name: []const u8) bool {
    if (@hasDecl(mod, "DISPATCH_HOME")) return exportedName(mod.DISPATCH_HOME, name);
    if (@hasDecl(mod, "UNIT")) return exportedName(dispatchUnit(mod.UNIT), name);
    return false;
}

/// Exporting a word declares its identity, not a fallback implementation.
/// Check lexical dependencies independently of whether a body is instantiated.
/// Only the source module and its direct imports supply declarations; caller
/// context selects implementations later and cannot repair misspellings.
pub fn validateCalls(comptime scope: anytype, comptime owner: []const u8, comptime words: []const []const u8) void {
    @setEvalBranchQuota(1_000_000);
    for (words) |word| {
        const found = blk: {
            inline for (scope, 0..) |mod, i| {
                const names = if (i == 0) mod.DECLARED else dispatchUnit(mod).EXPORTED;
                inline for (names) |n| if (std.mem.eql(u8, word, n)) break :blk true;
                if (i == 0 and unitScopeHas(mod, word)) break :blk true;
            }
            break :blk false;
        };
        if (!found) @compileError("jpp: undeclared call '" ++ word ++ "' in '" ++ scope[0].MODULE_NAME ++ "." ++ owner ++ "' (define, import, or export the word).");
    }
}

pub fn declaredValue(comptime scope: anytype, comptime name: []const u8) ?type {
    if (builtinType(name)) |T| return T;
    inline for (scope, 0..) |mod, i| {
        const names = if (i == 0) mod.DECLARED else dispatchUnit(mod).EXPORTED;
        inline for (names) |n| if (std.mem.eql(u8, name, n)) {
            if (i == 0 and !exportedName(mod, name) and !std.mem.eql(u8, name, "main"))
                return Word(mod.MODULE_NAME ++ "#" ++ name);
            return Word(name);
        };
        if (i == 0 and unitScopeHas(mod, name)) return Word(name);
    }
    return null;
}

pub fn requireValue(comptime scope: anytype, comptime name: []const u8) type {
    return declaredValue(scope, name) orelse @compileError("jpp: undefined value '" ++ name ++ "' (define it or import its definition).");
}

/// Declaration lookup is lexical; dispatch remains caller-contextual. A fresh
/// name binds an input. An explicit annotation gives it a signature role even
/// when the body ignores its value. Unused, unannotated slots error, including
/// anonymous ones; a misspelled class must not silently become a generic rule.
pub fn declarationQual(comptime scope: anytype, comptime name: ?[]const u8, comptime q: Qual, comptime used: bool) Qual {
    if (name) |n| {
        if (declaredValue(scope, n)) |V| {
            if (q != .bare and !(q == .exact and q.exact == type))
                @compileError("jpp: defined value '" ++ n ++ "' cannot be rebound by an input annotation.");
            return .{ .type_value = V };
        }
    }
    if (!used and q == .bare) {
        const label = if (name) |n| "'" ++ n ++ "'" else "(anonymous)";
        @compileError("jpp: unused input " ++ label ++ "; annotate its type or predicate, or define/import the intended value.");
    }
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
        if (@hasField(B, variableKey(name))) return boundType(B, name);
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
            const each: ?usize = for (m.signature, 0..) |slot, i| {
                if (slot.elementwise and slot.qual == .tvar and std.mem.eql(u8, slot.qual.tvar, g.tvar)) break i;
            } else null;
            if (each) |i| {
                for (@typeInfo(fieldTypeAt(B, i)).@"struct".fields) |f| {
                    if (!call(ctx, g.word, .{f.type})) return false;
                }
            } else {
                const T = typeOfVar(m.signature, B, g.tvar) orelse return false;
                if (!call(ctx, g.word, .{T})) return false;
            }
        }
        return true;
    }
}

// Compare the same supplied coordinate, not parallel declaration indices.
fn alignedSlot(comptime a: []const Slot, comptime i: usize, comptime b: []const Slot) ?usize {
    if (a[i].section == .positional) {
        var ordinal: usize = 0;
        for (a[0..i]) |slot| if (slot.section == .positional) {
            ordinal += 1;
        };
        var seen: usize = 0;
        for (b, 0..) |slot, j| {
            if (slot.section != .positional) continue;
            if (seen == ordinal) return j;
            seen += 1;
        }
    } else {
        for (b, 0..) |slot, j| if (slot.section == .named and std.mem.eql(u8, slot.name, a[i].name)) return j;
    }
    return null;
}

fn positionalMinimum(comptime sig: []const Slot) usize {
    var n: usize = 0;
    for (sig) |s| if (s.section == .positional and !s.rest) {
        n += 1;
    };
    return n;
}

fn hasRest(comptime sig: []const Slot, comptime section: Section) bool {
    for (sig) |s| if (s.section == section and s.rest) return true;
    return false;
}

fn requiredName(comptime sig: []const Slot, comptime name: []const u8) bool {
    for (sig) |s| if (s.section == .named and !s.rest and std.mem.eql(u8, s.name, name)) return true;
    return false;
}

fn shapeLeq(comptime a: []const Slot, comptime b: []const Slot) bool {
    const amin = positionalMinimum(a);
    const bmin = positionalMinimum(b);
    if (amin < bmin) return false;
    if (!hasRest(b, .positional) and (hasRest(a, .positional) or amin != bmin)) return false;
    for (b) |s| if (s.section == .named and !s.rest and !requiredName(a, s.name)) return false;
    if (!hasRest(b, .named)) {
        if (hasRest(a, .named)) return false;
        for (a) |s| if (s.section == .named and !s.rest and !requiredName(b, s.name)) return false;
    }
    return true;
}

fn shapeNarrower(comptime a: []const Slot, comptime b: []const Slot) bool {
    return shapeLeq(a, b) and !shapeLeq(b, a);
}

// Give a policy the actual coordinates, retaining original shape and coverage.
fn suppliedMethod(comptime m: Method, comptime Raw: type) Method {
    var out = m;
    var sig: []const Slot = &.{};
    for (@typeInfo(Raw).@"struct".fields) |f| {
        var slot = m.signature[slotFor(m.signature, f.name).?];
        // Positional names are irrelevant; named-rest labels belong to the call.
        if (slot.section == .named) slot.name = f.name;
        sig = sig ++ .{slot};
    }
    out.shape = m.signature;
    out.signature = sig;
    return out;
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
                const j = alignedSlot(a.signature, i, b.signature) orelse return false;
                const rb = effRank(b, j);
                if (ra < rb) return false;
                if (ra > rb) strictly = true;
            }
            return strictly or shapeNarrower(a.shape orelse a.signature, b.shape orelse b.signature);
        }
    }
};

const ground_policy = struct {
    pub fn moreSpecific(comptime ctx: anytype, comptime a: Method, comptime b: Method) bool {
        comptime {
            if (a.signature.len != b.signature.len) return false;
            var strictly: bool = false;
            for (a.signature, 0..) |sa, i| {
                const ra = effRank(a, i);
                const j = alignedSlot(a.signature, i, b.signature) orelse return false;
                const rb = effRank(b, j);
                const sb = b.signature[j];
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
                const gb = gatesAt(b, j);
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
            return strictly or shapeNarrower(a.shape orelse a.signature, b.shape orelse b.signature);
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
        const coverage: u32 = if (s.rest) 0 else 4;
        switch (s.qual) {
            .tvar => |v| {
                for (m.gates) |g| {
                    if (std.mem.eql(u8, g.tvar, v)) return coverage + 2;
                }
                return coverage + 1;
            },
            else => return coverage + slotRank(s.qual),
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

pub fn dispatchUnit(comptime mod: type) type {
    return if (@hasDecl(mod, "UNIT")) dispatchUnit(mod.UNIT) else mod;
}

fn dispatchHome(comptime mod: type) type {
    return if (@hasDecl(mod, "DISPATCH_HOME")) mod.DISPATCH_HOME else mod;
}

pub fn contains(comptime ctx: anytype, comptime mod: type) bool {
    inline for (ctx) |m| if (m == mod) return true;
    return false;
}

fn ExtendAllT(comptime ctx: anytype, comptime mods: anytype, comptime i: usize) type {
    if (i == mods.len) return @TypeOf(ctx);
    if (contains(ctx, dispatchUnit(mods[i]))) return ExtendAllT(ctx, mods, i + 1);
    return ExtendAllT(ctx ++ .{dispatchUnit(mods[i])}, mods, i + 1);
}

fn extendAllFrom(comptime ctx: anytype, comptime mods: anytype, comptime i: usize) ExtendAllT(ctx, mods, i) {
    if (i == mods.len) return ctx;
    if (comptime contains(ctx, dispatchUnit(mods[i]))) return extendAllFrom(ctx, mods, i + 1);
    return extendAllFrom(ctx ++ .{dispatchUnit(mods[i])}, mods, i + 1);
}

fn Extended(comptime ctx: anytype, comptime mods: anytype) type {
    // A declaration caches the value as well as its type. Return-type mirrors
    // otherwise repeat the same context construction through deep inference.
    return struct {
        const value = blk: {
            @setEvalBranchQuota(1_000_000);
            break :blk extendAllFrom(extendAllFrom(.{}, ctx, 0), mods, 0);
        };
    };
}

pub fn extendAll(comptime ctx: anytype, comptime mods: anytype) @TypeOf(Extended(ctx, mods).value) {
    return Extended(ctx, mods).value;
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

fn DependencyModules(comptime ctx: anytype) type {
    return struct {
        // Only a discovery universe: these imports do NOT enter the caller's
        // resolution context until the corresponding method is entered.
        const value = blk: {
            @setEvalBranchQuota(1_000_000);
            var mods: [512]type = undefined;
            var n: usize = 0;
            for (ctx) |mod| {
                if (contains(mods[0..n], mod)) continue;
                if (n == mods.len) @compileError("jpp: dependency module limit exceeded.");
                mods[n] = mod;
                n += 1;
            }
            var i: usize = 0;
            while (i < n) : (i += 1) {
                for (StaticOf(mods[i])) |mod| {
                    if (contains(mods[0..n], mod)) continue;
                    if (n == mods.len) @compileError("jpp: dependency module limit exceeded.");
                    mods[n] = mod;
                    n += 1;
                }
            }
            break :blk mods[0..n].*;
        };
    };
}

fn footprint(comptime ctx: anytype, comptime word: []const u8) []const []const u8 {
    comptime {
        @setEvalBranchQuota(1_000_000);
        var words: [128][]const u8 = undefined;
        // The judge and the order can themselves call ordinary words.
        var n: usize = 3;
        words[0] = word;
        words[1] = "<:";
        words[2] = "specificity";
        const mods = DependencyModules(ctx).value;
        // Scan each discovered word once. Repeatedly rescanning the entire
        // prefix made ordinary deep module graphs exhaust the comptime quota.
        var wi: usize = 0;
        while (wi < n) : (wi += 1) {
            const w = words[wi];
            for (mods) |mod| {
                if (!@hasDecl(mod, w)) continue;
                const MM = @field(mod, w);
                if (@TypeOf(MM) != type or !@hasDecl(MM, "is_mm")) continue;
                for (MM.methods) |m| {
                    // a gate is a dependency edge like any call: the
                    // predicate word must survive context collapse or
                    // matching itself becomes unresolvable.
                    for (m.gates) |gt| {
                        if (!containsWord(words[0..n], gt.word)) {
                            if (n == words.len) @compileError("jpp: dependency word limit exceeded.");
                            words[n] = gt.word;
                            n += 1;
                        }
                    }
                    if (m.body != .ops) continue;
                    for (m.body.ops.ops) |op| {
                        if (op.kind != .call) continue;
                        if (!containsWord(words[0..n], op.callee)) {
                            if (n == words.len) @compileError("jpp: dependency word limit exceeded.");
                            words[n] = op.callee;
                            n += 1;
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

fn Canonical(comptime ctx: anytype, comptime word: []const u8) type {
    return struct {
        const value = blk: {
            @setEvalBranchQuota(1_000_000);
            const units = extendAll(.{}, ctx);
            break :blk canonFrom(.{}, units, footprint(units, word), 0);
        };
    };
}

pub fn canon(comptime ctx: anytype, comptime word: []const u8) @TypeOf(Canonical(ctx, word).value) {
    return Canonical(ctx, word).value;
}

// --- resolution ------------------------------------------------------------------------

const Resolved = struct { m: Method, B: type, home: type, unit: ?type = null };

fn methodUnit(comptime method: Method) ?type {
    const home = method.declaration_home orelse return null;
    if (@hasDecl(home, "DISPATCH_HOME")) return home.DISPATCH_HOME;
    if (@hasDecl(home, "UNIT")) return dispatchUnit(home.UNIT);
    return null;
}

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
            const candidate_home = dispatchHome(mod);
            const earlier_modules = n;
            for (MM.methods) |m| {
                const unit = methodUnit(m);
                // A facade view and its full unit can both be present. They
                // may expose the same authored method, which is one candidate.
                const duplicate = for (cands[0..earlier_modules]) |prior| {
                    if ((prior.home == candidate_home or (unit != null and prior.unit == unit)) and std.meta.eql(prior.m, m)) break true;
                } else false;
                if (duplicate) continue;
                const B = construct(m.signature, Raw) orelse continue;
                const candidate_ctx = extendAll(ctx, StaticOf(m.declaration_home orelse mod));
                if (!eqsOk(candidate_ctx, m, B)) continue;
                // gates resolve caller-first with the home's static as
                // fallback — the same reach a BODY gets. applicability
                // stays caller-derived (a caller extending `Integer` leads
                // by position) without forcing every caller to import the
                // predicate module.
                if (!gatesOk(candidate_ctx, m, B)) continue;
                cands[n] = .{ .m = m, .B = B, .home = candidate_home, .unit = unit };
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
                if (P.moreSpecific(ctx, suppliedMethod(cands[j].m, Raw), suppliedMethod(cands[i].m, Raw))) {
                    dominated = true;
                    break;
                }
            }
            if (dominated) continue;
            max_count += 1;
            if (first_max == null) {
                first_max = cands[i]; // gather order = context order = position
            } else if (cands[i].home == first_max.?.home or
                (cands[i].unit != null and cands[i].unit == first_max.?.unit))
            {
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
                    if (s.rest) msg = msg ++ "...";
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

// Static availability belongs to fields, not to incidental constant folding.
// A static field carries its actual value in the pack type; a runtime field
// carries only its type. This also preserves non-type selectors from grounds.
const ValueInfo = struct { T: type, value: ?*const anyopaque = null };

fn staticInfo(comptime value: anytype) ValueInfo {
    return .{ .T = @TypeOf(value), .value = &value };
}

fn staticValue(comptime info: ValueInfo) info.T {
    return @as(*const info.T, @ptrCast(@alignCast(info.value.?))).*;
}

fn fieldInfo(comptime f: std.builtin.Type.StructField) ValueInfo {
    return .{ .T = f.type, .value = if (f.is_comptime) f.default_value_ptr else null };
}

fn refInfo(comptime r: ValRef, comptime B: type, comptime locals: []const ValueInfo) ValueInfo {
    return switch (r) {
        .bound_type => |name| staticInfo(boundType(B, name)),
        .param_type => |p| staticInfo(fieldTypeAt(B, p)),
        .type_value => |V| staticInfo(V),
        .param => |p| fieldInfo(@typeInfo(B).@"struct".fields[p]),
        .local => |l| locals[l],
        .lit_i => .{ .T = i64 },
        .lit_f => .{ .T = f64 },
        .lit_s => .{ .T = []const u8 },
        .lit_b => .{ .T = bool },
    };
}

fn entryName(comptime labels: []const []const u8, comptime i: usize) []const u8 {
    if (labels.len > 0 and labels[i].len > 0) return labels[i];
    return std.fmt.comptimePrint("{d}", .{i});
}

fn namedInfoPack(comptime infos: []const ValueInfo, comptime labels: []const []const u8, comptime canonical: bool) type {
    comptime {
        if (labels.len != 0 and labels.len != infos.len) @compileError("jpp: invalid pack labels.");
        var names: [infos.len][]const u8 = undefined;
        var ts: [infos.len]type = undefined;
        var attrs: [infos.len]std.builtin.Type.StructField.Attributes = @splat(.{});
        var named = false;
        for (infos, 0..) |info, i| {
            names[i] = entryName(labels, i);
            const is_named = positionOf(names[i]) == null;
            if (named and !is_named) @compileError("jpp: positional field after named section.");
            named = named or is_named;
            for (names[0..i]) |prior| if (std.mem.eql(u8, prior, names[i])) @compileError("jpp: duplicate pack field.");
            ts[i] = info.T;
            if (info.value) |ptr| attrs[i] = .{ .@"comptime" = true, .default_value_ptr = ptr };
        }
        // Positional indices retain their order. Named value identity is
        // independent of spelling order; this does not promise a foreign ABI.
        if (canonical) {
            for (0..infos.len) |i| {
                if (positionOf(names[i]) != null) continue;
                for (i + 1..infos.len) |j| {
                    if (std.mem.lessThan(u8, names[j], names[i])) {
                        std.mem.swap([]const u8, &names[i], &names[j]);
                        std.mem.swap(type, &ts[i], &ts[j]);
                        std.mem.swap(std.builtin.Type.StructField.Attributes, &attrs[i], &attrs[j]);
                    }
                }
            }
        }
        return @Struct(.auto, null, &names, &ts, &attrs);
    }
}

fn infoPack(comptime infos: []const ValueInfo) type {
    return namedInfoPack(infos, &.{}, false);
}

/// Native representation boundary used by the ordinary Tuple library.
pub fn tupleLen(comptime T: type) i64 {
    if (@typeInfo(T) != .@"struct") @compileError("jpp: tuple operation requires positional fields.");
    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields, 0..) |f, i| {
        if (comptime !std.mem.eql(u8, f.name, std.fmt.comptimePrint("{d}", .{i})))
            @compileError("jpp: tuple operation requires positional fields.");
    }
    return @intCast(fields.len);
}

fn TailType(comptime T: type) type {
    const n = tupleLen(T);
    if (n == 0) @compileError("jpp: tail requires a nonempty tuple.");
    const fields = @typeInfo(T).@"struct".fields;
    var infos: [fields.len - 1]ValueInfo = undefined;
    for (fields[1..], 0..) |f, i| infos[i] = fieldInfo(f);
    return infoPack(&infos);
}

pub fn tupleTail(value: anytype) TailType(@TypeOf(value)) {
    const T = TailType(@TypeOf(value));
    var out: T = undefined;
    inline for (@typeInfo(T).@"struct".fields, 0..) |f, i| {
        if (comptime !f.is_comptime) @field(out, f.name) = fieldAt(value, i + 1);
    }
    return out;
}

const ExpandedEntry = struct { source: usize, field: ?[]const u8 = null, label: []const u8, info: ValueInfo };

fn expandedEntries(comptime op: Op, comptime B: type, comptime locals: []const ValueInfo) []const ExpandedEntry {
    comptime {
        var entries: []const ExpandedEntry = &.{};
        for (op.args, 0..) |r, i| {
            const info = refInfo(r, B, locals);
            const splat = if (op.splats.len == 0) .none else op.splats[i];
            if (splat == .none) {
                entries = entries ++ .{ExpandedEntry{ .source = i, .label = if (op.labels.len == 0) "" else op.labels[i], .info = info }};
            } else {
                if (@typeInfo(info.T) != .@"struct") @compileError("jpp: splat requires a statically shaped tuple or record.");
                for (@typeInfo(info.T).@"struct".fields, 0..) |f, fi| {
                    const positional = positionOf(f.name) != null;
                    if ((splat == .positional) != positional) @compileError("jpp: splat cannot cross positional and named sections.");
                    if (positional and positionOf(f.name).? != fi) @compileError("jpp: positional splat requires contiguous tuple fields.");
                    entries = entries ++ .{ExpandedEntry{
                        .source = i,
                        .field = f.name,
                        .label = if (positional) "" else f.name,
                        .info = projectedInfo(info, f.name),
                    }};
                }
            }
        }
        return entries;
    }
}

fn argPack(comptime op: Op, comptime B: type, comptime locals: []const ValueInfo) type {
    comptime {
        const entries = expandedEntries(op, B, locals);
        var infos: [entries.len]ValueInfo = undefined;
        var labels: [entries.len][]const u8 = undefined;
        for (entries, 0..) |entry, i| {
            infos[i] = entry.info;
            labels[i] = entry.label;
        }
        return namedInfoPack(&infos, &labels, op.kind == .pack);
    }
}

fn projectedInfo(comptime parent: ValueInfo, comptime field: []const u8) ValueInfo {
    if (@typeInfo(parent.T) != .@"struct") @compileError("jpp: field projection requires a tuple or record.");
    for (@typeInfo(parent.T).@"struct".fields) |f| {
        if (std.mem.eql(u8, f.name, field)) {
            if (parent.value != null) return staticInfo(@field(staticValue(parent), field));
            return fieldInfo(f);
        }
    }
    @compileError("jpp: no field '" ++ field ++ "' in tuple or record.");
}

fn callInfo(comptime ctx: anytype, comptime word: []const u8, comptime Raw: type) ValueInfo {
    const T = RetOf(ctx, word, Raw);
    if (T == type) return staticInfo(call(ctx, word, @as(Raw, undefined)));
    const c = canon(ctx, word);
    const r = resolve(c, word, Raw) orelse return .{ .T = T };
    if (r.m.body == .ops) {
        const flat = r.m.body.ops;
        const infos = localInfo(extendAll(c, StaticOf(r.m.declaration_home orelse r.home)), flat, r.B);
        const result = refInfo(flat.result, r.B, &infos);
        if (result.T == T) return result;
    }
    return .{ .T = T };
}

fn localInfo(comptime ctx: anytype, comptime flat: Flat, comptime B: type) [flat.ops.len]ValueInfo {
    return LocalInfos(ctx, flat, B).value;
}

fn LocalInfos(comptime ctx: anytype, comptime flat: Flat, comptime B: type) type {
    return struct {
        const value = blk: {
            @setEvalBranchQuota(1_000_000);
            var infos: [flat.ops.len]ValueInfo = undefined;
            for (flat.ops, 0..) |op, i| {
                infos[i] = switch (op.kind) {
                    .call => callInfo(ctx, op.callee, argPack(op, B, infos[0..i])),
                    .pack => .{ .T = argPack(op, B, infos[0..i]) },
                    .project => projectedInfo(refInfo(op.args[0], B, infos[0..i]), op.field),
                };
            }
            break :blk infos;
        };
    };
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
        .bound_type => |name| boundType(@TypeOf(bound), name),
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
        for (fields, 0..) |f, i| infos[i] = fieldInfo(f);
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
        // Static results need no value storage, but calls may still have
        // runtime effects before returning a static field. Execute those calls.
        if (comptime infos[i].value == null or (op.kind == .call and infos[i].T != type)) {
            if (comptime op.kind == .project) {
                @field(locals, std.fmt.comptimePrint("{d}", .{i})) = @field(refValue(op.args[0], bound, locals), op.field);
            } else {
                const Raw = argPack(op, B, &infos);
                var raw: Raw = undefined;
                inline for (comptime expandedEntries(op, B, &infos), 0..) |entry, j| {
                    const name = comptime if (entry.label.len == 0) std.fmt.comptimePrint("{d}", .{j}) else entry.label;
                    const f = comptime @typeInfo(Raw).@"struct".fields[std.meta.fieldIndex(Raw, name).?];
                    if (comptime !f.is_comptime) {
                        const source = refValue(op.args[entry.source], bound, locals);
                        @field(raw, name) = if (comptime entry.field) |field| @field(source, field) else source;
                    }
                }
                const value = if (comptime op.kind == .pack) raw else call(ctx, op.callee, raw);
                if (comptime infos[i].value == null) @field(locals, std.fmt.comptimePrint("{d}", .{i})) = value;
            }
        }
    }
    const result = comptime refInfo(flat.result, B, &infos);
    if (comptime result.value != null) return staticValue(result);
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
        @setEvalBranchQuota(1_000_000);
        if (!shapeLeq(a, b)) return .no;
        var acc: Tri = .yes;
        for (0..positionalMinimum(a) + @intFromBool(hasRest(a, .positional))) |i| {
            const name = std.fmt.comptimePrint("{d}", .{i});
            acc = triAll(acc, qualLeq(ctx, a[slotFor(a, name).?].qual, b[slotFor(b, name).?].qual));
        }
        for (a) |slot| {
            if (slot.section != .named) continue;
            const name = if (slot.rest) "#unknown#" else slot.name;
            acc = triAll(acc, qualLeq(ctx, slot.qual, b[slotFor(b, name).?].qual));
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

fn qualMeet(comptime a: Qual, comptime b: Qual) ?Qual {
    return switch (a) {
        .type_value => |T| switch (b) {
            .type_value => |S| if (T == S) a else return null,
            .exact => |S| if (S == type) a else return null,
            .pred => |Q| if (Q(type)) a else return null,
            .bare, .tvar => a,
        },
        .exact => |T| switch (b) {
            .type_value => if (T == type) b else return null,
            .exact => |S| if (T == S) a else return null,
            .pred => |Q| if (Q(T)) a else return null,
            .bare, .tvar => a,
        },
        .pred => |P| switch (b) {
            .type_value => if (P(type)) b else return null,
            .exact => |S| if (P(S)) b else return null,
            .pred => |Q| if (P == Q) a else Qual{ .pred = conj(P, Q) },
            .bare, .tvar => a,
        },
        .bare, .tvar => b,
    };
}

/// Structural intersection, including an empty-only overlap of disjoint rests.
/// Gates and repeated-variable correlations need Method-level analysis.
pub fn sigMeet(comptime a: []const Slot, comptime b: []const Slot) ?[]const Slot {
    comptime {
        @setEvalBranchQuota(1_000_000);
        const amin = positionalMinimum(a);
        const bmin = positionalMinimum(b);
        if ((!hasRest(a, .positional) and amin < bmin) or (!hasRest(b, .positional) and bmin < amin)) return null;
        var out: []const Slot = &.{};
        const count = @max(amin, bmin);
        for (0..count) |i| {
            const name = std.fmt.comptimePrint("{d}", .{i});
            const sa = a[slotFor(a, name) orelse return null];
            const sb = b[slotFor(b, name) orelse return null];
            out = out ++ .{Slot{ .name = name, .qual = qualMeet(sa.qual, sb.qual) orelse return null }};
        }
        if (hasRest(a, .positional) and hasRest(b, .positional)) {
            const name = std.fmt.comptimePrint("{d}", .{count});
            if (qualMeet(a[slotFor(a, name).?].qual, b[slotFor(b, name).?].qual)) |q|
                out = out ++ .{Slot{ .name = "#rest#", .rest = true, .qual = q }};
        }
        for (a ++ b) |slot| {
            if (slot.section != .named or slot.rest or requiredName(out, slot.name)) continue;
            const sa = a[slotFor(a, slot.name) orelse return null];
            const sb = b[slotFor(b, slot.name) orelse return null];
            out = out ++ .{Slot{ .name = slot.name, .section = .named, .qual = qualMeet(sa.qual, sb.qual) orelse return null }};
        }
        if (hasRest(a, .named) and hasRest(b, .named)) {
            if (qualMeet(a[slotFor(a, "#unknown#").?].qual, b[slotFor(b, "#unknown#").?].qual)) |q|
                out = out ++ .{Slot{ .name = "#named-rest#", .section = .named, .rest = true, .qual = q }};
        }
        return out;
    }
}

fn hasAnyRest(comptime sig: []const Slot) bool {
    return hasRest(sig, .positional) or hasRest(sig, .named);
}

/// ledger primitive: is (a, b) an ambiguous pair? (neither contains the
/// other, intersection not provably empty.) .unknown widens the lint.
pub fn ambiguousPair(comptime ctx: anytype, comptime a: []const Slot, comptime b: []const Slot) Tri {
    comptime {
        // Inclusion alone cannot certify rest preference: empty captures have
        // no element witness. Actual calls use suppliedMethod and full gates.
        if (hasAnyRest(a) or hasAnyRest(b)) return if (sigMeet(a, b) == null) .no else .unknown;
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
        if (hasAnyRest(a) or hasAnyRest(b) or hasAnyRest(c)) return .unknown;
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
    // Specify runtime fields at the native boundary, as the surface emitter
    // does. A Zig anonymous literal may itself create comptime fields.
    const first: struct { x: i64, comptime T: type = i64 } = .{ .x = 1 };
    const second: struct { comptime T: type = i64, x: i64 } = .{ .x = 2 };
    const other: struct { x: i64, comptime T: type = u64 } = .{ .x = 1 };
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

test "rest dispatch compares supplied coordinates then accepted shape" {
    const empty: Method = .{ .name = "choose", .signature = &.{}, .body = .{ .ground = GroundStr("empty") } };
    const any: Method = .{ .name = "choose", .signature = &.{.{ .name = "xs", .rest = true, .qual = .bare }}, .body = .{ .ground = GroundStr("rest") } };
    const ints: Method = .{ .name = "choose", .signature = &.{.{ .name = "xs", .rest = true, .qual = .{ .exact = i64 } }}, .body = .{ .ground = GroundStr("ints") } };
    const floats: Method = .{ .name = "choose", .signature = &.{.{ .name = "xs", .rest = true, .qual = .{ .exact = f64 } }}, .body = .{ .ground = GroundStr("floats") } };
    const fixed: Method = .{ .name = "choose", .signature = &.{.{ .name = "x", .qual = .bare }}, .body = .{ .ground = GroundStr("fixed") } };
    const Raw0 = @TypeOf(.{});
    const Raw1 = struct { i64 };
    const Raw2 = struct { i64, i64 };
    try std.testing.expect(comptime ground_policy.moreSpecific(.{}, suppliedMethod(empty, Raw0), suppliedMethod(any, Raw0)));
    try std.testing.expect(comptime ground_policy.moreSpecific(.{}, suppliedMethod(fixed, Raw1), suppliedMethod(ints, Raw1)));
    try std.testing.expect(comptime ground_policy.moreSpecific(.{}, suppliedMethod(ints, Raw2), suppliedMethod(any, Raw2)));
    try std.testing.expect(comptime !ground_policy.moreSpecific(.{}, suppliedMethod(ints, Raw0), suppliedMethod(floats, Raw0)));
    try std.testing.expect(comptime !ground_policy.moreSpecific(.{}, suppliedMethod(floats, Raw0), suppliedMethod(ints, Raw0)));
    const crossing: Method = .{ .name = "choose", .signature = &.{
        .{ .name = "x", .qual = .bare }, .{ .name = "xs", .rest = true, .qual = .bare },
    }, .body = .{ .ground = GroundStr("crossing") } };
    try std.testing.expect(comptime !ground_policy.moreSpecific(.{}, suppliedMethod(crossing, Raw2), suppliedMethod(ints, Raw2)));
    try std.testing.expect(comptime !ground_policy.moreSpecific(.{}, suppliedMethod(ints, Raw2), suppliedMethod(crossing, Raw2)));
}

test "rest binding preserves sections, uniform witnesses, and static fields" {
    const sig = [_]Slot{
        .{ .name = "xs", .rest = true, .qual = .{ .tvar = "T" } },
        .{ .name = "T", .section = .named, .qual = .{ .exact = type } },
        .{ .name = "opts", .section = .named, .rest = true, .qual = .bare },
    };
    // Explicit type values must be static; declare the witness accordingly.
    const StaticRaw = struct { @"0": i64, comptime T: type = i64, comptime flag: bool = true, z: i64 };
    const B = comptime construct(&sig, StaticRaw).?;
    const bound = bindValues(&sig, B, StaticRaw{ .@"0" = 7, .z = 9 });
    try std.testing.expectEqual(@as(i64, 7), bound.xs.@"0");
    try std.testing.expectEqual(@as(i64, 9), bound.opts.z);
    try std.testing.expect(comptime @typeInfo(@TypeOf(bound.opts)).@"struct".fields[0].is_comptime);
    try std.testing.expect(comptime boundType(B, "T") == i64);
    const Empty = struct { comptime T: type = i64 };
    try std.testing.expect(comptime construct(&sig, Empty) != null);
    const unbound = [_]Slot{.{ .name = "xs", .rest = true, .qual = .{ .tvar = "T" } }};
    try std.testing.expect(comptime construct(&unbound, @TypeOf(.{})) == null);
    try std.testing.expect(comptime construct(&unbound, struct { i64, f64 }) == null);
}

test "signature ledger preserves empty rest intersections without certifying preference" {
    const ints = [_]Slot{.{ .name = "xs", .rest = true, .qual = .{ .exact = i64 } }};
    const floats = [_]Slot{.{ .name = "xs", .rest = true, .qual = .{ .exact = f64 } }};
    const any = [_]Slot{.{ .name = "xs", .rest = true, .qual = .bare }};
    const fixed = [_]Slot{.{ .name = "x", .qual = .{ .exact = i64 } }};
    try std.testing.expect(comptime sigLeq(.{}, &fixed, &ints) == .yes);
    try std.testing.expect(comptime sigLeq(.{}, &ints, &fixed) == .no);
    try std.testing.expect(comptime sigMeet(&ints, &floats).?.len == 0);
    try std.testing.expect(comptime sigMeet(&fixed, &floats) == null);
    try std.testing.expect(comptime ambiguousPair(.{}, &ints, &any) == .unknown);
    const named = [_]Slot{.{ .name = "x", .section = .named, .qual = .{ .exact = i64 } }};
    const named_rest = [_]Slot{.{ .name = "opts", .section = .named, .rest = true, .qual = .bare }};
    try std.testing.expect(comptime sigLeq(.{}, &named, &named_rest) == .yes);
    try std.testing.expect(comptime sigMeet(&named, &named_rest).?.len == 1);
}
