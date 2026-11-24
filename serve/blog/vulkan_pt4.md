## Systems
My most recent change was reorganizing the codebase to create more defined boundaries around what the `engine` library code the consuming binaries. Before I had the `systems` directory in the engine itself, but this does not reflect how systems should be defined. An engine should expose system declaration to users so they can implement game systems as needed.
I exposed systems to users via `SystemManager`:

```zig
pub fn SystemManager(
    World: type,
    Systems: []const type,
) type {}
```

We will get to the `World` parameter, as it something else exposed to users via a function very similar to `SystemManager`. For now, lets focus on the `Systems` array passed to this function.
Each type in the `Systems` array is expected to have method declaration matching any amount of the declaration described in the `SystemHook` enum:
```zig
const SystemHook = enum {
    deinit,
    initEntities,
    update,
    drawImgui,
    registerSets,
    updateSets,
    syncResources,
    syncWorld,
    initComputePipelines,
    recordComputeCommands,
}
```
Each of these functions exists in the type returned by `SystemManager`, they basically just call the function for each type in `Systems` that also has said function, in the order the systems appear in the `Systems` array. For example, take a look at `deinit`
```zig
pub fn deinit(
    self: *@This(),
    allocs: core.engine.Allocators,
    device: vk.Device,
    alloc_cbs: ?*vk.AllocationCallbacks,
) void {
    inline for (ALL_TAGS) |tag| {
        if (@hasDecl(SYSTEM_TYPES.get(tag), @src().fn_name))
            if (@field(self.plexe, @tagName(tag))) |*f| f.deinit(allocs, device, alloc_cbs);
    }
}
```
All of the variants in `SystemHook` have a function that looks almost identical to this. There is some fancy meta-programming happening that allows me to check if a given type in the `Systems` array actually has a declaration, but the general idea is fairly easy to comprehend. I iterate through the systems, if the current system has a declaration name matching the current function (`@src().fn_name`), I call the function, assuming that it takes the same arguments. Like I said there is some fancy meta-programming happening to ensure that functions' signatures are correct at compile time, but I will not get into that now. 

In practice, the `SystemManager` is declared by a consumer in `bins/shared.zig` like so:
```zig
pub const systems = struct {
    pub const Camera = @import("systems/Camera.zig");
    pub const Debug = @import("systems/Debug.zig");
    pub const DrawBackground = @import("systems/DrawBackground.zig");
    pub const Maze = @import("systems/Maze.zig");
};
pub const SystemManager = engine.engine.systems.SystemManager(GameWorld, &[_]type{
    systems.Maze,
    systems.Camera,
    systems.DrawBackground,
    systems.Debug,
});
```
The user has their own `systems` folder where they define types that satisfy the interface described by `SystemHooks`, and they pass them in a list to the `SystemManager` function.

The reason I went about system declaration in this way is because `zig` doesn't provide any kind of interface abstraction like `c++`. It doesn't even provide an alternative, such as `Rust`'s traits. Instead the developer has to build what they need themselves. This solution works great for me because it allows me to explicitly describe the contract between the user and the engine's internals. Users can only access what `SystemManager` gives them access to, and if I find that I need to add a new function I can just add an entry to `SystemHook` and give the manager a declaration of that function.

The one caveat here is the `Debug` system. There are two places in the engine internals where I access the `Debug` system directly via: `self.systems.plexe.Debug.?`. This is very unsafe and generally just bad practice because I'm assuming the `Debug` system is present in whatever `SystemManaeger` was passed to the engine. I have decided that this is fine for now, because it is only done for the `Debug` system, and it is only used to update image descriptor sets that `imgui` is using in the `Debug` system. If I find that I start doing more of this unsafe access I'll reevaluate.


## World
Now we can get to the `GameWorld` parameter we passed to `SystemManager`. This is another place that I have to expose something about the engine to the user. The `World` is basically what data exists in the ECS that the engine & systems use. If you're unfamiliar, an entity component system (ECS) is basically just a database paradigm. Each entry is called an Entity, and it can have any number of components associated with it. The way this looks in my implementation is:
```zig
var ent = try world.entities.register("main_camera");
ent.addComponent(.camera, camera);
ent.addComponent(.world_transform, transform);
```
This entity would be considered the main camera entity. Since it was declared, I can make changes to it in the `update` function:
```zig
pub fn update(self: *@This(), world: *shared.GameWorld, ctx: engine.engine.systems.UpdateContext) void {
    var camera_ent = world.entityHandle(self.main_camera_entity.?) catch @panic("No entity??");
    var controller: *Controller = (camera_ent.accessComponentPtr(.camera) catch @panic("No camera component?")).camera;
    const trans: *engine.engine.world.WorldTransform = (camera_ent.accessComponentPtr(.world_transform) catch @panic("No transform component?")).world_transform;

    if (ctx.input.isDown(.@"/")) {
        const mode_count = std.enums.values(Controller.Mode).len;
        const current: usize = @intCast(@backingInt(controller.mode));
        controller.mode = @fromBackingInt(@intCast((current + 1) % mode_count));
    }

    switch (controller.mode) {
        .input => controller.control(&self.gpu_camera.?, trans, ctx.dt, ctx.input),
        else => {},
    }
}
```
So, now that you know what the purpose of an ecs is and how it's used, lets get into how a user of my engine would define their world.
As I said before, my ecs implementation asks to know what all the components are at compile time. This is done with yet another function that returns a type:
```zig
pub fn EntityStore(
    comptime Options: EcsOptions,
) type {}
```
I'm not going to go too deep into this, but one of the fields of `EcsOptions` is `Components`, which is just a `struct` type. The components of the ecs correspond to each field in `Components`, the name of the component is the field name and the type is the field's type. Lets say I wanted an ecs with the following components: health, speed, armor. This is how I might express that:
```zig
const Ecs = EntityStore(.{
  .max_entities = 1024,
  .Components = struct {
    health: u32,
    speed: f32,
    armor: bool,
  }
});
```
Now I have a database that I can query and update that has compile time assurances about the types stored in it. 
Exposing the `World` to users in this way gives them a lot of control over all kinds of things. It also allows them to create systems that act on component data that I don't even have to think about as the author of the engine library. They can just add any component they like to the entity store and confidently access those components through their systems.

There is one problem though. What about components that must exist in the engine for it to function? For example, consider rendering logic. The way my renderer currently works is through instancing. You create an instance with a given mesh index, material index and a transform, the renderer then queries the game world through for each instance of a mesh. Every mesh gets a single draw call that renders all of it's instances. Additionally, consider transforms! Anything running in the renderer must have a transform... do I really want to demand that users ensure they include a `transform` component with a `engine.world.WorldTransform` type? Of course not, that would be unneccessarily cumbersome and just generally annoying. My solution to this was a light wrapper around `EntityStore`:
```zig
pub const RenderComponents = struct {
    world_transform: WorldTransform,
    screen_transform: ScreenTransform,
    mesh3D: MaterialMesh3D,
    mesh2D: MaterialMesh2D,
    rigid_body: RigidBody,
};

pub inline fn GameWorld(options: core.lib.ecs.EcsOptions) type {
    return core.lib.ecs.EntityStore(.{
        .max_entities = options.max_entities,
        .Components = @Struct(
            .auto,
            null,
            @typeInfo(RenderComponents).@"struct".field_names ++ @typeInfo(options.Components).@"struct".field_names,
            @typeInfo(RenderComponents).@"struct".field_types ++ @typeInfo(options.Components).@"struct".field_types,
            @typeInfo(RenderComponents).@"struct".field_attrs ++ @typeInfo(options.Components).@"struct".field_attrs,
        ),
    });
}
```
If you're unfamiliar with zig this might seem like a lot, but really all it does is create an `EntityStore` with the Render components and any components a user wants. There are a few nice perks that come with this approach:
* If any user tries to create a component matching the name of any RenderComponent they will get a compile time error
* When writing engine internals that utilize the GameWorld, I always know that my render components will exist
* If I need to expand my rendering logic and the components it utilizes, all I need to do is add to the `RenderComponents` struct
* Users can query for their own components and the provided render components in their systems

## Usage Overview
Now that we've covered the exposed `GameWorld` and `SystemManager`, we can take a look at how a user actually uses the engine. This is one more wrapper type: 
```zig
pub fn Ecs(
    Systems: type,
    EntityStore: type,
) type {
    std.debug.assert(EntityStore.IS_ENTITY_STORE);
    std.debug.assert(Systems.IS_SYSTEM_MANAGER);
    // ...
}
```
I have `IS_ENTITY_STORE` and `IS_SYSTEM_MANAGER` members declared in the types returned by `EntityStore` and `SystemManager` respectively. This may seem redundant and It may seem like I'm overusing generic wrapper functions like this, but I've found its a great way to separate concerns and keep things modular both for users and for me as the engine author. The way this is used in practice looks like this:
```zig
var engine = core.engine.Engine.init(
    a,
    init.io,
    resources_ci,
    shared.systems.Camera.CAMERA_SET_NAME,
    null,
);


const Ecs = core.engine.Engine.Ecs(shared.SystemManager, shared.GameWorld);
var ecs = Ecs{
    .entities = try shared.GameWorld.init(core_engine.allocs.std),
    .systems = shared.SystemManager{},
};
```
The user first creates the `CoreEngine` type, which is just a regular struct that contains all the rendering logic, allocators, resources, etc. Users must define their own ecs type, which you can see is done here with their custom `shared.SystemManager` and `shared.GameWorld`. Then they create the actual ecs with regular zig struct initialization syntax.
The ecs is what holds all the logic required for running the game:
```zig
engine.initImgui();
ecs.registerSets(&engine);
engine.uploadResources();
ecs.updateSets(&engine);
ecs.initPipelines(&engine);

engine.physics.createMeshColliders(
    engine.allocs.std,
    &engine.resources.meshes3D,
) catch @panic("OOM");

createEntities(&ecs.world, &engine.resources, &engine.physics);
ecs.run(&engine);
```

Because the ecs holds both the systems and the world, any method that requires data from those types is called through ecs's methods. In the code above you can see that descriptor sets are registerd and updated and graphics pipelines are created through the ecs. This is because the renderer queries the world for render entities and users can create their own compute pipelines through the system manager. However, core engine handles resources entirely separately from the `SystemManager` and `GameWorld` types respectively.
The consumer creates a function called `CreateEntities` just to consolidate all their scene creation. Finally, `run` is called from the ecs because access to the world and systems are required for running the engine.

## Pipeline descriptions
Now that we've seen the broad strokes of how to get started with the engine, I'm going to dive into how a user (and myself internally) declare pipelines through the abstraction `pipelines.Description`, yet another function that returns a type:
```zig
pub fn Description(comptime opts: DescriptionOptions) type {
  ...
}

const DescriptionOptions = struct {
    /// Should be an enum type
    /// sets will be in order of the variants
    DescriptorSets: type,
    /// passed as null when used for compute pipelines
    subpass_idx: ?u32,
    input_attachments: ?std.EnumSet(Renderer.Attachments.Tags) = null,
    color_attachments: ?std.EnumSet(Renderer.Attachments.Tags) = null,
    depth_attachment: ?Renderer.Attachments.Tags = null,
    push_constants: ?struct {
        type,
        clibs.vk.ShaderStageFlags,
    } = null,
};
pub const Common = struct {
    device: clibs.vk.Device,
    render_pass: clibs.vk.RenderPass,
    window_extent: clibs.vk.Extent2D,
};
```
So whenever me or a user needs to create a new pipeline, this makes declaring the descriptor sets, attachments and push constants information fairly easy. For an example, take a look at how I'm declaring the pipelines used in my geometry rendering in my renderer's internals:
```zig
pub const GBufferDescription = core.engine.pipelines.Description(.{
    .DescriptorSets = enum { camera, meshes, instances, samplers, textures },
    .color_attachments = .initMany(&.{ .position, .normal, .albedo }),
    .depth_attachment = .depth,
    .subpass_idx = 0,
    .push_constants = .{
        MeshInstanceConstants, vk.SHADER_STAGE_VERTEX_BIT,
    },
});

pub const SSAODescription = core.engine.pipelines.Description(.{
    .DescriptorSets = enum { camera, samplers, textures },
    .color_attachments = .initOne(.ssao),
    .subpass_idx = 1,
});
pub const FinalDescription = core.engine.pipelines.Description(.{
    .DescriptorSets = enum { input_attachments },
    .input_attachments = .initMany(&.{ .depth, .position, .normal, .albedo, .ssao }),
    // we do not pass a color attachment here because it is the final attachment
    // so manager will pass it later
    .color_attachments = null,
    .subpass_idx = 2,
    .push_constants = .{
        DitherParams, vk.SHADER_STAGE_FRAGMENT_BIT,
    },
});
```
This makes it easy to know all the data needed for a given pipeline at a glance. Just by looking at these Description types, I know the descriptor sets as well as their order, I also know the framebuffer attachments, subpass index and push constants information.
I've also provided some helper types for easily passing descriptor sets and their layouts while getting compile time assurances they are all passed.
`pipelines.Description` declares these two types internally:
```zig
pub const Layouts = std.EnumArray(opts.DescriptorSets, clibs.vk.DescriptorSetLayout);
pub const Sets = std.EnumArray(opts.DescriptorSets, clibs.vk.DescriptorSet);
```
If you're unfamiliar with zig's `EnumArray`, it is just an array that has the one entry for each enum variant with some methods for accessing said entries through the enums. Since `opts.DescriptorSets` is asserted as an enum, I know that this is safe to call and it makes it very easy to make sure I'm grabbing all the correct layouts. Here is the use of `Layouts` in practice in the `initPipelines` method of my Geometry pipelines module:
```zig
const gbuffer_layouts = GraphicsPipelines.GBufferDescription.Layouts.init(.{
    .camera = resources.mapped_buffers.buffer_set_layouts.get(self.camera_set_name).?.layout,
    .samplers = resources.materials.samplers_descriptor_set_layout,
    .textures = resources.materials.all_textures_descriptor_set_layout,
    .meshes = resources.meshes3D.descriptor_set_layout,
    .instances = resources.mapped_buffers.buffer_set_layouts.get(INSTANCE_SET_NAME).?.layout,
});
```
For context, the convention is that `Layouts` can be grabbed from `resources` and `Sets` can be grabbed from `allocated_resources`:
```zig
const gbuffer_sets = GraphicsPipelines.GBufferDescription.Sets.init(.{
    .camera = allocated_resources.mapped_buffers.buffer_sets.get(self.camera_set_name).?.set,
    .samplers = allocated_resources.materials.sampler_set,
    .meshes = allocated_resources.meshes3D.descriptor_set,
    .instances = allocated_resources.mapped_buffers.buffer_sets.get(INSTANCE_SET_NAME).?.set,
    .textures = allocated_resources.materials.all_textures_descriptor_set,
});

```

