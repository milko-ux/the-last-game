# ============================================================
# THE FLOOR TILES — eight slate tiles built and baked in Blender,
# headless (brief stage B, 2026-09-24). Through tools/blender/bake_all.sh:
#
#   Blender -b --python tools/blender/tiles.py -- [atlas_px] [samples]
#
# Each variant is a 2 x 2 slab: a high mesh with relief (a subdivided top
# displaced by noise, bevelled edges) and a low one (one quad), the top
# baked from high to low -- stone with relief, bevelled edges, grain,
# darker occlusion toward the seams, the concept's slate (#243141) -- lit
# by our light plus a soft sky, into ONE atlas of 4 x 2 tiles
# (assets/models/kit/tile_atlas.png). The game's tile shader samples a
# variant per tile by a hash of its position; armed / live magenta and
# the cyan rim stay in the shader on top. Nothing here is an AI image.
# ============================================================
import bpy, bmesh, math, os, sys, random
from mathutils import Vector, noise

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ATLAS = int(ARGS[0]) if len(ARGS) > 0 else 2048
SAMPLES = int(ARGS[1]) if len(ARGS) > 1 else 64
COLS, ROWS = 4, 2
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models", "kit"))
os.makedirs(OUT, exist_ok=True)
LIGHT_GODOT = Vector((0.36, 0.8, -0.48))
LIGHT = Vector((LIGHT_GODOT.x, -LIGHT_GODOT.z, LIGHT_GODOT.y)).normalized()
SLATE = (0x24 / 255.0, 0x31 / 255.0, 0x41 / 255.0)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'; scene.cycles.samples = SAMPLES; scene.cycles.device = 'GPU'; scene.cycles.use_denoising = False
prefs = bpy.context.preferences.addons['cycles'].preferences
prefs.compute_device_type = 'METAL'; prefs.refresh_devices()
for d in prefs.devices:
    d.use = d.type == 'METAL'


def stone_material():
    m = bpy.data.materials.new("slate"); m.use_nodes = True
    nt = m.node_tree; nodes = nt.nodes; links = nt.links
    for n in list(nodes): nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial"); bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.9; bsdf.inputs["Specular IOR Level"].default_value = 0.25
    links.new(bsdf.outputs[0], out.inputs[0])
    fine = nodes.new("ShaderNodeTexNoise"); fine.inputs["Scale"].default_value = 18.0; fine.inputs["Detail"].default_value = 7.0
    coarse = nodes.new("ShaderNodeTexNoise"); coarse.inputs["Scale"].default_value = 1.6; coarse.inputs["Detail"].default_value = 3.0
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (SLATE[0] * 0.8, SLATE[1] * 0.82, SLATE[2] * 0.85, 1)
    ramp.color_ramp.elements[1].color = (SLATE[0] * 1.25, SLATE[1] * 1.2, SLATE[2] * 1.12, 1)
    links.new(coarse.outputs["Fac"], ramp.inputs["Fac"])
    mixg = nodes.new("ShaderNodeMix"); mixg.data_type = 'RGBA'; mixg.blend_type = 'OVERLAY'; mixg.inputs["Factor"].default_value = 0.3
    links.new(ramp.outputs["Color"], mixg.inputs[6]); links.new(fine.outputs["Fac"], mixg.inputs[7])
    ao = nodes.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = 0.35; ao.samples = 8
    grime = nodes.new("ShaderNodeValToRGB"); grime.color_ramp.elements[0].position = 0.2; grime.color_ramp.elements[1].position = 0.8
    grime.color_ramp.elements[0].color = (0.45, 0.45, 0.5, 1)
    links.new(ao.outputs["AO"], grime.inputs["Fac"])
    mixa = nodes.new("ShaderNodeMix"); mixa.data_type = 'RGBA'; mixa.blend_type = 'MULTIPLY'; mixa.inputs["Factor"].default_value = 0.55
    links.new(mixg.outputs[2], mixa.inputs[6]); links.new(grime.outputs["Color"], mixa.inputs[7])
    links.new(mixa.outputs[2], bsdf.inputs["Base Color"])
    return m


sun_data = bpy.data.lights.new("sun", 'SUN'); sun_data.energy = 1.6; sun_data.angle = math.radians(6)
sun = bpy.data.objects.new("sun", sun_data); bpy.context.collection.objects.link(sun)
sun.rotation_euler = (-LIGHT).to_track_quat('-Z', 'Y').to_euler()
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
bg = world.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.42, 0.48, 0.58, 1.0); bg.inputs[1].default_value = 1.8

atlas = bpy.data.images.new("tile_atlas", ATLAS, ATLAS // 2); atlas.generated_color = (0, 0, 0, 1)
stone = stone_material()
lows = []
random.seed(7)
for v in range(COLS * ROWS):
    col, row = v % COLS, v // COLS
    # the high tile: a 2 x 2 x 0.3 block, top subdivided and displaced, edges bevelled, offset so each sits apart
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(col * 3.0, row * 3.0, 0.0))
    high = bpy.context.active_object; high.name = "high_%d" % v
    high.scale = (1.0, 1.0, 0.15); bpy.ops.object.transform_apply(scale=True)
    bev = high.modifiers.new("bevel", 'BEVEL'); bev.width = 0.07; bev.segments = 3
    bpy.context.view_layer.objects.active = high; bpy.ops.object.modifier_apply(modifier="bevel")
    bm = bmesh.new(); bm.from_mesh(high.data)
    top = [f for f in bm.faces if f.normal.z > 0.9 and f.calc_area() > 0.5]
    if top:
        res = bmesh.ops.subdivide_edges(bm, edges=list({e for f in top for e in f.edges}), cuts=22, use_grid_fill=True)
    bm.verts.ensure_lookup_table()
    seed = Vector((v * 11.3, v * 7.1, 0.0))
    for vert in bm.verts:
        if vert.co.z > 0.1:
            p = vert.co + seed
            n1 = noise.noise(p * 2.2); n2 = noise.noise(p * 7.0)
            edge = min(1.0, max(0.0, (0.5 - max(abs(vert.co.x - col * 3.0), abs(vert.co.y - row * 3.0))) * 6.0))
            vert.co.z += (n1 * 0.045 + n2 * 0.012) * edge
    bm.to_mesh(high.data); bm.free()
    high.data.materials.append(stone)
    bpy.ops.object.shade_smooth()
    # the low tile: one quad at the top, UVs into its atlas cell
    me = bpy.data.meshes.new("tile_%d" % v); bm = bmesh.new()
    cx, cy = col * 3.0, row * 3.0
    vs = [bm.verts.new((cx - 0.5, cy - 0.5, 0.15)), bm.verts.new((cx + 0.5, cy - 0.5, 0.15)), bm.verts.new((cx + 0.5, cy + 0.5, 0.15)), bm.verts.new((cx - 0.5, cy + 0.5, 0.15))]
    f = bm.faces.new(vs)
    uv_layer = bm.loops.layers.uv.new()
    pad = 0.015
    for loop in f.loops:
        lx = (loop.vert.co.x - (cx - 0.5)); ly = (loop.vert.co.y - (cy - 0.5))
        loop[uv_layer].uv = ((col + pad + lx * (1 - 2 * pad)) / COLS, (row + pad + ly * (1 - 2 * pad)) / ROWS)
    bm.to_mesh(me); bm.free()
    low = bpy.data.objects.new("tile_%d" % v, me); bpy.context.collection.objects.link(low)
    lm = bpy.data.materials.new("bake_%d" % v); lm.use_nodes = True; low.data.materials.append(lm)
    tex = lm.node_tree.nodes.new("ShaderNodeTexImage"); tex.image = atlas; lm.node_tree.nodes.active = tex
    lows.append((low, high))

scene.render.bake.use_selected_to_active = True
scene.render.bake.cage_extrusion = 0.25
scene.render.bake.max_ray_distance = 0.5
scene.render.bake.margin = 4
first = True
for (low, high) in lows:
    bpy.ops.object.select_all(action='DESELECT')
    high.select_set(True); low.select_set(True); bpy.context.view_layer.objects.active = low
    scene.render.bake.use_clear = first; first = False
    bpy.ops.object.bake(type='COMBINED', pass_filter={'DIRECT', 'INDIRECT', 'COLOR', 'DIFFUSE'})
atlas.filepath_raw = os.path.join(OUT, "tile_atlas.png"); atlas.file_format = 'PNG'; atlas.save()
print("TILES DONE", OUT, "%d tiles, %d x %d" % (COLS * ROWS, ATLAS, ATLAS // 2))
