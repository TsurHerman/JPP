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
//   expr: literals, idents, calls, infix + - * (precedence), { blocks },
//         zig{ raw ground }
//   params: x (bare) | x::typename (exact)
//   literals default int64 / float64 (julia-ish)

const std = @import("std");

// ---------------------------------------------------------------- tokens

const TokKind = enum { ident, int, float, lparen, rparen, lbrace, rbrace, comma, dcolon, eq, semi, nl, ground, kw_using, kw_export, op, eof };

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
        const start = i;
        switch (c) {
            '(' => toks[n] = .{ .kind = .lparen, .text = "(", .pos = start },
            ')' => toks[n] = .{ .kind = .rparen, .text = ")", .pos = start },
            '{' => toks[n] = .{ .kind = .lbrace, .text = "{", .pos = start },
            '}' => toks[n] = .{ .kind = .rbrace, .text = "}", .pos = start },
            ',' => toks[n] = .{ .kind = .comma, .text = ",", .pos = start },
            ';' => toks[n] = .{ .kind = .semi, .text = ";", .pos = start },
            '=' => toks[n] = .{ .kind = .eq, .text = "=", .pos = start },
            '+', '-', '*', '/' => toks[n] = .{ .kind = .op, .text = src[i .. i + 1], .pos = start },
            ':' => {
                if (i + 1 < src.len and src[i + 1] == ':') {
                    toks[n] = .{ .kind = .dcolon, .text = "::", .pos = start };
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
    ident: []const u8,
    call: struct { callee: []const u8, args: []*Node },
    block: []*Node,
};

const Param = struct { name: []const u8, ty: ?[]const u8 };

const Def = struct {
    name: []const u8,
    params: []Param,
    ret: ?[]const u8,
    body: ?*Node, // null when ground
    ground: ?[]const u8,
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
                    const t = try p.expect(.ident);
                    try usings.append(p.a, t.text);
                },
                .kw_export => {
                    _ = p.next();
                    while (true) {
                        const t = p.next();
                        if (t.kind != .ident and t.kind != .op) return error.Parse;
                        try exports.append(p.a, t.text);
                        if (p.peek().kind == .comma) {
                            _ = p.next();
                            continue;
                        }
                        break;
                    }
                },
                .ident, .op => try defs.append(p.a, try p.parseDef()),
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
                const pn = try p.expect(.ident);
                var ty: ?[]const u8 = null;
                if (p.peek().kind == .dcolon) {
                    _ = p.next();
                    ty = (try p.expect(.ident)).text;
                }
                try params.append(p.a, .{ .name = pn.text, .ty = ty });
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
        _ = try p.expect(.eq);
        p.skipNlOnlyNewlinesBeforeBody();
        if (p.peek().kind == .ground) {
            const g = p.next().text;
            return .{ .name = name, .params = params.items, .ret = ret, .body = null, .ground = g };
        }
        const body = try p.parseExpr(0);
        return .{ .name = name, .params = params.items, .ret = ret, .body = body, .ground = null };
    }

    fn skipNlOnlyNewlinesBeforeBody(p: *Parser) void {
        while (p.peek().kind == .nl) _ = p.next();
    }

    fn opPrec(text: []const u8) ?u8 {
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
            .ident => {
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

// ---------------------------------------------------------------- normalizer (ANF)

const VR = union(enum) { param: usize, local: usize, lit_i: i64, lit_f: f64 };
const OpIR = struct { callee: []const u8, args: []VR };
const FlatIR = struct { ops: []OpIR, result: VR };

fn flatten(a: std.mem.Allocator, def: Def) !FlatIR {
    var ops = try std.ArrayList(OpIR).initCapacity(a, 32);
    const result = try flattenNode(a, def.body.?, def.params, &ops);
    return .{ .ops = ops.items, .result = result };
}

fn flattenNode(a: std.mem.Allocator, n: *Node, params: []Param, ops: *std.ArrayList(OpIR)) anyerror!VR {
    switch (n.*) {
        .lit_i => |v| return .{ .lit_i = v },
        .lit_f => |v| return .{ .lit_f = v },
        .ident => |name| {
            for (params, 0..) |p, i| {
                if (std.mem.eql(u8, p.name, name)) return .{ .param = i };
            }
            std.debug.print("jppc: unknown name '{s}' (v1: only params may appear in bodies)\n", .{name});
            return error.Normalize;
        },
        .call => |c| {
            const args = try a.alloc(VR, c.args.len);
            for (c.args, 0..) |arg, i| args[i] = try flattenNode(a, arg, params, ops);
            try ops.append(a, .{ .callee = c.callee, .args = args });
            return .{ .local = ops.items.len - 1 };
        },
        .block => |items| {
            var last: ?VR = null;
            for (items) |item| last = try flattenNode(a, item, params, ops);
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

fn zigType(name: []const u8) []const u8 {
    const map = .{
        .{ "int64", "i64" },   .{ "int32", "i32" },   .{ "int16", "i16" }, .{ "int8", "i8" },
        .{ "uint64", "u64" },  .{ "uint32", "u32" },  .{ "uint16", "u16" }, .{ "uint8", "u8" },
        .{ "float64", "f64" }, .{ "float32", "f32" }, .{ "bool", "bool" }, .{ "nothing", "void" },
        .{ "string", "[]const u8" },
    };
    inline for (map) |e| {
        if (std.mem.eql(u8, name, e[0])) return e[1];
    }
    return name; // pass through — lets grounds use zig types directly
}

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
        .param => |p| o.add(".{{ .param = {d} }}", .{p}),
        .local => |l| o.add(".{{ .local = {d} }}", .{l}),
        .lit_i => |v| o.add(".{{ .lit_i = {d} }}", .{v}),
        .lit_f => |v| {
            o.add(".{{ .lit_f = ", .{});
            emitFloat(o, v);
            o.add(" }}", .{});
        },
    }
}

fn emitModule(o: *Out, a: std.mem.Allocator, m: Mod, flats: []?FlatIR) !void {
    o.add("// GENERATED by jppc from {s}.jpp — do not edit.\n", .{m.name});
    o.add("const std = @import(\"std\");\n", .{});
    o.add("const jpp = @import(\"jpp.zig\");\n", .{});
    for (m.usings) |u| o.add("const m_{s} = @import(\"{s}.zig\");\n", .{ u, u });
    o.add("\nconst this_module = @This();\n", .{});
    o.add("pub const STATIC = .{{ this_module", .{});
    for (m.usings) |u| o.add(", m_{s}", .{u});
    o.add(" }};\n", .{});

    // ground structs (printed zig; Ret = declared or @TypeOf mirror)
    for (m.defs, 0..) |d, k| {
        const g = d.ground orelse continue;
        o.add("\nconst G{d} = struct {{\n", .{k});
        o.add("    pub fn Ret(comptime B: type) type {{\n", .{});
        if (d.ret) |r| {
            o.add("        _ = B;\n        return {s};\n", .{zigType(r)});
        } else {
            o.add("        const bound: B = undefined;\n", .{});
            emitGroundPrelude(o, d, g);
            o.add("        return @TypeOf({s});\n", .{g});
        }
        o.add("    }}\n", .{});
        o.add("    pub fn run(bound: anytype) Ret(@TypeOf(bound)) {{\n", .{});
        emitGroundPrelude(o, d, g);
        o.add("        return {s};\n", .{g});
        o.add("    }}\n}};\n", .{});
    }

    // multimethods: group same-named defs, definition order preserved
    var done = try a.alloc(bool, m.defs.len);
    @memset(done, false);
    for (m.defs, 0..) |d, di| {
        if (done[di]) continue;
        o.add("\npub const @\"{s}\" = jpp.MultiMethod(\"{s}\", &.{{\n", .{ d.name, d.name });
        for (m.defs, 0..) |e, ei| {
            if (!std.mem.eql(u8, e.name, d.name)) continue;
            done[ei] = true;
            o.add("    .{{ .name = \"{s}\", .signature = &.{{", .{e.name});
            for (e.params, 0..) |prm, pi| {
                if (pi > 0) o.add(",", .{});
                o.add(" .{{ .name = \"{s}\", .qual = ", .{prm.name});
                if (prm.ty) |t| {
                    o.add(".{{ .exact = {s} }}", .{zigType(t)});
                } else {
                    o.add(".bare", .{});
                }
                o.add(" }}", .{});
            }
            o.add(" }},", .{});
            if (e.ret) |r| {
                if (e.ground == null) o.add(" .ret = {s},", .{zigType(r)});
            }
            if (e.ground != null) {
                o.add(" .body = .{{ .ground = G{d} }} }},\n", .{ei});
            } else {
                const flat = flats[ei].?;
                o.add("\n      .body = .{{ .ops = .{{ .ops = &.{{\n", .{});
                for (flat.ops) |op| {
                    o.add("        .{{ .callee = \"{s}\", .args = &.{{ ", .{op.callee});
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
        o.add("}});\n", .{});
    }
}

/// bring the slots a ground mentions into scope (heuristic: substring)
fn emitGroundPrelude(o: *Out, d: Def, g: []const u8) void {
    for (d.params) |p| {
        if (std.mem.indexOf(u8, g, p.name) != null)
            o.add("        const {s} = @field(bound, \"{s}\");\n", .{ p.name, p.name });
    }
}

// ---------------------------------------------------------------- driver

const modules = [_][]const u8{ "ints", "floats", "io", "algebra", "loud", "stats", "tweaked", "main", "loud_main", "tweaked_main" };

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const a = arena.allocator();
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, "gen");

    // the machinery rides along verbatim
    const machinery = try cwd.readFileAlloc(io, "src/jpp.zig", a, .unlimited);
    try cwd.writeFile(io, .{ .sub_path = "gen/jpp.zig", .data = machinery });

    const bigbuf = try a.alloc(u8, 1 << 20);
    const toks_pool = try a.alloc(Tok, 1 << 14);

    for (modules) |name| {
        const src_path = try std.fmt.allocPrint(a, "demo/{s}.jpp", .{name});
        const src = try cwd.readFileAlloc(io, src_path, a, .unlimited);
        const toks = lex(src, toks_pool) catch |e| {
            std.debug.print("jppc: lex error {any} in {s}\n", .{ e, src_path });
            return e;
        };
        var p = Parser{ .toks = toks, .a = a };
        const mod = p.parseModule(name) catch |e| {
            std.debug.print("jppc: parse error in {s}\n", .{src_path});
            return e;
        };
        const flats = try a.alloc(?FlatIR, mod.defs.len);
        for (mod.defs, 0..) |d, i| {
            flats[i] = if (d.ground == null) try flatten(a, d) else null;
        }
        var out = Out{ .buf = bigbuf };
        try emitModule(&out, a, mod, flats);
        const out_path = try std.fmt.allocPrint(a, "gen/{s}.zig", .{name});
        try cwd.writeFile(io, .{ .sub_path = out_path, .data = out.text() });
        std.debug.print("jppc: {s} -> {s} ({d} defs, {d} bytes)\n", .{ src_path, out_path, mod.defs.len, out.len });
    }

    // the harness: two entry contexts, same words, different laws
    var out = Out{ .buf = bigbuf };
    out.add(
        \\// GENERATED harness — runs main() from two contexts.
        \\const std = @import("std");
        \\const jpp = @import("jpp.zig");
        \\const main_mod = @import("main.zig");
        \\const loud_main = @import("loud_main.zig");
        \\const tweaked_main = @import("tweaked_main.zig");
        \\pub fn main() void {{
        \\    std.debug.print("== main.jpp ==\n", .{{}});
        \\    _ = jpp.call(main_mod.STATIC, "main", .{{}});
        \\    std.debug.print("== loud_main.jpp (using loud FIRST) ==\n", .{{}});
        \\    _ = jpp.call(loud_main.STATIC, "main", .{{}});
        \\    std.debug.print("== tweaked_main.jpp (grandparent overrides `+`) ==\n", .{{}});
        \\    _ = jpp.call(tweaked_main.STATIC, "main", .{{}});
        \\}}
        \\
    , .{});
    try cwd.writeFile(io, .{ .sub_path = "gen/run.zig", .data = out.text() });
    std.debug.print("jppc: wrote gen/run.zig — `zig run gen/run.zig`\n", .{});
}
