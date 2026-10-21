# ============================================================
# THE STONE — shared by the pillar kit scripts (tools/blender/pillars.py,
# the old built-by-script kit, and tools/blender/kit.py, the pieces from
# image-to-3D): the Cycles scene, the stone material and our light. One
# copy, imported by both (2026-10-21). Nothing here is an image: nodes.
# ============================================================
import bpy, math
from mathutils import Vector

SLATE = (0.29, 0.31, 0.36)        # the stone's base colour (lit faces read #556173-ish in fog); the game tints per band
# Godot (x, y up, z) -> Blender (x, -z, y up). The game's light, toward the light.
LIGHT_GODOT = Vector((0.36, 0.8, -0.48))
LIGHT = Vector((LIGHT_GODOT.x, -LIGHT_GODOT.z, LIGHT_GODOT.y)).normalized()


def new_scene(samples):
    """An empty scene rendering with Cycles on the Mac's GPU."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = samples
    scene.cycles.device = 'GPU'
    scene.cycles.use_denoising = False
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'METAL'
    prefs.refresh_devices()
    for d in prefs.devices:
        d.use = d.type == 'METAL'
    return scene


# The stone material: grain, weathering, edge wear, grime.
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



def sun_and_sky(scene, sky=1.9, sun=1.4):
    """Our sun (the game's CreatureLight) and a soft sky fill: the shadow side must stay stone, not black."""
    sun_data = bpy.data.lights.new("sun", 'SUN'); sun_data.energy = sun; sun_data.angle = math.radians(6)
    sun = bpy.data.objects.new("sun", sun_data); bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (-LIGHT).to_track_quat('-Z', 'Y').to_euler()   # a sun shines along its -Z
    world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
    bg = world.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.42, 0.48, 0.58, 1.0); bg.inputs[1].default_value = sky   # the sky fill: the shadow side must stay stone, not black
