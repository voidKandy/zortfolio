# Improvments to Vulkan engine
In my last post, I mentioned three abstractions as problematic: `PipelineObject`, `BoundDescriptor`, and `ResourceManager`. I have since dropped all three completely, along with several others I will spare you the details of. 
These three abstractions perfectly encapsulate everything that was wrong with my earlier approach. I was confused about where to draw boundaries between pipelines, descriptors, and resources. `PipelineObject` and `BoundDescriptor` were my attempt to encapsulate each separately, but this was a mistake. Pipelines and descriptor sets *are* coupled by nature, and trying to treat them as independent only made things harder to reason about. As for the `ResourceManager`, I was designing an abstraction for managing resources before I even understood how mesh data would be allocated on the GPU. You cannot design a good abstraction for something you don't yet understand. 
## New Features
I will get into the details of what's changed, but I would like to start off by showcasing some of the new features of the engine.

For starters, arbitrary obj files can be loaded and rendered using the engine. They can have their own materials.
![graphics pipeline showcase 1](imgs/gphx_pipeline_showcase1.png)
Materials and world transforms can be mutated at runtime.
![graphics pipeline showcase 2](imgs/gphx_pipeline_showcase2.png)
Alternative pipelines can also be selected at runtime.
![graphics pipeline showcase 3](imgs/gphx_pipeline_showcase3.png)
The compute pipeline's capabilities are mostly the same.
![compute pipeline showcase 1](imgs/cmpt_pipeline_showcase1.png)
Data associated with the compute pipeline can also be mutated at runtime.
![compute pipeline showcase 2](imgs/cmpt_pipeline_showcase2.png)

## New Abstractions
`VulkanEngine` is already a fat struct of everything needed to run the engine: allocators, device handles, render passes, swapchain, and so on. What I was trying to do with `PipelineObject` and `BoundDescriptor` was create generic objects with a shared interface, so I could hold arrays of pipeline and descritor objects whose logic was neatly encapsulated behind a common API. The instinct to simplify is understandable, but in practice it just added indirection without clarity. It is also worth noting that in Zig, interfaces require manual implementation, which adds friction that compounds quickly. 
In the new approach, nothing about pipelines or descriptors is generic. Each pipeline is treated as a distinct set of objects with their own logic. 
We went from this: 
```zig
const VulkanEngine = struct {
    // ...
    pipeline_objects: PipelineManager = undefined,
    bound_descriptors: std.StringHashMap(BoundDescriptor) = undefined,
    // ...
};
```
To this: 
```zig
const VulkanEngine = struct {
    // ...
    main_compute_pipeline: ComputePipeline = undefined,
    main_compute_pipeline_data: ComputePipeline.AllocatedData = undefined,
    main_compute_descriptor_set: vk.DescriptorSet = undefined,
    main_compute_pipeline_description: ComputePipeline.Description = undefined,
    
    main_graphics_pipeline_create_data: GraphicsPipeline.AllocatedData.CreateData,
    main_graphics_pipeline: GraphicsPipeline = undefined,
    main_graphics_pipeline_data: GraphicsPipeline.AllocatedData = undefined,
    main_graphics_pipeline_systems_data: GraphicsPipeline.SystemsData = undefined,
    main_graphics_descriptor_set: vk.DescriptorSet = undefined,
    main_graphics_texture_descriptor_set: vk.DescriptorSet = undefined,
    main_graphics_pipeline_description: GraphicsPipeline.Description = undefined,
    // ...
};
```
This may look more verbose, but the explicit fields make it immediately clear what each piece is for. You might notice that `ComputePipeline` and `GraphicsPipeline` share a similar shape; both have `Description` and `AllocatedData` types associated with them. Rather than enforcing this with vtables, I have opted for conventions about how pipelines should be structured that are not enforced by the compiler, but that I follow consistently.

Some of the soft rules include the inclusion of: 
+ `Description`: everything needed to create the pipeline, passed to its `init` function. For example, `GraphicsPipeline.Description` holds the device, render pass, window extent, shader modules and a few configuration options.
+ `AllocatedData`: Stores any GPU side data that the pipeline needs to access.
+ `SystemsData`: Stores any CPU side data that the pipeline needs to access in it's `recordCommandBuffer` function.
+ Some functions, such as `init` and `recordCommandBuffer`, and a few others.
  + Helper functions for quickly initializing the pipeline and data associated with it (`createDescriptorPool`, `allocateDescriptorSet`, `updateDescriptorSets`)

These conventions have made the codebase significantly easier to reason about and have noticeably sped up development. As a bonus, moving each pipeline into its own struct meant I could also delete `PipelineBuilder` and several other generic utilities that were only necessary because of the old abstraction.

## Mesh and Material loading
Previously, a single function handled both loading a mesh from disk and uploading it to the GPU, and it could only be called once per mesh. Because it was uploading directly to the GPU, it also had to block on a semaphore until the upload completed. This was fine as a starting point for getting familiar with Vulkan, but it is not a scalable approach.

In the new implementation, the engine accepts an array of `MeshCreateInfo`, which pairs a loaded OBJ file with a world transform (defaulting to the origin if none is provided), along with an array of `.mtl` files. All OBJ files are assumed to share materials from the provided `.mtl` files; if a material is referenced that cannot be found, the program will panic.
Here is how this looks: 

```zig
const camera = core.Camera{};
var global_mat = core.mtl_loader.parseFile(a, "assets/globals.mtl") catch @panic("failed to load materials file");
defer global_mat.deinit();
var debug_mat = core.mtl_loader.parseFile(a, "assets/debug.mtl") catch @panic("failed to load materials file");
defer debug_mat.deinit();
const meshes_object_files = core.obj_loader.readObjDirectory(a, "assets/meshes") catch @panic("failed to read objects");
const widgets_object_files = core.obj_loader.readObjDirectory(a, "assets/widgets") catch @panic("failed to read objects");
defer {
    for (meshes_object_files) |*obj|
        obj.deinit();
    a.free(meshes_object_files);
    for (widgets_object_files) |*obj|
        obj.deinit();
    a.free(widgets_object_files);
}
const amt_meshes_objects = meshes_object_files.len + widgets_object_files.len;

const meshes_objects = a.alloc(
    core.GraphicsPipeline.AllocatedData.CreateData.MeshCreateInfo,
    amt_meshes_objects,
) catch @panic("failed to alloc meshes_objects");
defer a.free(meshes_objects);
for (meshes_object_files, 0..) |*obj, i| meshes_objects[i] = .{
    .obj = obj.*,
};
for (widgets_object_files, 0..) |*obj, i| meshes_objects[i + meshes_object_files.len] = .{
    .obj = obj.*,
};

var engine = core.VulkanEngine.init(
    a,
    .{
        .camera = camera,
        .materials_files = &[_]core.mtl_loader.MtlFile{ global_mat, debug_mat },
        .mesh_objs = meshes_objects,
    },
    null,
);
```
During initialization, the engine converts each `ObjFile` into a `Mesh3D`. All meshes are then concatenated into two large buffers: one for vertices and one for indices. What the engine treats as a single mesh is actually a collection of submeshes, since a single OBJ file can reference multiple materials. As they are concatenated, the engine tracks the byte ranges for each submesh as well as the material index so the descriptor set can be indexed correctly at draw time. These ranges are stored in `GraphicsPipeline.SystemsData.mesh_ranges`.

Materials are handled similarly. Each `.mtl` file is parsed into a `Materials` struct, and all material textures are packed into a single texture atlas. Before upload, each submesh is assigned a material index computed from the human-readable material name referenced in its OBJ file, which it uses to index into the atlas at runtime. It is worth noting that each `.mtl` file corresponds to a single texture resource on the GPU, so passing two `.mtl` files results in two texture uploads.

## Non-uniform Indexing 
The material index approach relies on a Vulkan feature called non-uniform indexing. Rather than binding a single texture per draw call, we pass a material index per submesh and use it to index into a texture array at runtime. This is what allows many meshes with different materials to be drawn in a single pass without uploading a separate texture for each one. Here is my fragment shader (notice the use of `nonuniformEXT`): 
```glsl
#version 460
#extension GL_EXT_nonuniform_qualifier : require

layout(location = 0) in vec2 texCoord;
layout(location = 1) flat in uint MaterialIndex;
layout(location = 0) out vec4 out_Color;
layout(set = 1, binding = 0) uniform sampler2D Textures[];

vec4 TextureBindless2D(uint MaterialIndex, vec2 uv)
{
     return texture(Textures[nonuniformEXT(MaterialIndex)], uv);
}

void main()
{
    out_Color = TextureBindless2D(MaterialIndex, texCoord);
}
```

This is only possible because descriptor indexing is enabled on the Vulkan instance. Without it, all lanes in a GPU subgroup would be required to use the same index into the texture array. With it, each lane can carry a different material index, allowing the fragment shader to sample from whichever texture that submesh references.

I will not go into the details of how descriptor indexing is set up in the engine here, as there are better resources written by people with a much stronger grasp on the subject. I will say that the implementation was heavily inspired by emeiri's excellent [tutorial on descriptor indexing in Vulkan](https://github.com/emeiri/ogldev/blob/0d4b19d7fe5a2c53f85ec080d7b0d6d91386097c/Vulkan/Tutorial29/tutorial29.cpp#L46), which I owe a lot to.

## What's next?
I am really proud of how far I've come but there is still so much to do and I genuinely don't know what to tackle first. Here is a list of things I need to do just off the top of my head: 
+ Add a decent character controller
+ More mesh manipulation 
+ Physics engine integration
+ Terrain generation and runtime manipulation
+ ECS or some other resource management system for game systems
+ Many other things
Thanks for reading this blog post!
