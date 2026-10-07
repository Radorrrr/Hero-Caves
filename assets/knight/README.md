# Knight: rigid rig and first animation pass

**For the corrected Roblox compatibility export, see [Roblox Test v2](ROBLOX_TEST_V2.md).**
Select `Knight_Roblox_Test_v2.fbx` in Studio. The original files described below
are retained for comparison; use the v2 pipeline for new Roblox exports.

Prepared from the uploaded Meshy_AI_Character_output.glb in Blender 4.3.2.
The original upload is unchanged. This is an editable first animation pass,
not an asset already connected to the Roblox game's combat controller.

## Files

- Knight_Rigged_Animated.blend: editable skeleton, packed original textures,
  named body regions and three actions. Idle is active when opened.
- Knight_Rigged_Animated.glb: portable textured model with all three animations.
- Knight_Idle.fbx, Knight_SwordAttack.fbx, Knight_Walk.fbx: one animation per
  file. Keep the supplied textures folder next to these FBX files.
- Knight_SwordAttack_Preview.mp4: preview of the first slash.
- rig-report.json / validation.json: geometry and animation checks.

## Rig and clips

4,072 triangles, unchanged geometry/UVs. The imported 23-bone auto-rig was
replaced with 17 named bones: Root, Pelvis, Torso, Head, upper arm/forearm/hand
and thigh/shin/foot on each side, and Sword parented to Hand.R.

The 95 connected components (after accounting for duplicated seam vertices)
are assigned wholly to one bone at weight 1.0, then grouped into 16 named mesh
regions. Chest/head/armor and the sword therefore move rigidly instead of
stretching under interpolated auto-weights. Joint gaps/intersections should
still be reviewed in your intended camera and combat poses; this is a first pass.

At 30 fps:
- Knight_Idle: frames 1-61, 2-second subtle breathing loop.
- Knight_Walk: frames 1-31, 1-second walk-in-place loop; no root motion.
- Knight_SwordAttack: frames 1-31, 1-second overhead slash. Windup at frame 10,
  impact pose at frame 17, return to rest at frame 31.

Open the .blend and press Space to preview Idle. For another clip, select
Knight_Rig, switch a Dope Sheet area to Action Editor and choose the named
Knight action. Set timeline end to 31 for Walk/SwordAttack. The muted NLA tracks
store all three actions for export; leave them muted when previewing the active
action so clips do not mix. Original uploads contained no animation.

## Textures

Original maps are preserved, without AI regeneration or upscaling:
- Image_0.jpg: 4096x4096 base color.
- Image_1.jpg: 2048x2048 packed metallic/roughness map.
- Image_2.jpg: 4096x4096 normal map.

The color map is already 4K. Soft painted/baked details cannot be restored just
by increasing resolution. Blender Material Preview, lighting and normal maps
also affect the apparent sharpness. Sharper stylized details need a separate
texture-authoring pass. FBX does not preserve the glTF packed-map shader setup
exactly: metallic/roughness and Roblox SurfaceAppearance may need manual setup.
The .blend/.glb retain the original material graph/map setup.

## Validation and Roblox integration

All three source actions were evaluated at every integer frame. Maximum mesh
edge-length deviation from rest was 3.554e-7 Blender units; no scale animation
is used. All 4,072 triangles remain. GLB contains all three named animations.
The attack FBX was re-imported successfully with skeleton, animated action,
4,072 triangles, and resolvable color/normal image paths. Blender's default FBX
import adds one frame of offset; its clip appears at 2-32, with the same duration.

The FBX files are starting points for Studio's model/animation import workflow.
This is a custom skinned rig, not Roblox R15, and no stock humanoid animations
are assumed compatible. Check scale, facing direction, materials and joint
hierarchy in Studio, then upload the clips using Animation Editor. Animation IDs,
combat timing/impact synchronization and runtime replacement of the existing
procedural KnightRig are not configured here. Source/exports alone do not
change the game. Phase 8 / offline progress has not begun.
