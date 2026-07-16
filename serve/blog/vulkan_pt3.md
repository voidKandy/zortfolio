# More Improvements to the Rendering engine
Since my last post, I've changed quite a bit in my renderer. I've added an additional pipeline (or rather, set of pipelines): the `HudPipeline`. It manages a compute and graphics pipeline that renders anything I want on top of the scene as a HUD. Right now that's just a maze.

Speaking of which — I've also added a MAZE. Since this engine project is mostly for learning, but with the intention of eventually turning into a game (I haven't articulated on this blog what that game actually is yet, but I do have an idea), I wanted a way to generate mazes and render them in both 2D and 3D. The HUD pipeline takes the maze object and renders it in 2D on the HUD, while the mesh pipeline turns the same maze into an actual 3D mesh that gets rendered into the scene. I've also implemented a very shaky first-pass player controller and done a solid amount of cleanup.

### The maintenance

Let's start with what the source tree used to look like:

![tree before](imgs/tree_before.png)

And how it's organized now:

![tree after](imgs/tree_after.png)

I went from a mostly flat file structure — basically everything living directly in `src`, with some genuinely confused file placement inside `pipelines` (what was `Meshes2D`/`Meshes3D` even doing in there?). Now concerns are clearly separated by directory:

- **bindings** — Thin wrappers around any C library that needs one. Right now that's Vulkan, SDL, and VMA. I expect this to grow and I'll likely need one for a physics engine down the line.
- **clibs** — All C code lives here. `c.h` gets compiled via `build.zig`, and `clibs/root.zig` is a convenience layer that exposes structs for anything I expect to touch often. For example, rather than reaching for `@import("c").SDL_Window` everywhere, `clibs/root.zig` gives me an `sdl` struct with a `Window` type, so I can just do `@import("clibs/root.zig").sdl.Window`.
- **engine** — Any engine-level code. I tried to keep this as the outermost dependency layer, nothing imports `engine` except the actual consumer of the codebase (my binaries). There are a couple of exceptions: `engine.Engine.Allocators` leaks intentionally, because it's convenient to write `deinit` functions that take allocators owned by the engine. And `pipelines` does pull in engine code like `Camera`. `GlobalAllocatedData` holds anything global across all pipelines, the player camera lives here, for instance, so I can drop it into any pipeline's descriptor sets if a shader needs camera data. `MeshPipeline` uses this (more on that below).
- **lib** — General-purpose code. I could've called this `utils` or `common`, but `lib` felt closer to where I expect it to go. Right now it holds math helpers, mesh helpers, my `Maze` struct, and the ECS I plan to use eventually.
- **loaders** — Could technically live in `lib`, but I gave it its own directory anyway. Currently holds the `.mtl` and `.obj` loaders. I'll need to add more here, `.gltf` support being the obvious next one.
- **pipelines** — Where the pipelines themselves live. These are deliberately fat structs, usually containing a `PipelineLayout`, `Pipeline`, and their own `DescriptorSetLayout`/`DescriptorPool`. Letting each pipeline carry its own logic instead of building shared abstractions has been the best experience for me so far.
- **resources** — Code for any GPU-bound resources. `Meshes3D`, for example, takes N meshes and, on upload, concatenates all of them into a single vertex/index buffer. `Materials` works in a similar way.

## Screenshot of the engine

![Engine screenshot](imgs/vk_pt3_screenshot.png)

A lot more ImGui debug windows have shown up since last time. I can now switch camera modes between player, orbit, and fixed. The player controller isn't great yet; movement is choppy and awkward, but it works. The maze in the top-right is procedurally generated and written to an image via a compute shader, then displayed in that quad. The maze mesh you see is the same maze, generated as a mesh on the CPU rather than the GPU. I might eventually move maze mesh generation over to the GPU, but I'm holding off for now. I still have some experimenting to do around the mesh generation, especially if I end up using alpha wrapping to consolidate the maze mesh into something more organic-looking (a topic for a future post).

### What's next

The immediate next step is finishing up the code organization. I'd also like to surface the player camera position in the shader that draws the 2D maze on the HUD, so that'll probably be next.

After that, I want to migrate to dynamic rendering instead of my current approach. Right now I'm manually managing framebuffers, and dynamic rendering should let me stop thinking about that entirely. Once that's in, ambient occlusion is next; I don't want to jump straight into a full PBR lighting setup, so AO is the first step toward making things like the maze read as more than flat gray shapes. After that, I'll dive into alpha wrapping; I plan to use it on the maze first, but if the implementation ends up robust enough, I'd like to roll it out across the whole engine. Once that's done, integrating a physics engine feels like the natural next step.

Thanks for reading :)
