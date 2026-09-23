# ============================================================
# THE PILLAR KIT — built and baked in Blender, headless (brief stage B,
# 2026-09-24). Run through tools/blender/bake_all.sh, or on its own:
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/pillars.py -- [atlas_px] [samples]
#
# Six pillar variants and one lintel, like the concept: straight,
# vertical, square in section, chamfered edges, stacked blocks with
# joints, recessed panels, the circle motif, a few carved abstract
# symbols, a cap stone. Each variant is TWO meshes: a low one (the
# chamfered stack, what the game draws) and a high one with every
# recess cut in. The stone material -- grain, weathering, edge wear,
# grime in the recesses -- lit by OUR light (pr_light_dir, the game's
# CreatureLight) plus a soft sky, with ambient occlusion, is baked from
# the high mesh onto the low one, into ONE atlas, light included in the
# colour (the world shaders are unshaded). The pillars keep a fixed
# orientation in the game (monoliths.gd), so the baked light is right.
#
# Writes assets/models/kit/pillar_<name>.glb (the low meshes, UVs into
# the atlas), assets/models/kit/pillar_atlas.png, and kit.json (the
# variants' sizes). Nothing here is an AI image: the material is nodes.
# ============================================================
import bpy, bmesh, json, math, os, sys
from mathutils import Vector, Matrix

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ATLAS = int(ARGS[0]) if len(ARGS) > 0 else 2048
SAMPLES = int(ARGS[1]) if len(ARGS) > 1 else 64
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models", "kit"))
os.makedirs(OUT, exist_ok=True)

# Godot (x, y up, z) -> Blender (x, -z, y up). The game's light, toward the light.
LIGHT_GODOT = Vector((0.36, 0.8, -0.48))
LIGHT = Vector((LIGHT_GODOT.x, -LIGHT_GODOT.z, LIGHT_GODOT.y)).normalized()
SLATE = (0.29, 0.31, 0.36)        # the stone's base colour (lit faces read #556173-ish in fog); the game tints per band
CHAMFER = 0.06                    # of the width, on the low mesh's edges

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = SAMPLES
scene.cycles.device = 'GPU'
scene.cycles.use_denoising = False
prefs = bpy.context.preferences.addons['cycles'].preferences
prefs.compute_device_type = 'METAL'
prefs.refresh_devices()
for d in prefs.devices:
    d.use = d.type == 'METAL'


# ---------- geometry helpers (all in model units: width 1 at the base, height h) ----------
def box(bm, cx, cy, z0, z1, hx, hy):
    """An axis-aligned box from z0 to z1, half extents hx, hy, centred on (cx, cy). Returns its faces."""
    verts = []
    for z in (z0, z1):
        for sy in (-1, 1):
            for sx in (-1, 1):
                verts.append(bm.verts.new((cx + sx * hx, cy + sy * hy, z)))
    v = verts
    faces = [
        (v[0], v[1], v[3], v[2]), (v[4], v[6], v[7], v[5]),
        (v[0], v[4], v[5], v[1]), (v[2], v[3], v[7], v[6]),
        (v[0], v[2], v[6], v[4]), (v[1], v[5], v[7], v[3]),
    ]
    out = []
    for f in faces:
        out.append(bm.faces.new(f))
    return out


def stack(bm, blocks):
    """blocks: list of (z0, z1, half_x, half_y). Each block is a box."""
    for (z0, z1, hx, hy) in blocks:
        box(bm, 0.0, 0.0, z0, z1, hx, hy)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)


def make_object(name, build, chamfer=0.0):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build(bm)
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if chamfer > 0.0:
        mod = ob.modifiers.new("chamfer", 'BEVEL')
        mod.width = chamfer; mod.segments = 1; mod.limit_method = 'ANGLE'; mod.angle_limit = math.radians(40)
    return ob


def cut(target, cutter):
    """Boolean difference, applied."""
    mod = target.modifiers.new("cut", 'BOOLEAN'); mod.operation = 'DIFFERENCE'; mod.object = cutter; mod.solver = 'EXACT'
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def cutter_box(name, cx, cy, cz, hx, hy, hz):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    box(bm, cx, cy, cz - hz, cz + hz, hx, hy); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(ob); return ob


def cutter_cyl(name, cx, cy, cz, r, depth, axis='Y', segs=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=segs, radius=r, depth=depth, location=(cx, cy, cz))
    ob = bpy.context.active_object; ob.name = name
    if axis == 'Y': ob.rotation_euler = (math.radians(90), 0, 0)
    elif axis == 'X': ob.rotation_euler = (0, math.radians(90), 0)
    bpy.ops.object.transform_apply(rotation=True)
    return ob


def apply_mods(ob):
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


# ---------- the variants: (name, height, low blocks, decorate(high object)) ----------
# Widths: the base block is 1.0 wide (half 0.5); the game scales uniformly by height.
def v_plain(h):
    low = [(0.0, 0.08 * h, 0.5, 0.5), (0.08 * h, 0.92 * h, 0.44, 0.44), (0.92 * h, h, 0.48, 0.48)]
    def deco(ob):
        # two recessed panels on the +x and -z faces (the lit faces), a joint every quarter
        for cz in (0.35 * h, 0.7 * h):
            cut(ob, cutter_box("p", 0.44, 0.0, cz, 0.09, 0.26, 0.10 * h))
            cut(ob, cutter_box("p", 0.0, 0.44, cz, 0.26, 0.09, 0.10 * h))
            cut(ob, cutter_box("p", -0.44, 0.0, cz, 0.09, 0.26, 0.10 * h))
        for cz in (0.3 * h, 0.55 * h, 0.8 * h):
            cut(ob, cutter_box("j", 0.0, 0.0, cz, 0.47, 0.47, 0.03))
    return low, deco


def v_circle(h):
    low = [(0.0, 0.1 * h, 0.52, 0.52), (0.1 * h, 0.9 * h, 0.45, 0.45), (0.9 * h, h, 0.5, 0.5)]
    def deco(ob):
        # the circle motif: a recessed disc with a ring, on the -z face and the +x face
        for (cx, cy, axis) in ((0.0, 0.45, 'Y'), (0.45, 0.0, 'X'), (-0.45, 0.0, 'X')):
            cut(ob, cutter_cyl("c", cx, cy, 0.62 * h, 0.22, 0.14, axis))
            ring_in = cutter_cyl("r", cx, cy, 0.62 * h, 0.14, 0.2, axis)
            cut(ob, cutter_cyl("r", cx, cy, 0.62 * h, 0.16, 0.12, axis))
            bpy.data.objects.remove(ring_in, do_unlink=True)
        for cz in (0.25 * h, 0.4 * h):
            cut(ob, cutter_box("j", 0.0, 0.0, cz, 0.47, 0.47, 0.012))
    return low, deco


def v_stacked(h):
    n = 5
    low = []
    for i in range(n):
        z0, z1 = i * h / n, (i + 1) * h / n
        w = 0.5 - 0.015 * i
        low.append((z0 + 0.008 * h, z1 - 0.008 * h, w, w))
    def deco(ob):
        # deep joints between the blocks, a symbol on the third
        for i in range(1, n):
            cut(ob, cutter_box("j", 0.0, 0.0, i * h / n, 0.55, 0.55, 0.02 * h))
        cz = 2.5 * h / n
        for cy in (0.47, -0.47):
            cut(ob, cutter_box("s", 0.0, cy, cz, 0.16, 0.07, 0.03))
            cut(ob, cutter_box("s", 0.0, cy, cz + 0.06 * h, 0.16, 0.07, 0.03))
            cut(ob, cutter_box("s", 0.0, cy, cz - 0.06 * h, 0.16, 0.07, 0.03))
    return low, deco


def v_symbols(h):
    low = [(0.0, 0.06 * h, 0.5, 0.5), (0.06 * h, 0.94 * h, 0.42, 0.42), (0.94 * h, h, 0.46, 0.46)]
    def deco(ob):
        # carved abstract symbols down the -z face: bars, a lozenge, a ring
        z = 0.2 * h
        for k in range(4):
            cz = z + k * 0.17 * h
            if k % 2 == 0:
                cut(ob, cutter_box("s", 0.0, 0.42, cz, 0.2, 0.08, 0.035))
                cut(ob, cutter_box("s", 0.12, 0.42, cz + 0.05 * h, 0.05, 0.08, 0.06))
            else:
                cut(ob, cutter_cyl("s", 0.0, 0.42, cz, 0.12, 0.16, 'Y'))
        cut(ob, cutter_box("p", 0.42, 0.0, 0.5 * h, 0.09, 0.22, 0.3 * h))
        cut(ob, cutter_box("p", -0.42, 0.0, 0.5 * h, 0.09, 0.22, 0.3 * h))
    return low, deco


def v_slab(h):
    low = [(0.0, 0.05 * h, 0.55, 0.3), (0.05 * h, 0.95 * h, 0.5, 0.24), (0.95 * h, h, 0.53, 0.28)]
    def deco(ob):
        for cz in (0.3 * h, 0.6 * h):
            cut(ob, cutter_box("p", 0.0, 0.24, cz, 0.3, 0.08, 0.11 * h))
        cut(ob, cutter_cyl("c", 0.0, 0.24, 0.82 * h, 0.16, 0.16, 'Y'))
        for cz in (0.45 * h, 0.75 * h):
            cut(ob, cutter_box("j", 0.0, 0.0, cz, 0.6, 0.6, 0.012))
    return low, deco


def v_capped(h):
    low = [(0.0, 0.07 * h, 0.5, 0.5), (0.07 * h, 0.86 * h, 0.4, 0.4), (0.86 * h, 0.9 * h, 0.46, 0.46), (0.9 * h, h, 0.52, 0.52)]
    def deco(ob):
        for cz in (0.3 * h, 0.5 * h, 0.7 * h):
            cut(ob, cutter_box("j", 0.0, 0.0, cz, 0.45, 0.45, 0.01))
        cut(ob, cutter_box("p", 0.4, 0.0, 0.48 * h, 0.09, 0.2, 0.28 * h))
        cut(ob, cutter_box("p", -0.4, 0.0, 0.48 * h, 0.09, 0.2, 0.28 * h))
        cut(ob, cutter_box("p", 0.0, 0.4, 0.48 * h, 0.2, 0.09, 0.28 * h))
    return low, deco


def v_lintel(h):
    # a bridge piece between two pillars: a long beam, 1 unit tall, h long (along x)
    low = [(0.0, 1.0, 0.4, h * 0.5)]
    def deco(ob):
        for k in range(int(h)):
            cut(ob, cutter_box("j", 0.0, -h * 0.5 + (k + 0.5), 0.5, 0.5, 0.012, 0.6))
        cut(ob, cutter_box("p", 0.4, 0.0, 0.5, 0.03, h * 0.42, 0.2))
        cut(ob, cutter_box("p", -0.4, 0.0, 0.5, 0.03, h * 0.42, 0.2))
    return low, deco


VARIANTS = [("plain", 8.0, v_plain), ("circle", 8.0, v_circle), ("stacked", 8.0, v_stacked),
            ("symbols", 8.0, v_symbols), ("slab", 8.0, v_slab), ("capped", 8.0, v_capped), ("lintel", 6.0, v_lintel)]


# ---------- the stone material: grain, weathering, edge wear, grime ----------
def stone_material():
    m = bpy.data.materials.new("stone"); m.use_nodes = True
    nt = m.node_tree; nodes = nt.nodes; links = nt.links
    for n in list(nodes): nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial"); bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.95; bsdf.inputs["Specular IOR Level"].default_value = 0.2
    links.new(bsdf.outputs[0], out.inputs[0])
    # grain: fine noise on the base colour; weathering: a coarse noise moving it between two slates
    fine = nodes.new("ShaderNodeTexNoise"); fine.inputs["Scale"].default_value = 26.0; fine.inputs["Detail"].default_value = 6.0
    coarse = nodes.new("ShaderNodeTexNoise"); coarse.inputs["Scale"].default_value = 2.2; coarse.inputs["Detail"].default_value = 3.0
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (SLATE[0] * 0.78, SLATE[1] * 0.78, SLATE[2] * 0.8, 1)
    ramp.color_ramp.elements[1].color = (SLATE[0] * 1.15, SLATE[1] * 1.12, SLATE[2] * 1.08, 1)
    links.new(coarse.outputs["Fac"], ramp.inputs["Fac"])
    mixg = nodes.new("ShaderNodeMix"); mixg.data_type = 'RGBA'; mixg.blend_type = 'OVERLAY'; mixg.inputs["Factor"].default_value = 0.35
    links.new(ramp.outputs["Color"], mixg.inputs[6]); links.new(fine.outputs["Fac"], mixg.inputs[7])
    # edge wear: pointiness (convex edges) lightens; grime: AO darkens the recesses
    geo = nodes.new("ShaderNodeNewGeometry")
    wear = nodes.new("ShaderNodeMath"); wear.operation = 'SMOOTH_MIN'
    wearramp = nodes.new("ShaderNodeValToRGB"); wearramp.color_ramp.elements[0].position = 0.5; wearramp.color_ramp.elements[1].position = 0.62
    links.new(geo.outputs["Pointiness"], wearramp.inputs["Fac"])
    mixw = nodes.new("ShaderNodeMix"); mixw.data_type = 'RGBA'; mixw.blend_type = 'ADD'; mixw.inputs["Factor"].default_value = 0.22
    links.new(mixg.outputs[2], mixw.inputs[6]); links.new(wearramp.outputs["Color"], mixw.inputs[7])
    ao = nodes.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = 0.8; ao.samples = 8
    grime = nodes.new("ShaderNodeValToRGB"); grime.color_ramp.elements[0].position = 0.15; grime.color_ramp.elements[1].position = 0.75
    grime.color_ramp.elements[0].color = (0.35, 0.35, 0.4, 1)
    links.new(ao.outputs["AO"], grime.inputs["Fac"])
    mixa = nodes.new("ShaderNodeMix"); mixa.data_type = 'RGBA'; mixa.blend_type = 'MULTIPLY'; mixa.inputs["Factor"].default_value = 0.7
    links.new(mixw.outputs[2], mixa.inputs[6]); links.new(grime.outputs["Color"], mixa.inputs[7])
    links.new(mixa.outputs[2], bsdf.inputs["Base Color"])
    return m


# ---------- the light: our sun, a soft sky ----------
sun_data = bpy.data.lights.new("sun", 'SUN'); sun_data.energy = 1.4; sun_data.angle = math.radians(6)
sun = bpy.data.objects.new("sun", sun_data); bpy.context.collection.objects.link(sun)
sun.rotation_euler = (-LIGHT).to_track_quat('-Z', 'Y').to_euler()   # a sun shines along its -Z
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
bg = world.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.42, 0.48, 0.58, 1.0); bg.inputs[1].default_value = 1.9   # the sky fill: the shadow side must stay stone, not black

# ---------- build, unwrap, bake ----------
atlas = bpy.data.images.new("pillar_atlas", ATLAS, ATLAS); atlas.generated_color = (0, 0, 0, 1)
stone = stone_material()
lows = []
sizes = {}
for (name, h, fn) in VARIANTS:
    blocks, deco = fn(h)
    low = make_object("pillar_" + name, lambda bm, b=blocks: stack(bm, b), chamfer=CHAMFER)
    high = make_object("high_" + name, lambda bm, b=blocks: stack(bm, b), chamfer=CHAMFER * 0.6)
    apply_mods(high)
    deco(high)
    high.data.materials.append(stone)
    apply_mods(low)
    low.data.materials.append(bpy.data.materials.new("bake_" + name))
    lm = low.data.materials[0]; lm.use_nodes = True
    tex = lm.node_tree.nodes.new("ShaderNodeTexImage"); tex.image = atlas; lm.node_tree.nodes.active = tex
    lows.append((low, high, name, h))
    d = low.dimensions
    sizes[name] = [d.x, d.z, d.y]   # Godot's (x, y up, z)

# One atlas: every low mesh unwrapped, then all islands packed together.
bpy.ops.object.select_all(action='DESELECT')
for (low, high, name, h) in lows:
    low.select_set(True)
bpy.context.view_layer.objects.active = lows[0][0]
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
bpy.ops.uv.pack_islands(margin=0.012)
bpy.ops.object.mode_set(mode='OBJECT')

scene.render.bake.use_selected_to_active = True
scene.render.bake.cage_extrusion = 0.2
scene.render.bake.max_ray_distance = 0.45
scene.render.bake.use_clear = False
scene.render.bake.margin = 6
first = True
for (low, high, name, h) in lows:
    bpy.ops.object.select_all(action='DESELECT')
    high.select_set(True); low.select_set(True)
    bpy.context.view_layer.objects.active = low
    scene.render.bake.use_clear = first
    first = False
    bpy.ops.object.bake(type='COMBINED', pass_filter={'DIRECT', 'INDIRECT', 'COLOR', 'DIFFUSE'})
    print("baked", name, "tris low", len(low.data.polygons))
atlas.filepath_raw = os.path.join(OUT, "pillar_atlas.png"); atlas.file_format = 'PNG'; atlas.save()

# Export the low meshes, one GLB each, Y up, at the origin (base at y = 0).
for (low, high, name, h) in lows:
    bpy.data.objects.remove(high, do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT'); low.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "pillar_%s.glb" % name), use_selection=True,
                              export_format='GLB', export_yup=True, export_apply=True, export_materials='NONE',
                              export_normals=True, export_texcoords=True)
json.dump({"atlas": "pillar_atlas.png", "sizes": sizes, "light": list(LIGHT_GODOT)}, open(os.path.join(OUT, "kit.json"), "w"), indent=1)
print("KIT DONE", OUT, sizes)
