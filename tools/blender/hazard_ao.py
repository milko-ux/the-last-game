# ============================================================
# HAZARDS: ambient occlusion baked into the clay models' vertex colours
# (brief stage B, 2026-09-24), so their recesses get depth. Through
# tools/blender/bake_all.sh:
#
#   Blender -b --python tools/blender/hazard_ao.py -- [ignored] [samples]
#
# For each light copy in assets/models/lod/ (the meshes the game draws,
# made by tools/decimate_models.py with the bake's colour in COLOR_0):
# import, bake AO to a colour attribute, multiply it into COLOR_0
# (lifted so flat areas keep their colour), export the GLB back in place.
# The clay shader (props.gd) reads COLOR, so the recesses darken with no
# shader change. Idempotent enough: the multiply is against the
# decimator's output, so re-run decimate_models.py first to start over.
# ============================================================
import bpy, os, sys, math
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SAMPLES = int(ARGS[1]) if len(ARGS) > 1 else 32
HERE = os.path.dirname(os.path.abspath(__file__))
LOD = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models", "lod"))
MODELS = ["gate_pillar", "sweeper_segment", "slammer", "orbiter_pillar", "volley_emitter"]
AO_STRENGTH = 0.75      # how much of the AO goes in (1 = full)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'; scene.cycles.samples = SAMPLES; scene.cycles.device = 'GPU'
prefs = bpy.context.preferences.addons['cycles'].preferences
prefs.compute_device_type = 'METAL'; prefs.refresh_devices()
for d in prefs.devices:
    d.use = d.type == 'METAL'
scene.render.bake.target = 'VERTEX_COLORS'

for name in MODELS:
    path = os.path.join(LOD, name + ".glb")
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete()
    bpy.ops.import_scene.gltf(filepath=path)
    obs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if not obs:
        print("AO skip", name); continue
    ob = obs[0]
    bpy.context.view_layer.objects.active = ob; ob.select_set(True)
    me = ob.data
    if "Col" not in me.color_attributes and "COLOR_0" not in me.color_attributes and len(me.color_attributes) == 0:
        print("AO no colour on", name); continue
    src = me.color_attributes[0]
    ao = me.color_attributes.new("AO", 'BYTE_COLOR', 'CORNER')
    me.color_attributes.active_color = ao
    if not me.materials:
        me.materials.append(bpy.data.materials.new("m"))
    bpy.ops.object.bake(type='AO')
    # multiply the AO into the source colour, lifted
    ao_data = me.color_attributes["AO"].data
    src_data = src.data
    n = min(len(ao_data), len(src_data))
    for i in range(n):
        a = ao_data[i].color[0]
        k = 1.0 - AO_STRENGTH * (1.0 - a)
        c = src_data[i].color
        src_data[i].color = (c[0] * k, c[1] * k, c[2] * k, c[3])
    me.color_attributes.remove(me.color_attributes["AO"])
    me.color_attributes.active_color = src
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB', export_yup=True,
                              export_apply=True, export_materials='NONE', export_normals=True, export_vertex_color='ACTIVE')
    print("AO DONE", name, "verts", len(me.vertices))
