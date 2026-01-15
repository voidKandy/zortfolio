## Zemplate Type Graph Refactor

In my last post I went over how I've refactored `zemplate`'s parser to construct an AST rather than render directly from a token stream. This week I'm going to give an overview of how type introspection now works post-refactor. The old approach worked, but it had some serious problems—particularly with how it handled nested structs, which caused the type representations to balloon quickly. This new solution is much more elegant and scales way better.

### How is introspection used?

One of the arguments in `Template.init` is an `anytype` value, which is then used when rendering a template. For example, if I have a struct:

```zig
const MyStruct = struct {
  string: []const u8,
  number: u32
}
```

I should be able to access the fields `string` and `number` from within the template via those field names. If I pass a value of this type to Template, like:

```zig
Template.init(
  allocator,
  &MyStruct{
    .string = "World",
    .number = 42,
  },
);
```

Then I might have a template text:

```
Hello {|.string|}!
The meaning of life is {|.number|}
```

And I would expect the output:

```
Hello World!
The meaning of life is 42
```

But how am I actually accessing these field values at runtime? That's what I'm going to cover in this post.

### The old approach

I have a [previous post](https://www.voidkandy.space/Blog?post=zemplate-gets-control-flow) where I discuss the way I used to do type introspection. I'm not going to rehash all the details here—partly because I've already covered it, but also because the implementation was complex enough that I've honestly forgotten some of the finer details.

The big problem with that solution was that it required constructing a type to encapsulate all the possible types that might be returned from accessing a struct. This would very quickly balloon, especially when dealing with nested structs. The new solution avoids this entirely.

### Scoping vs. Accessing

The first thing I had to figure out was what accessing a field actually *does* in different contexts. I found there are really only two use cases: **entering a new scope** or **accessing and writing** the field.

Entering a scope happens when an if or for block is entered, for example:

```
||zz for .string zz||
||zz endfor zz||
```

Accessing is what you saw in the first example—the contents of a field actually need to be rendered to the result of the template.

Since I managed to boil my needs down to these two things, I can encapsulate each in a function signature.

`GetInnerScope` functions take some `Scope` and return another `Scope`:

```zig
const GetInnerScopeFunc = *const fn (
    Allocator,
    Scope,
) error{OutOfMemory}!Scope;
```

`WriteAccessFunc` takes some scope, a writer, and some options associated with writing that type, then writes to the writer, returning `void` on success or some `Error` otherwise:

```zig
const WriteAccessFunc = *const fn (
    *std.Io.Writer,
    Scope,
    std.json.Stringify.Options,
    bool,
) (util.WriteError || error{NotPresent})!void;
```

### What is a `Scope`?

Before moving forward, I should clarify what exactly a `Scope` struct is. This struct is the cornerstone of the refactor. Here are the relevant fields and init signature (I've omitted some implementation details):

```zig
const Scope = struct {
  instance: *const anyopaque,
  access_map: std.StaticStringMap(WriteAccessFunc),
  child_scopes: std.StaticStringMap(GetInnerScopeFunc),
  iterateFunc: error{NotIterable}!*const fn (@This()) Iterator,

  pub fn init(val: anytype, a: Allocator) error{OutOfMemory}!@This() {}
};
```

Here's what each field does:

+ **instance** - An opaque pointer to whatever type the `Scope` was initialized with.
+ **access_map** - A map of functions for writing each field and subfield of the type `Scope` was initialized with. This is constructed at comptime and passed to `Scope` upon initialization.
+ **child_scopes** - A map of functions for entering a scope for each field and subfield of the type `Scope` was initialized with. Also constructed at comptime.
+ **iterateFunc** - A function that returns an `Iterator` object. Some scopes aren't iterable (for example, a `Scope` with root type `u32`), which is why this field is an error union.

### How are the maps constructed?

The entries of both `access_map` and `child_scopes` are computed at comptime. The maps are constructed from these pre-computed entries when a `Scope` object is created. The way this works is pretty sweet.

The basic problem is that a `Scope` can be created for virtually any type. So, a function chain needs to be constructed for accessing child scopes and instances for writing. Below are the two functions that create the entries for each map:

```zig
inline fn childScopesKvs(
    comptime Root: type,
    comptime T: type,
    comptime basename: []const u8,
) [childScopesKvsCount(Root, T)]struct { []const u8, GetInnerScopeFunc } {
    util.compileLogPrint("GETTING KVS FOR {s} with {s}", .{ @typeName(T), basename });

    const OUT_SIZE = childScopesKvsCount(Root, T);
    const arr: [OUT_SIZE]struct { []const u8, GetInnerScopeFunc } = comptime blk: {
        var tmp: [OUT_SIZE]struct { []const u8, GetInnerScopeFunc } = undefined;
        if (OUT_SIZE == 0) break :blk tmp;
        if (basename.len > 1) {
            tmp[0] = .{
                basename,
                flattenScopeWalkerFunctionChain(
                    &buildScopeWalkerFunctionChain(Root, basename),
                ),
            };
        }

        const info = @typeInfo(T);
        switch (info) {
            .pointer, .array => break :blk tmp,
            else => {},
        }

        var i: usize = if (basename.len > 1) 1 else 0;
        for (info.@"struct".fields) |f| {
            util.compileLogPrint("FIELD: {s}", .{f.name});

            const expected_size = childScopesKvsCount(Root, f.type);
            if (expected_size == 0) {
                util.compileLogPrint("SIZE == 0", .{});
                continue;
            }

            const nested_basename = if (basename.len == 1)
                comptimePrint("{s}{s}", .{ basename, f.name })
            else
                comptimePrint("{s}.{s}", .{ basename, f.name });

            const nested = childScopesKvs(Root, f.type, nested_basename);
            for (nested) |kv| {
                tmp[i] = kv;
                i += 1;
            }
        }

        if (i != OUT_SIZE) @compileError(comptimePrint(
            \\ entry count of of {s} does not match expected
            \\ i != {d}
        , .{ @typeName(T), OUT_SIZE }));

        break :blk tmp;
    };
    return arr;
}

inline fn accessMapKvs(
  comptime Root: type,
  comptime T: type,
  comptime basename: []const u8,
) [accessMapKvsCount(T)]struct { []const u8, WriteAccessFunc } {
    const accessBase: WriteAccessFunc = &struct {
        fn call(
            w: *std.Io.Writer,
            s: Scope,
            json_opts: std.json.Stringify.Options,
            print_json: bool,
        ) (util.WriteError || error{NotPresent})!void {
            if (basename.len == 1) {
                const val: *const Root = @ptrCast(@alignCast(s.instance));
                return try util.writeType(T, val.*, w, json_opts, print_json);
            }

            const inst = try flattenAccessWalkerFunctionChain(
                &buildAccessWalkerFunctionChain(Root, basename),
            )(s.instance);

            const val: *const T = @ptrCast(@alignCast(inst));
            try util.writeType(T, val.*, w, json_opts, print_json);
        }
    }.call;

    switch (@typeInfo(T)) {
        .@"struct" => {
            const FIELDS = @typeInfo(T).@"struct".fields;

            const OUT_SIZE = accessMapKvsCount(T);

            const arr: [OUT_SIZE]struct { []const u8, WriteAccessFunc } = blk: {
                var tmp: [OUT_SIZE]struct { []const u8, WriteAccessFunc } = undefined;
                tmp[0] = .{
                    basename,
                    accessBase,
                };
                var i: usize = 1;
                inline for (FIELDS) |f| {
                    const name = if (basename.len == 1)
                        comptimePrint("{s}{s}", .{ basename, f.name })
                    else
                        comptimePrint("{s}.{s}", .{ basename, f.name });

                    const entries = accessMapKvs(Root, f.type, name);
                    inline for (entries) |kv| {
                        tmp[i] = kv;
                        i += 1;
                    }
                } 
                break :blk tmp;
            };

            return arr;
        },
        else => return [1]struct { []const u8, WriteAccessFunc }{.{ basename, accessBase }},
    }
}
```

Both of these functions recurse through the type graph to create a list of accessors for each field in the struct. They both use a function chain and flattener. Here are the functions that `childScopeKvs` uses:

```zig
inline fn buildScopeChainItem(
    comptime T: type,
    comptime fieldname: []const u8,
) GetInnerScopeFunc {
    return &struct {
        fn call(a: Allocator, s: Scope) error{OutOfMemory}!Scope {
            const inst: *const T = @ptrCast(@alignCast(s.instance));
            const field = @field(inst, fieldname);

            const scope = try Scope.init(&field, a);
            return scope;
        }
    }.call;
}

inline fn buildScopeWalkerFunctionChain(
    comptime Root: type,
    comptime basename: []const u8,
) [util.countPeriods(basename)]GetInnerScopeFunc {
    const fields = comptime basenameToFields(basename);
    comptime var funcs: [util.countPeriods(basename)]GetInnerScopeFunc = undefined;

    comptime var Ty: type = Root;
    inline for (fields, 0..) |name, i| {
        funcs[i] = buildScopeChainItem(Ty, name);
        Ty = @FieldType(Ty, name);
    }
    return funcs;
}

inline fn flattenScopeWalkerFunctionChain(
    comptime funcs: []const GetInnerScopeFunc,
) GetInnerScopeFunc {
    return &struct {
        fn call(
            a: Allocator,
            s: Scope,
        ) error{OutOfMemory}!Scope {
            var sc: Scope = s;
            inline for (funcs, 0..) |f, i| {
                sc = try f(a, sc);
                defer if (i < funcs.len - 1) sc.deinit(a);
            }
            return sc;
        }
    }.call;
}
```

This chain is used to traverse down through the outermost `Root` scope into whichever child is needed. A very similar thing happens when traversing through the root to get to the type that needs to be written to the writer.

### Wrapping up

The core idea here is that instead of trying to build a type that represents every possible value that could be accessed, I'm building function chains at compile time that know how to navigate to any field in the type graph. Each `Scope` carries these pre-computed maps of accessor functions, which means at runtime I just look up the right function and call it. It's cleaner, scales better with nested types, and honestly just makes more sense conceptually.
