# ============================================================
# THE CREATURE, ONE TAIL (step 3, character v2, 2026-10-21; Milko picked
# docs/concept/hero/C_bright_lilac.jpg). Run headless:
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/creature_tail.py -- [render_dir]
#
# The image-to-3D model (assets/models/creature.glb, 2026-09-17) came with
# TWO tail prongs, back-left and back-right; the concept has one. This
# removes the right one (Godot +x: the side the camera does not see) the
# way creature.gd already melts the baked leg stubs: every vertex of the
# prong outside the body's fitted ellipsoid is pushed back ONTO it, and
# those vertices (and a ring around them) take the ellipsoid's own normal,
# so the spot shades as smooth round body -- no hole, no patch, the
# texture untouched. (Cutting the prong off and filling the hole left
# folds and flecks: the mesh is too irregular.) Writes the model back in
# place (git keeps the old one). With a render_dir: views of the result.
# ============================================================
import bpy, bmesh, math, os, sys
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER = ARGS[0] if ARGS else ""
PATH = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models", "creature.glb"))
# The body, fitted by eye from the bounds and the side view (Blender's
# axes: the eye looks down -y, up is +z): centre and radii.
BODY_C = Vector((0.0, -0.12, -0.02))
BODY_R = Vector((0.80, 0.86, 0.92))
SURFACE = 0.95       # the body's surface around the prong's root, in ellipsoid units (measured: 0.94-0.95)

def body_e(p):
    q = p - BODY_C
    return math.sqrt((q.x / BODY_R.x) ** 2 + (q.y / BODY_R.y) ** 2 + (q.z / BODY_R.z) ** 2)

def body_normal(p):
    q = p - BODY_C
    return Vector((q.x / BODY_R.x ** 2, q.y / BODY_R.y ** 2, q.z / BODY_R.z ** 2)).normalized()

def in_prong(p):
    return p.x > 0.15 and p.y > 0.2 and -0.7 < p.z < 0.3 and body_e(p) > SURFACE

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=PATH)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
me = ob.data
normals = [v.normal.copy() for v in me.vertices]
moved = set()
for v in me.vertices:
    if in_prong(v.co):
        v.co = BODY_C + (v.co - BODY_C) * (SURFACE / body_e(v.co))
        moved.add(v.index)
# The ring around them too, so the shading blends: every vertex sharing an
# edge with a moved one, and one step further.
near = set(moved)
for _ in range(2):
    grow = set()
    for e in me.edges:
        a, b = e.vertices
        if a in near or b in near:
            grow.add(a); grow.add(b)
    near |= grow
for i in near:
    normals[i] = body_normal(me.vertices[i].co)
me.normals_split_custom_set_from_vertices(normals)
me.update()
print("prong vertices pushed onto the body", len(moved), "smooth-shaded", len(near), "of", len(me.vertices))
bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True)
bpy.context.view_layer.objects.active = ob
bpy.ops.export_scene.gltf(filepath=PATH, use_selection=True, export_format='GLB', export_yup=True, export_apply=True,
                          export_normals=True)
print("CREATURE DONE", PATH)

if RENDER:
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.color_type = 'TEXTURE'
    sc.render.resolution_x = sc.render.resolution_y = 500
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 2.4
    sc.world = bpy.data.worlds.new("w")
    for name, p in {"top": (0, 0.01, 3), "back": (0, 3, 0), "side_right": (3, 0, 0), "back_right": (2.2, 2.2, 0.6)}.items():
        cam.location = Vector(p)
        cam.rotation_euler = (Vector((0, 0, 0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(RENDER, "tail_%s.png" % name)
        bpy.ops.render.render(write_still=True)
