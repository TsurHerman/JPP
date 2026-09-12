// ast.zig — intended AST model; the active parser still owns its smaller AST.
//
// THREE representations, each with one producer and one consumer (ratified):
//
//   1. Expr     surface — uniform, homoiconic: julia's Expr (head + args),
//               with JuliaSyntax's lesson applied: every node carries its
//               source SPAN (julia's classic Expr lost provenance to loose
//               LineNumberNodes and they rebuilt the parser a decade later
//               to fix it — we start there). produced by the PARSER.
//               no static guarantees by design: it represents what was
//               WRITTEN, not what is meant.
//   2. Method   checked — what the READER makes of a definition Expr:
//               slots classified, ranks derivable, where attached. the
//               body stays a (block) Expr. meaning lives here.
//   3. FlatBody computational — ANF op vector, produced by the NORMALIZER,
//               consumed by the EMITTER.
//
// pipeline: text -> Expr -> Method -> FlatBody -> printed zig.
//
// there is no Stmt type: "statement" is not a real category. a bind is an
// assign node — it names a data edge, not a computation (thorin view) —
// and erases at normalization. a body is just a block Expr whose value is
// its last child.

pub const Span = struct {
    start: u32 = 0, // byte offsets into the module's source
    end: u32 = 0,
};

// --- layer 1: Expr — the surface form ----------------------------------------

/// an expression is an ATOM (symbol | literal | ground block) or a HEAD
/// plus children. heads are a CLOSED enum (exhaustive switches in the
/// reader) rather than julia's open Symbols; future macros arrive through
/// a macrocall head, never new heads.
pub const Expr = struct {
    span: Span = .{},
    kind: Kind,

    pub const Kind = union(enum) {
        symbol: []const u8, // a name; resolution deferred to context
        int: []const u8, // textual — comptime ints are arbitrary precision
        float: []const u8,
        string: []const u8,
        ground: Ground, // zig{}/c{}/llvm{} — the one non-julia atom
        node: Node,
    };

    pub const Node = struct {
        head: Head,
        args: []const Expr,
    };
};

/// head vocabulary — julia's names and shapes where julia has them
/// (julia-9/10). the callee of :call is the FIRST CHILD, julia-style:
/// even "what is called" is just an expression (functions are values).
pub const Head = enum {
    call, //      f(a, b)      -> (call f a b)
    curly, //     f{T}         -> (curly f T)     comptime application
    block, //     { ... }      value = last child
    tuple, //     a, b
    splat, //     t...
    @"if", //     c ? a : b    -> (if c a b)
    assign, //    lhs = rhs    definitions AND binds — the reader decides
    typed, //     x::T         (julia's :(::))
    subtype, //   x<:P
    where, //     sig where pred
    @"for", //    for b in it { ... }   top level = staged codegen
    using, //  using mod
    @"export", // export a, b, ...
    type_decl, // type arm64
};

pub const Ground = struct {
    lang: enum { zig, c, llvm },
    src: []const u8, // captured RAW by the lexer; never parsed. axiom.
};

// {} disambiguation (ratified, lexical, no lookahead):
//   IDENT{            juxtaposed, no space -> curly   (julia's own f{T} rule)
//   zig{ c{ llvm{     -> ground atom, body captured raw by the lexer
//   otherwise {       -> block

// --- layer 2: Method & friends — the checked form -----------------------------

/// a program is just modules — deliberately NO whole-program structure.
/// the call/instance graph does not exist statically: zig comptime
/// derives it lazily from main's instantiation (it IS the comptime memo
/// table). unit ladder: call = computation, method = meaning, module =
/// organization, instance (method × context × argtypes) = compilation,
/// caching, invalidation.
pub const Program = struct {
    modules: []const Module,
    entry: []const u8 = "main", // module whose main() seeds instantiation
};

pub const Module = struct {
    name: []const u8, // file stem: "ints"
    usings: []const []const u8, // ORDERED — context priority
    exports: []const []const u8,
    defs: []const Def,
};

pub const Def = union(enum) {
    method: Method,
    type_decl: []const u8, // `type arm64`
    const_bind: Bind, // `ARCH::type = zig{...}` — top-level comptime bind
    comptime_for: ComptimeFor, // top-level for = staged codegen
};

/// Methods take ONE semantic pack: positional and named fields, including
/// actual static values. Selectors do not create a second method table or pack.
/// Rest capture is implemented; static-application syntax remains future work.
pub const Method = struct {
    name: []const u8, // "+", "promote", "double" — verbatim (@"name" decl key)
    params: []const Slot = &.{}, // one pattern over the whole pack
    where: ?Expr = null, // comptime predicate over bound names
    ret: ?Expr = null, // a type expression; absent = inferred
    body: Body,
};

/// one grammar for both positions (ratified): brace slots and value slots
/// are the same shape. Specificity compares the same supplied coordinates:
/// fixed coverage precedes rest coverage; within either, type value > exact
/// input type > predicate > bare. Never sum ranks. Named coordinates align by
/// name, positionals by index; structural shape breaks otherwise equal ties.
pub const Slot = struct {
    name: ?[]const u8, // null = anonymous (::arm64, {Integer})
    qual: Qual,
    section: enum { positional, named } = .positional,
    requires_static: bool = false, // future brace/static input requirement
    variadic: bool = false, // TT... / args...
};

pub const Qual = union(enum) {
    exact: Expr, // x::int32   f{int32}   ::arm64
    predicate: Expr, // x<:Integer {T<:P}
    bare, // x          {T}
};

pub const Body = union(enum) {
    ground: Ground, // axiom: no context dispatch inside, one-way door
    expr: Expr, // a block (or single expression); value = last child
};

/// a bind names a data edge — not computation (thorin view: assignments
/// dissolve into dependencies). erases at normalization: jpp bind ->
/// zig const -> llvm SSA. `var` (mutation) is parked with the memory model.
pub const Bind = struct {
    name: []const u8,
    ann: ?Expr = null, // optional ::T on the binder
    value: Expr,
};

pub const ComptimeFor = struct {
    binders: []const []const u8, // for (U, S) in ... — one or more
    iterable: Expr, // a comptime tuple
    defs: []const Def, // generated per iteration
};

// --- layer 3: FlatBody — A-normal form ----------------------------------------
// the normalizer flattens every body into a linear op vector: each op is
//   id = op(operand refs...)
// operands are only REFERENCES (param, earlier id, literal, context name);
// nested expressions dissolve into named intermediates; binds alias an id
// and vanish. ids are edges, ops are nodes, list order is one legal
// schedule of the dataflow graph (SSA<->CPS). the emitter consumes THIS.
// comptime rewrites (mimir-style normalization), if ever, operate here.
// every op keeps the span of its source Expr — provenance threads the
// whole pipeline: .jpp span -> op -> comment in printed zig -> mapped
// comptime error.
//
// control flow: `select` carries two REGIONS (flat sub-bodies) — flatness
// is recursive, not global.

pub const FlatBody = struct {
    ops: []const Op,
    result: ValRef, // the body's value
};

pub const Op = struct {
    id: u32, // referenced by later ops as .{ .local = id }
    span: Span = .{}, // of the source Expr
    kind: OpKind,
};

pub const OpKind = union(enum) {
    call: FlatCall, // the unit of computation
    pack: []const Entry,
    project: struct { value: ValRef, field: []const u8 },
    select: Select, // ternary — arms are regions, not eager operands
    ground: Ground, // zig{} in expression position
};

pub const FlatCall = struct {
    callee: []const u8,
    args: []const Entry = &.{},
};

pub const Entry = struct {
    label: ?[]const u8 = null, // null = positional; otherwise a named field
    value: ValRef,
    splat: enum { none, positional, named } = .none, // expand in its written section
};

pub const Select = struct {
    cond: ValRef,
    then: FlatBody,
    els: FlatBody,
};

pub const ValRef = union(enum) {
    param: u32, // index in the single bound pack, static or runtime
    local: u32, // result of a previous op
    lit_int: []const u8, // comptime int, arbitrary precision
    lit_float: []const u8,
    global: []const u8, // module-level name — resolved in context
};

// --- living example: `double(x) = x + x` through all three layers -------------

const x_sym: Expr = .{ .kind = .{ .symbol = "x" } };
const plus_sym: Expr = .{ .kind = .{ .symbol = "+" } };

// layer 1 — what the parser emits for the whole definition line:
//   (assign (call double x) (call + x x))
pub const example_double_surface: Expr = .{ .kind = .{ .node = .{
    .head = .assign,
    .args = &.{
        .{ .kind = .{ .node = .{ .head = .call, .args = &.{
            .{ .kind = .{ .symbol = "double" } },
            x_sym,
        } } } },
        .{ .kind = .{ .node = .{ .head = .call, .args = &.{
            plus_sym,
            x_sym,
            x_sym,
        } } } },
    },
} } };

// layer 2 — what the reader makes of it:
pub const example_double: Method = .{
    .name = "double",
    .params = &.{
        .{ .name = "x", .qual = .bare }, // rank 1
    },
    .body = .{ .expr = .{ .kind = .{ .node = .{ .head = .call, .args = &.{
        plus_sym,
        x_sym,
        x_sym,
    } } } } },
};

// layer 3 — normalized: one op, result is its id.
pub const example_double_flat: FlatBody = .{
    .ops = &.{
        .{ .id = 0, .kind = .{ .call = .{
            .callee = "+",
            .args = &.{ .{ .value = .{ .param = 0 } }, .{ .value = .{ .param = 0 } } },
        } } },
    },
    .result = .{ .local = 0 },
};

test "layer 1: surface Expr is (assign (call double x) (call + x x))" {
    const std = @import("std");
    const def = example_double_surface.kind.node;
    try std.testing.expect(def.head == .assign);
    const sig = def.args[0].kind.node;
    try std.testing.expect(sig.head == .call);
    try std.testing.expectEqualStrings("double", sig.args[0].kind.symbol);
    const body = def.args[1].kind.node;
    try std.testing.expect(body.head == .call);
    try std.testing.expectEqualStrings("+", body.args[0].kind.symbol);
}

test "layer 2: reader output" {
    const std = @import("std");
    try std.testing.expectEqualStrings("double", example_double.name);
    const body = example_double.body.expr.kind.node;
    try std.testing.expect(body.head == .call);
    try std.testing.expect(body.args.len == 3); // callee + two args
}

test "layer 3: ANF is one op" {
    const std = @import("std");
    try std.testing.expect(example_double_flat.ops.len == 1);
    const op = example_double_flat.ops[0];
    try std.testing.expectEqualStrings("+", op.kind.call.callee);
    try std.testing.expect(example_double_flat.result.local == op.id);
}
