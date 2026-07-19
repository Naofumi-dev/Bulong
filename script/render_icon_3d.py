# Renders Bulong's 3D app icon with Blender (headless):
#   blender -b -P script/render_icon_3d.py -- <out_dir>
#
# Produces:
#   icon_master_1024.png — dark squircle tile + glossy mint whisper-orb
#                          + emissive waveform bars (full app icon)
#   logo_master_1024.png — orb + bars alone on transparency (brand/menu logo)
#
# Design language mirrors the app: ink #0C1210 tile, mint #2BDEB1 accent,
# orb-with-waveform mark (the HUD's orb, made physically real).

import bpy
import math
import sys

out_dir = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "/tmp"

MINT = (0.169, 0.871, 0.694, 1.0)        # 2BDEB1
MINT_DEEP = (0.055, 0.42, 0.33, 1.0)
INK = (0.0045, 0.0085, 0.0075, 1.0)      # tile base, green-tinted near-black

scene = bpy.context.scene

# ---- clean slate -----------------------------------------------------------
for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)

# ---- materials -------------------------------------------------------------
def principled(name, color, metallic=0.0, rough=0.4, coat=0.0,
               emission=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    coat_input = bsdf.inputs.get("Coat Weight")
    if coat_input is not None:
        coat_input.default_value = coat
    if emission is not None:
        emit_color = bsdf.inputs.get("Emission Color")
        emit_strength = bsdf.inputs.get("Emission Strength")
        if emit_color is not None and emit_strength is not None:
            emit_color.default_value = emission
            emit_strength.default_value = emission_strength
    return mat

tile_mat = principled("Tile", INK, metallic=0.0, rough=0.52)
orb_mat = principled("Orb", MINT, metallic=0.0, rough=0.26, coat=0.9)
bar_mat = principled("Bar", MINT, rough=0.35,
                     emission=MINT, emission_strength=1.6)
bar_dim_mat = principled("BarDim", MINT_DEEP, rough=0.35,
                         emission=MINT_DEEP, emission_strength=0.8)

# ---- squircle tile ---------------------------------------------------------
# Full-thickness cube sunk below z=0 so the corner bevel isn't clamped by a
# thin slab — this is what actually produces the big rounded macOS corners.
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, -0.5))
tile = bpy.context.active_object
tile.name = "Tile"
tile.scale = (0.82, 0.82, 0.5)
bpy.ops.object.transform_apply(scale=True)
bevel = tile.modifiers.new("Bevel", "BEVEL")
bevel.width = 0.4
bevel.segments = 48
bevel.profile = 0.68
tile.data.materials.append(tile_mat)
bpy.ops.object.shade_smooth()

# ---- whisper orb -----------------------------------------------------------
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.36, location=(0, 0.0, 0.34),
                                     segments=96, ring_count=64)
orb = bpy.context.active_object
orb.name = "Orb"
orb.data.materials.append(orb_mat)
bpy.ops.object.shade_smooth()

# ---- waveform bars (capsules crossing in FRONT of the orb) -----------------
bars = []
bar_spec = [  # x offset, half-height, bright?
    (-0.42, 0.15, False),
    (-0.21, 0.25, True),
    (0.00, 0.38, True),
    (0.21, 0.25, True),
    (0.42, 0.15, False),
]
for i, (x, h, bright) in enumerate(bar_spec):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, location=(x, 0.0, 0.88),
                                         segments=48, ring_count=32)
    bar = bpy.context.active_object
    bar.name = f"Bar{i}"
    bar.scale = (0.068, h, 0.068)
    bpy.ops.object.transform_apply(scale=True)
    bar.data.materials.append(bar_mat if bright else bar_dim_mat)
    bpy.ops.object.shade_smooth()
    bars.append(bar)

# ---- lights ----------------------------------------------------------------
def area_light(name, loc, rot, energy, size, color=(1, 1, 1)):
    bpy.ops.object.light_add(type="AREA", location=loc, rotation=rot)
    light = bpy.context.active_object
    light.name = name
    light.data.energy = energy
    light.data.size = size
    light.data.color = color
    return light

area_light("Key", (2.2, 1.6, 4.0), (math.radians(-18), math.radians(24), 0),
           320, 2.4, (1.0, 0.98, 0.95))
area_light("Rim", (-3.0, -0.8, 2.2), (math.radians(12), math.radians(-42), 0),
           260, 2.0, (0.42, 1.0, 0.85))
area_light("Fill", (0.2, -2.6, 3.2), (math.radians(32), 0, 0),
           90, 3.0, (0.85, 0.92, 1.0))

world = bpy.data.worlds.new("IconWorld")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.01, 0.016, 0.014, 1.0)
bg.inputs[1].default_value = 0.1

# ---- camera ----------------------------------------------------------------
bpy.ops.object.camera_add(location=(0, 0, 7.2), rotation=(0, 0, 0))
cam = bpy.context.active_object
cam.data.lens = 90
scene.camera = cam

# ---- render settings -------------------------------------------------------
scene.render.engine = "CYCLES"
scene.cycles.samples = 160
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.render.resolution_x = 1024
scene.render.resolution_y = 1024
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
try:
    scene.cycles.device = "GPU"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for device in prefs.devices:
        device.use = True
except Exception:
    scene.cycles.device = "CPU"

# ---- render 1: full icon ---------------------------------------------------
scene.render.filepath = f"{out_dir}/icon_master_1024.png"
bpy.ops.render.render(write_still=True)

# ---- render 2: logo only (hide tile, tighter camera) -----------------------
tile.hide_render = True
cam.data.lens = 70
scene.render.filepath = f"{out_dir}/logo_master_1024.png"
bpy.ops.render.render(write_still=True)

print("RENDER_DONE")
