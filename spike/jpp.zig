// Historical encoding retained for tailcalls.zig only. The active runtime is
// src/jpp.zig; this probe helper's summed ranks are not current jpp semantics.
// Original encoding:
//   call(ctx, "f", args) = resolve(ctx, "f", typeof(args)).call(ctx, args)
//
// encoding conventions (what the transpiler emits):
//   * jpp module      -> zig struct (a file), jpp surface names as @"..." decls
//   * jpp method      -> jpp.Method(struct{ rank, matches, Ret, call })
//   * jpp method NAME -> jpp.MultiMethod("name", .{ methods... }) decl
//   * jpp context     -> comptime tuple of module structs
//   * call/resolve/rank/matches/Ret (unquoted) are reserved machinery names

const std = @import("std");

// --- Method & MultiMethod: the two emitted constructs -------------------------

/// ONE definition. Impl must provide (validated by construction — a missing
/// decl errors at the wrap site, not inside resolve):
///   pub const rank: comptime_int        — specificity: sum of slot ranks
///                                         (exact=3, predicate=2, bare=1, variadic=0)
///   pub fn matches(Args) bool           — the pack pattern
///   pub fn Ret(ctx, Args) type          — return type; takes ctx because an
///                                         inferred return resolves in context
///   pub fn call(ctx, args) Ret(...)     — the body
pub fn Method(comptime Impl: type) type {
    return struct {
        pub const is_jpp_method = true;
        pub const rank: comptime_int = Impl.rank;
        pub const matches = Impl.matches;
        pub const Ret = Impl.Ret;
        pub const call = Impl.call;
    };
}

/// the named, ORDERED collection of methods for one surface name in one
/// module. this is what a `pub const @"f" = ...` decl holds. it owns LOCAL
/// resolution; global resolve just asks each module's multimethod for its
/// best candidate.
pub fn MultiMethod(comptime name: []const u8, comptime method_tuple: anytype) type {
    return struct {
        pub const is_jpp_multimethod = true;
        pub const method_name = name;
        pub const methods = method_tuple;

        /// best match for Args within this multimethod, or null.
        /// rank decides; on ties the EARLIER definition wins.
        pub fn find(comptime Args: []const type) ?type {
            comptime {
                var Best: type = undefined;
                var best_rank: i64 = -1;
                for (0..methods.len) |j| {
                    const M = methods[j];
                    if (!M.matches(Args)) continue;
                    if (M.rank > best_rank) {
                        Best = M;
                        best_rank = M.rank;
                    }
                }
                return if (best_rank >= 0) Best else null;
            }
        }
    };
}

/// tuple type -> slice of its field types (comptime)
pub fn argTypes(comptime ArgsT: type) []const type {
    const fields = @typeInfo(ArgsT).@"struct".fields;
    comptime var out: [fields.len]type = undefined;
    inline for (fields, 0..) |f, i| out[i] = f.type;
    const frozen = out;
    return &frozen;
}

/// the single magical external: walk the context's method sets for `name`,
/// keep the most specific match. specificity = method's declared rank
/// (exact=3 per arg, predicate=2, bare=1, variadic=0 — summed by the
/// transpiler when it emits the method).
///
/// ordering rule (ratified): rank first; on rank TIES, position in the
/// context wins — earlier module beats later. the context is ordered
/// [caller's chain..., callee's static imports...], so newer code can
/// override old behavior, and the override is local to contexts that
/// include it. within-module same-rank ambiguity is a transpiler-time
/// error (not checked here).
pub fn resolve(comptime ctx: anytype, comptime name: []const u8, comptime Args: []const type) type {
    comptime {
        var Best: type = undefined;
        var best_rank: i64 = -1;

        for (0..ctx.len) |i| {
            const mod = ctx[i];
            if (!@hasDecl(mod, name)) continue;
            const MM = @field(mod, name);
            // the marker lets a module export a plain decl that merely
            // shares a method's name without confusing the resolver
            if (@TypeOf(MM) != type or !@hasDecl(MM, "is_jpp_multimethod")) continue;
            const M = MM.find(Args) orelse continue;
            if (M.rank > best_rank) { // strictly greater: ties keep the earlier
                Best = M;
                best_rank = M.rank;
            }
        }

        if (best_rank < 0) @compileError("jpp: no method '" ++ name ++ "' in context for " ++ typeList(Args));
        return Best;
    }
}

// --- context building --------------------------------------------------------
// entering a resolved method, the effective context is
//   caller_ctx ++ callee's static context   (deduped, caller stays ahead)
// emitted bodies call: jpp.call(jpp.extendAll(ctx, STATIC), "f", args)

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

/// every jpp surface call f(args...) lowers to this.
pub fn call(comptime ctx: anytype, comptime name: []const u8, args: anytype) RetOf(ctx, name, @TypeOf(args)) {
    const M = comptime resolve(ctx, name, argTypes(@TypeOf(args)));
    return M.call(ctx, args);
}

/// return type of the resolved method. Ret takes ctx: an inferred return
/// type mirrors the body's calls, which resolve in context.
pub fn RetOfT(comptime ctx: anytype, comptime name: []const u8, comptime Args: []const type) type {
    return resolve(ctx, name, Args).Ret(ctx, Args);
}

fn RetOf(comptime ctx: anytype, comptime name: []const u8, comptime ArgsT: type) type {
    return RetOfT(ctx, name, argTypes(ArgsT));
}

fn typeList(comptime Args: []const type) []const u8 {
    comptime {
        var msg: []const u8 = "(";
        for (Args, 0..) |T, k| {
            if (k > 0) msg = msg ++ ", ";
            msg = msg ++ @typeName(T);
        }
        return msg ++ ")";
    }
}
