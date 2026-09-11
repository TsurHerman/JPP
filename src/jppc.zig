// jppc.zig — the jpp transpiler: .jpp text -> zig data-literal modules.
//
// deliberately DUMB: file-local, context-blind, no type checking. five
// stages, each a pure function: lex -> parse -> read -> normalize ->
// print. all semantics (dispatch, contexts, specificity, collapse) live
// in src/jpp.zig and run at zig comptime inside the GENERATED files.
//
// v1 surface (scope cuts documented in README):
//   using NAME
//   export a, b, +
//   name(params) [:: retty] = expr
//   expr: literals, idents, calls, { blocks }, zig{ raw ground },
//         infix || && + - * / (that precedence, loosest first) — every
//         operator is an ordinary overridable word, not a builtin
//   params: x (bare) | x::typename (exact) | x::T where T (type var)
//         | x<:Pred (predicate qual; sugar for x::T + gate, T fresh —
//           `::` takes a TYPE, `<:` takes a PREDICATE, never swapped)
//   where T | where T == S | where T <: Pred | where Pred(T)
//     (identity, <: equivalence, predicate gate; see README §4)
//   defined values constrain any signature; fresh names bind inputs.
//   ignored inputs may be annotated or anonymous: x::type, _, ::type, <:Predicate.
//   literals default int64 / float64 (julia-ish)

const std = @import("std");

// ---------------------------------------------------------------- tokens

const TokKind = enum { ident, int, float, str, lparen, rparen, lbrace, rbrace, comma, dcolon, subtype, eq, eqeq, semi, nl, ground, kw_using, kw_export, kw_where, op, dot, eof };

const Tok = struct { kind: TokKind, text: []const u8, pos: usize };

const LexError = error{ UnterminatedGround, BadChar };

fn lex(src: []const u8, toks: []Tok) LexError![]Tok {
    var n: usize = 0;
    var i: usize = 0;
    while (i < src.len) {
        const c = src[i];
        if (c == ' ' or c == '\t' or c == '\r') {
            i += 1;
            continue;
        }
        if (c == '#') {
            while (i < src.len and src[i] != '\n') i += 1;
            continue;
        }
        if (c == '\n') {
            toks[n] = .{ .kind = .nl, .text = "\n", .pos = i };
            n += 1;
            i += 1;
            continue;
        }
        if (std.ascii.isAlphabetic(c) or c == '_') {
            const start = i;
            while (i < src.len and (std.ascii.isAlphanumeric(src[i]) or src[i] == '_')) i += 1;
            const word = src[start..i];
            if (std.mem.eql(u8, word, "using")) {
                toks[n] = .{ .kind = .kw_using, .text = word, .pos = start };
            } else if (std.mem.eql(u8, word, "export")) {
                toks[n] = .{ .kind = .kw_export, .text = word, .pos = start };
            } else if (std.mem.eql(u8, word, "where")) {
                toks[n] = .{ .kind = .kw_where, .text = word, .pos = start };
            } else if (std.mem.eql(u8, word, "zig") and i < src.len and src[i] == '{') {
                // ground capture: raw until balanced '}', strings skipped
                i += 1; // consume '{'
                const gstart = i;
                var depth: usize = 1;
                while (i < src.len and depth > 0) {
                    const g = src[i];
                    if (g == '"') {
                        i += 1;
                        while (i < src.len and src[i] != '"') {
                            if (src[i] == '\\') i += 1;
                            i += 1;
                        }
                    } else if (g == '{') {
                        depth += 1;
                    } else if (g == '}') {
                        depth -= 1;
                        if (depth == 0) break;
                    }
                    i += 1;
                }
                if (depth != 0) return error.UnterminatedGround;
                toks[n] = .{ .kind = .ground, .text = std.mem.trim(u8, src[gstart..i], " \t\n"), .pos = gstart };
                i += 1; // consume final '}'
            } else {
                toks[n] = .{ .kind = .ident, .text = word, .pos = start };
            }
            n += 1;
            continue;
        }
        if (std.ascii.isDigit(c)) {
            const start = i;
            while (i < src.len and std.ascii.isDigit(src[i])) i += 1;
            var isf = false;
            if (i + 1 < src.len and src[i] == '.' and std.ascii.isDigit(src[i + 1])) {
                isf = true;
                i += 1;
                while (i < src.len and std.ascii.isDigit(src[i])) i += 1;
            }
            toks[n] = .{ .kind = if (isf) .float else .int, .text = src[start..i], .pos = start };
            n += 1;
            continue;
        }
        if (c == '"') {
            const start = i;
            i += 1;
            while (i < src.len and src[i] != '"') {
                if (src[i] == '\\') i += 1;
                i += 1;
            }
            if (i >= src.len) return error.BadChar;
            toks[n] = .{ .kind = .str, .text = src[start + 1 .. i], .pos = start };
            n += 1;
            i += 1; // closing quote
            continue;
        }
        const start = i;
        switch (c) {
            '(' => toks[n] = .{ .kind = .lparen, .text = "(", .pos = start },
            ')' => toks[n] = .{ .kind = .rparen, .text = ")", .pos = start },
            '{' => toks[n] = .{ .kind = .lbrace, .text = "{", .pos = start },
            '}' => toks[n] = .{ .kind = .rbrace, .text = "}", .pos = start },
            ',' => toks[n] = .{ .kind = .comma, .text = ",", .pos = start },
            ';' => toks[n] = .{ .kind = .semi, .text = ";", .pos = start },
            '=' => {
                if (i + 1 < src.len and src[i + 1] == '=') {
                    toks[n] = .{ .kind = .eqeq, .text = "==", .pos = start };
                    i += 1;
                } else {
                    toks[n] = .{ .kind = .eq, .text = "=", .pos = start };
                }
            },
            '+', '-', '*', '/' => toks[n] = .{ .kind = .op, .text = src[i .. i + 1], .pos = start },
            // only the doubled forms: a lone `&`/`|` has no meaning yet
            '&', '|' => {
                if (i + 1 < src.len and src[i + 1] == c) {
                    toks[n] = .{ .kind = .op, .text = src[i .. i + 2], .pos = start };
                    i += 1;
                } else return error.BadChar;
            },
            '.' => toks[n] = .{ .kind = .dot, .text = ".", .pos = start },
            ':' => {
                if (i + 1 < src.len and src[i + 1] == ':') {
                    toks[n] = .{ .kind = .dcolon, .text = "::", .pos = start };
                    i += 1;
                } else return error.BadChar;
            },
            // bare `<` stays BadChar: jpp has no comparison operator yet
            '<' => {
                if (i + 1 < src.len and src[i + 1] == ':') {
                    toks[n] = .{ .kind = .subtype, .text = "<:", .pos = start };
                    i += 1;
                } else return error.BadChar;
            },
            else => return error.BadChar,
        }
        n += 1;
        i += 1;
    }
    toks[n] = .{ .kind = .eof, .text = "", .pos = src.len };
    n += 1;
    return toks[0..n];
}

// ---------------------------------------------------------------- surface AST

const Node = union(enum) {
    lit_i: i64,
    lit_f: f64,
    lit_s: []const u8, // raw (escapes preserved verbatim, re-emitted verbatim)
    lit_b: bool,
    ident: []const u8,
    call: struct { callee: []const u8, args: []*Node },
    block: []*Node,
};

// `pred` is the slot-position form `x<:Integer`. README §4: it is sugar
// for `x::T where Integer(T)` with T fresh, so it lowers to a binder
// plus a gate and needs nothing new from the machinery.
const Param = struct { name: []const u8, anonymous: bool = false, ty: ?[]const u8, pred: ?[]const u8 = null };

const Where = struct {
    vars: []const []const u8,
    eqs: []const [2][]const u8,
    gates: []const [2][]const u8, // .{ tvar, predicate word }
};

const Def = struct {
    name: []const u8,
    params: []Param,
    ret: ?[]const u8,
    where_clause: ?Where = null,
    body: ?*Node, // null when ground
    ground: ?[:0]const u8,
};

const Mod = struct {
    name: []const u8,
    usings: [][]const u8,
    exports: [][]const u8,
    defs: []Def,
};

// ---------------------------------------------------------------- parser

const Parser = struct {
    toks: []Tok,
    i: usize = 0,
    a: std.mem.Allocator,

    fn peek(p: *Parser) Tok {
        return p.toks[p.i];
    }
    fn next(p: *Parser) Tok {
        const t = p.toks[p.i];
        if (t.kind != .eof) p.i += 1;
        return t;
    }
    fn skipNl(p: *Parser) void {
        while (p.peek().kind == .nl or p.peek().kind == .semi) _ = p.next();
    }
    fn expect(p: *Parser, k: TokKind) !Tok {
        const t = p.next();
        if (t.kind != k) {
            std.debug.print("jppc: expected {s}, found {s} '{s}' at byte {d}\n", .{ @tagName(k), @tagName(t.kind), t.text, t.pos });
            return error.Parse;
        }
        return t;
    }

    fn node(p: *Parser, v: Node) !*Node {
        const out = try p.a.create(Node);
        out.* = v;
        return out;
    }

    fn parseModule(p: *Parser, name: []const u8) !Mod {
        var usings = try std.ArrayList([]const u8).initCapacity(p.a, 8);
        var exports = try std.ArrayList([]const u8).initCapacity(p.a, 16);
        var defs = try std.ArrayList(Def).initCapacity(p.a, 32);
        p.skipNl();
        while (p.peek().kind != .eof) {
            switch (p.peek().kind) {
                .kw_using => {
                    _ = p.next();
                    // dotted module path: sub-folders are NAMESPACES —
                    // `using ground.ints` names <root>/ground/ints.jpp;
                    // paths are absolute from the tree root.
                    var path = (try p.expect(.ident)).text;
                    while (p.peek().kind == .dot) {
                        _ = p.next();
                        const seg = try p.expect(.ident);
                        path = try std.fmt.allocPrint(p.a, "{s}.{s}", .{ path, seg.text });
                    }
                    try usings.append(p.a, path);
                },
                .kw_export => {
                    _ = p.next();
                    while (true) {
                        const t = p.next();
                        if (t.kind != .ident and t.kind != .op and t.kind != .subtype) return error.Parse;
                        try exports.append(p.a, t.text);
                        if (p.peek().kind == .comma) {
                            _ = p.next();
                            continue;
                        }
                        break;
                    }
                },
                .ident, .op, .subtype => try defs.append(p.a, try p.parseDef()),
                else => {
                    std.debug.print("jppc: unexpected token '{s}' at byte {d}\n", .{ p.peek().text, p.peek().pos });
                    return error.Parse;
                },
            }
            p.skipNl();
        }
        return .{ .name = name, .usings = usings.items, .exports = exports.items, .defs = defs.items };
    }

    fn parseDef(p: *Parser) !Def {
        const name = p.next().text;
        _ = try p.expect(.lparen);
        var params = try std.ArrayList(Param).initCapacity(p.a, 8);
        if (p.peek().kind != .rparen) {
            while (true) {
                if (p.peek().kind != .ident and p.peek().kind != .dcolon and p.peek().kind != .subtype) return error.Parse;
                const spelling = if (p.peek().kind == .ident) p.next().text else "_";
                const anonymous = std.mem.eql(u8, spelling, "_");
                const pn = if (anonymous) try std.fmt.allocPrint(p.a, "__slot{d}", .{params.items.len}) else spelling;
                var ty: ?[]const u8 = null;
                var pred: ?[]const u8 = null;
                if (p.peek().kind == .dcolon) {
                    _ = p.next();
                    ty = (try p.expect(.ident)).text;
                } else if (p.peek().kind == .subtype) {
                    // `::` takes a TYPE, `<:` takes a PREDICATE — rank is
                    // read off the symbol, so the two never share one
                    _ = p.next();
                    pred = (try p.expect(.ident)).text;
                }
                try params.append(p.a, .{ .name = pn, .anonymous = anonymous, .ty = ty, .pred = pred });
                if (p.peek().kind == .comma) {
                    _ = p.next();
                    continue;
                }
                break;
            }
        }
        _ = try p.expect(.rparen);
        var ret: ?[]const u8 = null;
        if (p.peek().kind == .dcolon) {
            _ = p.next();
            ret = (try p.expect(.ident)).text;
        }
        var where_clause: ?Where = null;
        if (p.peek().kind == .kw_where) {
            _ = p.next();
            where_clause = try p.parseWhere();
        }
        _ = try p.expect(.eq);
        p.skipNlOnlyNewlinesBeforeBody();
        if (p.peek().kind == .ground) {
            const g = try p.a.dupeZ(u8, p.next().text);
            return .{ .name = name, .params = params.items, .ret = ret, .where_clause = where_clause, .body = null, .ground = g };
        }
        const body = try p.parseExpr(0);
        return .{ .name = name, .params = params.items, .ret = ret, .where_clause = where_clause, .body = body, .ground = null };
    }

    fn parseWhere(p: *Parser) !Where {
        // where T | where T == S | where T <: Pred | where Pred(T)
        // comma-separated atoms. `T <: Pred` is SUGAR for `Pred(T)`.
        var vars = try std.ArrayList([]const u8).initCapacity(p.a, 4);
        var eqs = try std.ArrayList([2][]const u8).initCapacity(p.a, 4);
        var gates = try std.ArrayList([2][]const u8).initCapacity(p.a, 4);
        while (true) {
            const a = (try p.expect(.ident)).text;
            if (p.peek().kind == .lparen) {
                // Pred(T) — the primitive gate; the binder is the argument
                _ = p.next();
                const v = (try p.expect(.ident)).text;
                _ = try p.expect(.rparen);
                try addWhereVar(&vars, p.a, v);
                try gates.append(p.a, .{ v, a });
            } else {
                try addWhereVar(&vars, p.a, a);
                if (p.peek().kind == .eqeq) {
                    _ = p.next();
                    const b = (try p.expect(.ident)).text;
                    try addWhereVar(&vars, p.a, b);
                    try eqs.append(p.a, .{ a, b });
                } else if (p.peek().kind == .subtype) {
                    _ = p.next();
                    const pred = (try p.expect(.ident)).text;
                    try gates.append(p.a, .{ a, pred });
                }
            }
            if (p.peek().kind == .comma) {
                _ = p.next();
                continue;
            }
            break;
        }
        return .{ .vars = vars.items, .eqs = eqs.items, .gates = gates.items };
    }

    fn skipNlOnlyNewlinesBeforeBody(p: *Parser) void {
        while (p.peek().kind == .nl) _ = p.next();
    }

    fn opPrec(text: []const u8) ?u8 {
        if (std.mem.eql(u8, text, "||")) return 4;
        if (std.mem.eql(u8, text, "&&")) return 6;
        if (text.len != 1) return null;
        return switch (text[0]) {
            '+', '-' => 10,
            '*', '/' => 20,
            else => null,
        };
    }

    fn parseExpr(p: *Parser, min_prec: u8) anyerror!*Node {
        var lhs = try p.parsePrimary();
        while (p.peek().kind == .op) {
            const prec = opPrec(p.peek().text) orelse return error.Parse;
            if (prec < min_prec) break;
            const op = p.next().text;
            const rhs = try p.parseExpr(prec + 1);
            const args = try p.a.alloc(*Node, 2);
            args[0] = lhs;
            args[1] = rhs;
            lhs = try p.node(.{ .call = .{ .callee = op, .args = args } });
        }
        return lhs;
    }

    fn parsePrimary(p: *Parser) anyerror!*Node {
        const t = p.peek();
        switch (t.kind) {
            .int => {
                _ = p.next();
                return p.node(.{ .lit_i = std.fmt.parseInt(i64, t.text, 10) catch return error.Parse });
            },
            .float => {
                _ = p.next();
                return p.node(.{ .lit_f = std.fmt.parseFloat(f64, t.text) catch return error.Parse });
            },
            .str => {
                _ = p.next();
                return p.node(.{ .lit_s = t.text });
            },
            .ident, .subtype => {
                if (std.mem.eql(u8, t.text, "true") or std.mem.eql(u8, t.text, "false")) {
                    _ = p.next();
                    return p.node(.{ .lit_b = std.mem.eql(u8, t.text, "true") });
                }
                _ = p.next();
                if (p.peek().kind == .lparen) {
                    _ = p.next();
                    var args = try std.ArrayList(*Node).initCapacity(p.a, 8);
                    if (p.peek().kind != .rparen) {
                        while (true) {
                            try args.append(p.a, try p.parseExpr(0));
                            if (p.peek().kind == .comma) {
                                _ = p.next();
                                continue;
                            }
                            break;
                        }
                    }
                    _ = try p.expect(.rparen);
                    return p.node(.{ .call = .{ .callee = t.text, .args = args.items } });
                }
                return p.node(.{ .ident = t.text });
            },
            .lparen => {
                _ = p.next();
                const e = try p.parseExpr(0);
                _ = try p.expect(.rparen);
                return e;
            },
            .lbrace => {
                _ = p.next();
                var items = try std.ArrayList(*Node).initCapacity(p.a, 16);
                p.skipNl();
                while (p.peek().kind != .rbrace) {
                    try items.append(p.a, try p.parseExpr(0));
                    p.skipNl();
                }
                _ = try p.expect(.rbrace);
                return p.node(.{ .block = items.items });
            },
            else => {
                std.debug.print("jppc: unexpected '{s}' at byte {d}\n", .{ t.text, t.pos });
                return error.Parse;
            },
        }
    }
};

fn addWhereVar(vars: *std.ArrayList([]const u8), a: std.mem.Allocator, name: []const u8) !void {
    for (vars.items) |v| {
        if (std.mem.eql(u8, v, name)) return;
    }
    try vars.append(a, name);
}

fn isTVar(d: Def, name: []const u8) bool {
    const w = d.where_clause orelse return false;
    for (w.vars) |v| {
        if (std.mem.eql(u8, v, name)) return true;
    }
    return false;
}

// ---------------------------------------------------------------- normalizer (ANF)

const VR = union(enum) { param_type: usize, name: []const u8, param: usize, local: usize, lit_i: i64, lit_f: f64, lit_s: []const u8, lit_b: bool };
const OpIR = struct { callee: []const u8, args: []VR };
const FlatIR = struct { ops: []OpIR, result: VR };

fn flatten(a: std.mem.Allocator, def: Def) !FlatIR {
    var ops = try std.ArrayList(OpIR).initCapacity(a, 32);
    const result = try flattenNode(a, def.body.?, def, &ops);
    return .{ .ops = ops.items, .result = result };
}

fn flattenNode(a: std.mem.Allocator, n: *Node, def: Def, ops: *std.ArrayList(OpIR)) anyerror!VR {
    switch (n.*) {
        .lit_i => |v| return .{ .lit_i = v },
        .lit_f => |v| return .{ .lit_f = v },
        .lit_s => |v| return .{ .lit_s = v },
        .lit_b => |v| return .{ .lit_b = v },
        .ident => |name| {
            for (def.params, 0..) |p, i| {
                if (std.mem.eql(u8, p.name, name)) return .{ .param = i };
            }
            if (isTVar(def, name)) {
                for (def.params, 0..) |p, i| {
                    if (p.ty) |t| if (std.mem.eql(u8, t, name)) return .{ .param_type = i };
                }
            }
            return .{ .name = name };
        },
        .call => |c| {
            const args = try a.alloc(VR, c.args.len);
            for (c.args, 0..) |arg, i| args[i] = try flattenNode(a, arg, def, ops);
            try ops.append(a, .{ .callee = c.callee, .args = args });
            return .{ .local = ops.items.len - 1 };
        },
        .block => |items| {
            var last: ?VR = null;
            for (items) |item| last = try flattenNode(a, item, def, ops);
            return last orelse error.Normalize;
        },
    }
}

// ---------------------------------------------------------------- emitter

const Out = struct {
    buf: []u8,
    len: usize = 0,
    fn add(o: *Out, comptime fmt: []const u8, args: anytype) void {
        const w = std.fmt.bufPrint(o.buf[o.len..], fmt, args) catch @panic("emit buffer full");
        o.len += w.len;
    }
    fn text(o: *Out) []const u8 {
        return o.buf[0..o.len];
    }
};

fn emitFloat(o: *Out, v: f64) void {
    const start = o.len;
    o.add("{d}", .{v});
    // ensure a valid zig float literal (2.0 not 2)
    const s = o.buf[start..o.len];
    if (std.mem.indexOfScalar(u8, s, '.') == null and std.mem.indexOfScalar(u8, s, 'e') == null)
        o.add(".0", .{});
}

fn emitVR(o: *Out, r: VR) void {
    switch (r) {
        .param_type => |p| o.add(".{{ .param_type = {d} }}", .{p}),
        .name => |n| o.add(".{{ .type_value = jpp.requireValue(STATIC, \"{s}\") }}", .{n}),
        .param => |p| o.add(".{{ .param = {d} }}", .{p}),
        .local => |l| o.add(".{{ .local = {d} }}", .{l}),
        .lit_i => |v| o.add(".{{ .lit_i = {d} }}", .{v}),
        .lit_f => |v| {
            o.add(".{{ .lit_f = ", .{});
            emitFloat(o, v);
            o.add(" }}", .{});
        },
        .lit_s => |v| o.add(".{{ .lit_s = \"{s}\" }}", .{v}),
        .lit_b => |v| o.add(".{{ .lit_b = {} }}", .{v}),
    }
}

// Private references are bound file-locally to an unspellable internal key.
// They neither fuse with caller words nor leak through accumulated context.
fn localWord(a: std.mem.Allocator, m: Mod, name: []const u8) ![]const u8 {
    if (std.mem.eql(u8, name, "main")) return name;
    for (m.exports) |x| if (std.mem.eql(u8, x, name)) return name;
    for (m.defs) |d| if (std.mem.eql(u8, d.name, name))
        return std.fmt.allocPrint(a, "{s}#{s}", .{ m.name, name });
    return name;
}

fn emitModule(o: *Out, a: std.mem.Allocator, m: Mod, flats: []?FlatIR) !void {
    o.add("// GENERATED by jppc from {s} — do not edit.\n", .{m.name});
    o.add("const std = @import(\"std\");\n", .{});
    o.add("const jpp = @import(\"jpp.zig\");\n", .{});
    // dotted module paths: emitted files are FLAT with dotted names;
    // local aliases sanitize dots to underscores
    for (m.usings) |u| o.add("const m_{s} = @import(\"{s}.zig\");\n", .{ try aliasOf(a, u), u });
    o.add("\nconst this_module = @This();\n", .{});
    o.add("pub const STATIC = .{{ this_module", .{});
    for (m.usings) |u| o.add(", m_{s}", .{try aliasOf(a, u)});
    o.add(" }};\n", .{});
    o.add("pub const MODULE_NAME = \"{s}\";\n", .{m.name});
    o.add("pub const DECLARED = .{{", .{});
    for (m.defs) |d| o.add("\"{s}\",", .{d.name});
    o.add(" }};\npub const EXPORTED = .{{", .{});
    for (m.exports) |x| o.add("\"{s}\",", .{x});
    o.add(" }};\ncomptime {{ jpp.validateExports(DECLARED, EXPORTED); }}\n", .{});

    // ground structs (printed zig; Ret = declared or @TypeOf mirror)
    for (m.defs, 0..) |d, k| {
        const g = d.ground orelse continue;
        o.add("\nconst G{d} = struct {{\n", .{k});
        o.add("    pub fn Ret(comptime B: type) type {{\n", .{});
        if (d.ret) |r| {
            if (!boundTypeName(d, r)) o.add("        _ = B;\n", .{});
            o.add("        return ", .{});
            emitBoundType(o, d, r);
            o.add(";\n", .{});
        } else {
            if (groundUsesAny(d, g)) o.add("        const bound: B = undefined;\n", .{}) else o.add("        _ = B;\n", .{});
            emitGroundPrelude(o, d, g);
            o.add("        return @TypeOf({s});\n", .{g});
        }
        o.add("    }}\n", .{});
        o.add("    pub fn run(bound: anytype) Ret(@TypeOf(bound)) {{\n", .{});
        emitGroundPrelude(o, d, g);
        // declared-nothing grounds are STATEMENTS (blocks, ifs); the rest
        // are expressions returned
        const is_void = if (d.ret) |r| std.mem.eql(u8, r, "nothing") else false;
        if (is_void) {
            if (std.mem.endsWith(u8, g, "}")) o.add("        {s}\n", .{g}) else o.add("        {s};\n", .{g});
        } else {
            o.add("        return {s};\n", .{g});
        }
        o.add("    }}\n}};\n", .{});
    }

    // multimethods: group same-named defs, definition order preserved.
    // Exported keys fuse across modules. Private keys are lexical and cannot
    // be spelled by callers. Main is implicitly exported for the harness.
    var done = try a.alloc(bool, m.defs.len);
    @memset(done, false);
    for (m.defs, 0..) |d, di| {
        if (done[di]) continue;
        const emitted_name = try localWord(a, m, d.name);
        o.add("\npub const @\"{s}\" = jpp.MultiMethod(\"{s}\", &.{{\n", .{ emitted_name, emitted_name });
        for (m.defs, 0..) |e, ei| {
            if (!std.mem.eql(u8, e.name, d.name)) continue;
            done[ei] = true;
            o.add("    .{{ .declaration_home = this_module, .name = \"{s}\", .signature = &.{{", .{emitted_name});
            for (e.params, 0..) |prm, pi| {
                if (pi > 0) o.add(",", .{});
                o.add(" .{{ .name = \"{s}\", .qual = ", .{prm.name});
                if (prm.anonymous)
                    o.add("jpp.declarationQual(STATIC, null, ", .{})
                else
                    o.add("jpp.declarationQual(STATIC, \"{s}\", ", .{prm.name});
                if (prm.pred != null) {
                    o.add(".{{ .tvar = \"{s}\" }}", .{prm.name});
                } else if (prm.ty) |t| {
                    if (isTVar(e, t)) {
                        o.add(".{{ .tvar = \"{s}\" }}", .{t});
                    } else {
                        o.add(".{{ .exact = jpp.requireValue(STATIC, \"{s}\") }}", .{t});
                    }
                } else {
                    o.add(".bare", .{});
                }
                o.add(", {})", .{!prm.anonymous and paramUsed(e, prm.name)});
                o.add(" }}", .{});
            }
            o.add(" }},", .{});
            if (e.where_clause) |w| {
                o.add(" .variables = &.{{", .{});
                for (w.vars) |v| o.add("\"{s}\",", .{v});
                o.add(" }},", .{});
                if (w.eqs.len > 0) {
                    o.add(" .eqs = &.{{", .{});
                    for (w.eqs) |pair| o.add(" .{{ .a = \"{s}\", .b = \"{s}\" }},", .{ pair[0], pair[1] });
                    o.add(" }},", .{});
                }
            }
            // gates arrive from two spellings that mean the same thing:
            // the `where T <: P` clause and the slot form `x<:P`
            const wgates: []const [2][]const u8 = if (e.where_clause) |w| w.gates else &.{};
            var nslot: usize = 0;
            for (e.params) |prm| {
                if (prm.pred != null) nslot += 1;
            }
            if (wgates.len + nslot > 0) {
                o.add(" .gates = &.{{", .{});
                for (wgates) |g| o.add(" .{{ .tvar = \"{s}\", .word = \"{s}\" }},", .{ g[0], try localWord(a, m, g[1]) });
                for (e.params) |prm| {
                    if (prm.pred) |pw| o.add(" .{{ .tvar = \"{s}\", .word = \"{s}\" }},", .{ prm.name, try localWord(a, m, pw) });
                }
                o.add(" }},", .{});
            }
            if (e.ret) |r| {
                if (e.ground == null) {
                    if (boundTypeName(e, r)) o.add(" .ret_variable = \"{s}\",", .{r}) else o.add(" .ret = jpp.requireValue(STATIC, \"{s}\"),", .{r});
                }
            }
            if (e.ground != null) {
                o.add(" .body = .{{ .ground = G{d} }} }},\n", .{ei});
            } else {
                const flat = flats[ei].?;
                o.add("\n      .body = .{{ .ops = .{{ .ops = &.{{\n", .{});
                for (flat.ops) |op| {
                    o.add("        .{{ .callee = \"{s}\", .args = &.{{ ", .{try localWord(a, m, op.callee)});
                    for (op.args, 0..) |r, ri| {
                        if (ri > 0) o.add(", ", .{});
                        emitVR(o, r);
                    }
                    o.add(" }} }},\n", .{});
                }
                o.add("      }}, .result = ", .{});
                emitVR(o, flat.result);
                o.add(" }} }} }},\n", .{});
            }
        }
        o.add("}});\ncomptime {{ _ = @\"{s}\"; }}\n", .{emitted_name});
    }
}

/// Tokenize Zig grounds for input use; comments, strings and partial identifier
/// matches cannot hide an accidentally unused binder.
fn groundUses(g: [:0]const u8, name: []const u8) bool {
    var lexer = std.zig.Tokenizer.init(g);
    while (true) {
        const tok = lexer.next();
        if (tok.tag == .eof) return false;
        if (tok.tag == .identifier and std.mem.eql(u8, g[tok.loc.start..tok.loc.end], name)) return true;
    }
}

fn nodeUses(n: *Node, name: []const u8) bool {
    return switch (n.*) {
        .ident => |s| std.mem.eql(u8, s, name),
        .call => |c| blk: {
            for (c.args) |arg| if (nodeUses(arg, name)) break :blk true;
            break :blk false;
        },
        .block => |items| blk: {
            for (items) |item| if (nodeUses(item, name)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

fn paramUsed(d: Def, name: []const u8) bool {
    if (d.ret) |r| if (std.mem.eql(u8, r, name)) return true;
    if (d.where_clause) |w| {
        for (w.eqs) |e| if (std.mem.eql(u8, e[0], name) or std.mem.eql(u8, e[1], name)) return true;
        for (w.gates) |g| if (std.mem.eql(u8, g[0], name)) return true;
    }
    return if (d.ground) |g| groundUses(g, name) else nodeUses(d.body.?, name);
}

fn boundTypeName(d: Def, name: []const u8) bool {
    if (isTVar(d, name)) return true;
    for (d.params) |p| {
        if (std.mem.eql(u8, p.name, name) and p.ty != null and std.mem.eql(u8, p.ty.?, "type")) return true;
    }
    return false;
}

fn emitBoundType(o: *Out, d: Def, name: []const u8) void {
    for (d.params) |p| {
        if (p.ty) |t| {
            if (isTVar(d, name) and std.mem.eql(u8, t, name)) {
                o.add("@TypeOf(@field(@as(B, undefined), \"{s}\"))", .{p.name});
                return;
            }
            if (std.mem.eql(u8, p.name, name) and std.mem.eql(u8, t, "type")) {
                o.add("@field(@as(B, undefined), \"{s}\")", .{p.name});
                return;
            }
        }
    }
    o.add("jpp.requireValue(STATIC, \"{s}\")", .{name});
}

fn groundUsesAny(d: Def, g: [:0]const u8) bool {
    for (d.params) |p| if (!p.anonymous and groundUses(g, p.name)) return true;
    if (d.where_clause) |w| for (w.vars) |v| if (groundUses(g, v)) return true;
    return false;
}

fn emitGroundPrelude(o: *Out, d: Def, g: [:0]const u8) void {
    for (d.params, 0..) |p, i| {
        const repeated = for (d.params[0..i]) |prev| {
            if (std.mem.eql(u8, p.name, prev.name)) break true;
        } else false;
        if (repeated) continue;
        if (!p.anonymous and groundUses(g, p.name)) {
            o.add("        const {s} = @field(bound, \"{s}\");\n", .{ p.name, p.name });
        }
    }
    if (d.where_clause) |w| {
        for (w.vars) |v| {
            if (!groundUses(g, v)) continue;
            for (d.params) |p| {
                if (p.ty) |t| {
                    if (std.mem.eql(u8, t, v)) {
                        o.add("        const {s} = @TypeOf(@field(bound, \"{s}\"));\n", .{ v, p.name });
                        break;
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- driver
//
// usage: jppc [src_root] [out_dir]     (defaults: tests/dispatch gen)
//
// discovers *.jpp RECURSIVELY under src_root. a PROGRAM is a tree-root
// module that defines `main` (filename is free). the generated harness
// starts a FRESH context at each program — that is how two worlds
// share libraries without leaking `using` lists. `main` first, then
// alphabetical.

const Found = struct { name: []const u8, path: []const u8 };

fn lessThanName(_: void, x: Found, y: Found) bool {
    return std.mem.lessThan(u8, x.name, y.name);
}

fn moreDots(_: void, x: []const u8, y: []const u8) bool {
    return std.mem.count(u8, x, ".") > std.mem.count(u8, y, ".");
}

fn isProgram(f: Found, m: Mod) bool {
    // a program is a tree-root module that defines main(). Base/ joins
    // every tree but is never a program. nested modules (dots) are
    // libraries — putting main() there would also leak into a folder
    // aggregate's exported words.
    if (std.mem.startsWith(u8, f.path, "Base/")) return false;
    if (std.mem.indexOfScalar(u8, f.name, '.') != null) return false;
    for (m.defs) |d| {
        if (std.mem.eql(u8, d.name, "main")) return true;
    }
    return false;
}

/// dotted module path -> zig-safe local alias segment (dots to underscores)
fn aliasOf(a: std.mem.Allocator, dotted: []const u8) ![]const u8 {
    const out = try a.dupe(u8, dotted);
    std.mem.replaceScalar(u8, out, '.', '_');
    return out;
}

pub fn main(pinit: std.process.Init) !void {
    const a = pinit.arena.allocator();
    const io = pinit.io;
    const cwd = std.Io.Dir.cwd();

    var argit = std.process.Args.Iterator.init(pinit.minimal.args);
    _ = argit.next(); // argv0
    const src_root: []const u8 = argit.next() orelse "tests/dispatch";
    const out_dir: []const u8 = argit.next() orelse "gen";

    try cwd.createDirPath(io, out_dir);

    // the machinery rides along verbatim (incl. its inline-test fixture —
    // @import paths must resolve even though tests are never analyzed here)
    for ([_][]const u8{ "jpp.zig", "mixed_vis_fixture.zig" }) |mfile| {
        const data = try cwd.readFileAlloc(io, try std.fmt.allocPrint(a, "src/{s}", .{mfile}), a, .unlimited);
        try cwd.writeFile(io, .{
            .sub_path = try std.fmt.allocPrint(a, "{s}/{s}", .{ out_dir, mfile }),
            .data = data,
        });
    }

    // --- discover .jpp files recursively -------------------------------------
    var found: [256]Found = undefined;
    var nfound: usize = 0;
    {
        var root = try cwd.openDir(io, src_root, .{ .iterate = true });
        defer root.close(io);
        var walker = try root.walk(a);
        defer walker.deinit();
        while (try walker.next(io)) |e| {
            if (e.kind != .file) continue;
            if (!std.mem.endsWith(u8, e.basename, ".jpp")) continue;
            // module identity = DOTTED PATH from the tree root:
            // ground/ints.jpp -> "ground.ints" (`using ground.ints`).
            // TAKEOVER: <dir>/<dir>.jpp collapses to "<dir>" — that file
            // IS the folder's module and governs it.
            const rel = e.path[0 .. e.path.len - 4];
            var dotted = try a.dupe(u8, rel);
            std.mem.replaceScalar(u8, dotted, '/', '.');
            if (std.mem.lastIndexOfScalar(u8, dotted, '.')) |di| {
                const stem = dotted[di + 1 ..];
                const dir = dotted[0..di];
                const dirseg = if (std.mem.lastIndexOfScalar(u8, dir, '.')) |dj| dir[dj + 1 ..] else dir;
                if (std.mem.eql(u8, stem, dirseg)) dotted = try a.dupe(u8, dir);
            }
            for (found[0..nfound]) |f| {
                if (std.mem.eql(u8, f.name, dotted)) {
                    std.debug.print("jppc: module name collision '{s}' under {s}\n", .{ dotted, src_root });
                    return error.DuplicateModule;
                }
            }
            found[nfound] = .{
                .name = dotted,
                .path = try std.fmt.allocPrint(a, "{s}/{s}", .{ src_root, e.path }),
            };
            nfound += 1;
        }
    }
    // Base/ is the jpp library (not zig's std): modules join every tree
    // under their own names; the tree's own SHADOW them (entitlement).
    if (cwd.openDir(io, "Base", .{ .iterate = true })) |sdc| {
        var sd = sdc;
        defer sd.close(io);
        var walker2 = try sd.walk(a);
        defer walker2.deinit();
        while (try walker2.next(io)) |e| {
            if (e.kind != .file) continue;
            if (!std.mem.endsWith(u8, e.basename, ".jpp")) continue;
            const rel = e.path[0 .. e.path.len - 4];
            var dotted = try a.dupe(u8, rel);
            std.mem.replaceScalar(u8, dotted, '/', '.');
            if (std.mem.lastIndexOfScalar(u8, dotted, '.')) |di| {
                const stem = dotted[di + 1 ..];
                const dir = dotted[0..di];
                const dirseg = if (std.mem.lastIndexOfScalar(u8, dir, '.')) |dj| dir[dj + 1 ..] else dir;
                if (std.mem.eql(u8, stem, dirseg)) dotted = try a.dupe(u8, dir);
            }
            var shadowed = false;
            for (found[0..nfound]) |f| {
                if (std.mem.eql(u8, f.name, dotted)) shadowed = true;
            }
            if (shadowed) continue; // tree wins
            found[nfound] = .{
                .name = dotted,
                .path = try std.fmt.allocPrint(a, "Base/{s}", .{e.path}),
            };
            nfound += 1;
        }
    } else |_| {} // no Base/ — fine

    const mods = found[0..nfound];
    std.mem.sort(Found, mods, {}, lessThanName); // deterministic output

    const bigbuf = try a.alloc(u8, 1 << 20);
    const toks_pool = try a.alloc(Tok, 1 << 14);

    // parse everything first — aggregates need the children's exports
    var parsed: [256]Mod = undefined;
    for (mods, 0..) |f, mi| {
        const src = try cwd.readFileAlloc(io, f.path, a, .unlimited);
        const toks = lex(src, toks_pool) catch |e| {
            std.debug.print("jppc: lex error {any} in {s}\n", .{ e, f.path });
            return e;
        };
        var p = Parser{ .toks = toks, .a = a };
        parsed[mi] = p.parseModule(f.name) catch |e| {
            std.debug.print("jppc: parse error in {s}\n", .{f.path});
            return e;
        };
    }

    for (mods, 0..) |f, mi| {
        const mod = parsed[mi];
        const flats = try a.alloc(?FlatIR, mod.defs.len);
        for (mod.defs, 0..) |d, i| {
            flats[i] = if (d.ground == null) try flatten(a, d) else null;
        }
        var out = Out{ .buf = bigbuf };
        try emitModule(&out, a, mod, flats);
        const out_path = try std.fmt.allocPrint(a, "{s}/{s}.zig", .{ out_dir, f.name });
        try cwd.writeFile(io, .{ .sub_path = out_path, .data = out.text() });
        std.debug.print("jppc: {s} -> {s} ({d} defs, {d} bytes)\n", .{ f.path, out_path, mod.defs.len, out.len });
    }

    // FOLDERS ARE MODULES: for every directory without a takeover file,
    // synthesize the aggregate — its words are the union of its direct
    // children's exports, methods merged in child order. deepest first,
    // so a synthesized aggregate can be a child of its parent's aggregate.
    var all_names: [512][]const u8 = undefined; // files + aggregates
    var all_exports: [512][]const []const u8 = undefined;
    var nall: usize = 0;
    for (mods, 0..) |f, mi| {
        all_names[nall] = f.name;
        all_exports[nall] = parsed[mi].exports;
        nall += 1;
    }
    var dirs: [64][]const u8 = undefined;
    var ndirs: usize = 0;
    for (mods) |f| {
        var name = f.name;
        while (std.mem.lastIndexOfScalar(u8, name, '.')) |di| {
            const dir = name[0..di];
            var known = false;
            for (dirs[0..ndirs]) |d| {
                if (std.mem.eql(u8, d, dir)) known = true;
            }
            for (mods) |g| {
                if (std.mem.eql(u8, g.name, dir)) known = true; // takeover
            }
            if (!known) {
                dirs[ndirs] = dir;
                ndirs += 1;
            }
            name = dir;
        }
    }
    // deepest (most dots) first
    std.mem.sort([]const u8, dirs[0..ndirs], {}, moreDots);
    for (dirs[0..ndirs]) |dir| {
        var out = Out{ .buf = bigbuf };
        out.add("// GENERATED aggregate — the folder '{s}' as a module.\n", .{dir});
        out.add("const jpp = @import(\"jpp.zig\");\n", .{});
        // direct children: name == dir ++ "." ++ seg (seg without dots)
        var child_idx: [64]usize = undefined;
        var nchild: usize = 0;
        for (all_names[0..nall], 0..) |n, i| {
            if (!std.mem.startsWith(u8, n, dir)) continue;
            if (n.len <= dir.len or n[dir.len] != '.') continue;
            const rest = n[dir.len + 1 ..];
            if (std.mem.indexOfScalar(u8, rest, '.') != null) continue;
            child_idx[nchild] = i;
            nchild += 1;
        }
        for (child_idx[0..nchild]) |i|
            out.add("const m_{s} = @import(\"{s}.zig\");\n", .{ try aliasOf(a, all_names[i]), all_names[i] });
        out.add("\nconst this_module = @This();\n", .{});
        out.add("pub const STATIC = ", .{});
        for (child_idx[0..nchild]) |_| out.add("jpp.extendAll(", .{});
        out.add(".{{this_module}}", .{});
        for (child_idx[0..nchild]) |i|
            out.add(", m_{s}.STATIC)", .{try aliasOf(a, all_names[i])});
        out.add(";\n", .{});
        // words: union of children's exports (arena-owned — the aggregate
        // itself becomes a child of its parent's aggregate)
        var words = try std.ArrayList([]const u8).initCapacity(a, 32);
        for (child_idx[0..nchild]) |i| {
            for (all_exports[i]) |w| {
                var dup = false;
                for (words.items) |x| {
                    if (std.mem.eql(u8, x, w)) dup = true;
                }
                if (!dup) try words.append(a, w);
            }
        }
        out.add("pub const MODULE_NAME = \"{s}\";\n", .{dir});
        out.add("pub const EXPORTED = .{{", .{});
        for (words.items) |w| out.add("\"{s}\",", .{w});
        out.add(" }};\npub const DECLARED = EXPORTED;\n", .{});
        for (words.items) |w| {
            out.add("\npub const @\"{s}\" = jpp.MergedWord(\"{s}\", .{{", .{ w, w });
            for (child_idx[0..nchild], 0..) |i, k| {
                if (k > 0) out.add(",", .{});
                out.add(" m_{s}", .{try aliasOf(a, all_names[i])});
            }
            out.add(" }});\n", .{});
        }
        const agg_path = try std.fmt.allocPrint(a, "{s}/{s}.zig", .{ out_dir, dir });
        try cwd.writeFile(io, .{ .sub_path = agg_path, .data = out.text() });
        std.debug.print("jppc: aggregate {s} ({d} children, {d} words)\n", .{ agg_path, nchild, words.items.len });
        // the aggregate is itself a module — a child of ITS parent
        all_names[nall] = dir;
        all_exports[nall] = words.items;
        nall += 1;
    }

    // --- run.zig: THE artifact, self-judging ----------------------------------
    // each PROGRAM starts a fresh context at its own STATIC. checks
    // (Base/Test.jpp) record failures; the harness snapshots the counter
    // around each program so a contrast case names WHICH world failed.
    // `[case] PASS|FAIL` (plus per-program lines when there are several),
    // exit 0/1 (unix). no separate judge, no output oracle.
    var programs: [64][]const u8 = undefined;
    var nprog: usize = 0;
    for (mods, 0..) |f, mi| { // `main` first if present
        if (isProgram(f, parsed[mi]) and std.mem.eql(u8, f.name, "main")) {
            programs[nprog] = f.name;
            nprog += 1;
        }
    }
    for (mods, 0..) |f, mi| { // the rest, alphabetical (mods are sorted)
        if (isProgram(f, parsed[mi]) and !std.mem.eql(u8, f.name, "main")) {
            programs[nprog] = f.name;
            nprog += 1;
        }
    }
    if (nprog == 0) {
        std.debug.print("jppc: no program in {s} — a root module must define main()\n", .{src_root});
        return error.NoProgram;
    }
    std.debug.print("jppc: {d} program(s)", .{nprog});
    for (programs[0..nprog]) |p| std.debug.print(" {s}", .{p});
    std.debug.print("\n", .{});

    var out = Out{ .buf = bigbuf };
    out.add("// GENERATED — self-judging: each program is a fresh root context.\n", .{});
    out.add("const std = @import(\"std\");\n", .{});
    out.add("const jpp = @import(\"jpp.zig\");\n", .{});
    for (programs[0..nprog]) |p|
        out.add("const m_{s} = @import(\"{s}.zig\");\n", .{ p, p });
    const label = caseName(src_root);
    out.add("pub fn main() u8 {{\n", .{});
    if (nprog > 1) out.add("    var programs_failed: usize = 0;\n", .{});
    for (programs[0..nprog]) |p| {
        if (nprog == 1) {
            out.add("    _ = jpp.call(m_{s}.STATIC, \"main\", .{{}});\n", .{p});
            continue;
        }
        out.add("    {{\n", .{});
        out.add("        const before = jpp.test_failures;\n", .{});
        out.add("        _ = jpp.call(m_{s}.STATIC, \"main\", .{{}});\n", .{p});
        out.add("        const n = jpp.test_failures - before;\n", .{});
        out.add("        if (n == 0) {{\n", .{});
        out.add("            std.debug.print(\"[{s}/{s}] PASS\\n\", .{{}});\n", .{ label, p });
        out.add("        }} else {{\n", .{});
        out.add("            std.debug.print(\"[{s}/{s}] FAIL — {{d}} check(s) failed\\n\", .{{n}});\n", .{ label, p });
        out.add("            programs_failed += 1;\n", .{});
        out.add("        }}\n", .{});
        out.add("    }}\n", .{});
    }
    out.add("    if (jpp.test_failures == 0) {{\n", .{});
    if (nprog == 1) {
        out.add("        std.debug.print(\"[{s}] PASS\\n\", .{{}});\n", .{label});
    } else {
        out.add("        std.debug.print(\"[{s}] PASS — {d} programs\\n\", .{{}});\n", .{ label, nprog });
    }
    out.add("        return 0;\n    }}\n", .{});
    if (nprog == 1) {
        out.add("    std.debug.print(\"[{s}] FAIL — {{d}} check(s) failed\\n\", .{{jpp.test_failures}});\n", .{label});
    } else {
        out.add("    std.debug.print(\"[{s}] FAIL — {{d}} check(s) failed in {{d}} program(s)\\n\", .{{jpp.test_failures, programs_failed}});\n", .{label});
    }
    out.add("    return 1;\n}}\n", .{});
    const run_path = try std.fmt.allocPrint(a, "{s}/run.zig", .{out_dir});
    try cwd.writeFile(io, .{ .sub_path = run_path, .data = out.text() });
    std.debug.print("jppc: wrote {s}\n", .{run_path});
}

fn caseName(src_root: []const u8) []const u8 {
    const trimmed = std.mem.trimEnd(u8, src_root, "/");
    if (std.mem.lastIndexOfScalar(u8, trimmed, '/')) |i| return trimmed[i + 1 ..];
    return trimmed;
}
