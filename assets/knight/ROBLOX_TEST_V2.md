# Basic Knight — Roblox Test 1, export v2

**Select `assets/knight/Knight_Roblox_Test_v2.fbx` in Studio's 3D Importer.**
This is a separate compatibility test asset, not a gameplay replacement.
The original v1 .blend, GLB, FBX clips and texture files remain unchanged.

## What was fixed

The original Blender actions had rotation/location keys and no scale keys.
However, its GLB contained **17 constant scale animation channels per clip**,
51 in total. Those exported channels explain Studio's unsupported-scale warning.
Blender's FBX exporter also generates scale curves while baking, even for unit
scale. The v2 pipeline removes only verified constant unit-scale curves and
rejects genuine scale animation rather than silently discarding it.

The old asset had **16 separate skinned mesh objects sharing one skin**, with no
explicit GLB skeleton root. The source objects already had identity transforms;
the assembled Blender model was not fixed by arbitrarily changing its proportions.
For v2 the same triangle/UV/rigid-weight data is joined into **one `Basic_Knight`
skinned mesh**, with one coherent skin and the existing 17-bone `Knight_Rig`.
The GLB now also declares the single `Root` skeleton root. This removes the
split-mesh/shared-skeleton import layout involved in the displaced Studio preview.
Local checks cannot identify Roblox's internal conversion bug with certainty;
the final assembled pose still needs to be confirmed in Studio itself.

Before joining/exporting, the pipeline clears active/NLA poses, checks identity
mesh/armature/parent-inverse matrices and applies the identity object transforms.
It preserves the original rest bones, hierarchy and whole-component weight 1.0
assignments, including `Sword -> Hand.R`. No rest pose is derived from an animated
frame. The source and joined triangle-corner signatures (positions, UVs and rigid
bone assignment) are equal. No shape keys, drivers or deformation constraints
are used. Animation is bone rotation/translation only; no scale or morph/weight
animation is exported.

FBX uses `FBX_SCALE_UNITS`, no leaf bones and no experimental space-transform bake.
Bone/object scale properties are unit scale; unit conversion belongs to FBX's
unit metadata instead of a baked animated armature scale of 100. All three takes
are sampled at 30 fps, retaining the original concepts and timings:

| Clip | Source frames | Duration |
| --- | --- | --- |
| Knight_Idle | 1–61 | 2 seconds |
| Knight_Walk | 1–31 | 1 second |
| Knight_SwordAttack | 1–31 | 1 second |

Exported clips start at time zero. Attack windup/impact/recovery retain source
frames 10/17/31. No game attack timing, Animation IDs or gameplay code was changed.

## Files

- **Knight_Roblox_Test_v2.fbx** — primary Studio test: one mesh, rig, all three takes;
  original supported base-color/normal image bytes embedded.
- **Knight_Roblox_Test_v2.glb** — independently validated alternative/comparison;
  one mesh/skin, explicit skeleton root, all three clips, no scale/weight channels.
- **Knight_Roblox_Test_v2.blend** — corrected, editable source; opens assembled
  with no active animation. Original maps remain packed. In Action Editor choose
  Knight_Idle, Knight_Walk or Knight_SwordAttack on Knight_Rig to preview a clip.
  Keep the other NLA tracks muted.
- **Knight_Roblox_Test_v2-export-report.json** — source/layout checks and removed channels.
- **Knight_Roblox_Test_v2-validation.json** — actual output-file checks and numeric errors.

FBX is primary because Studio's documented skinned-model workflow recommends FBX,
and this file passed a direct binary audit and full animation roundtrip with unit
transforms. This choice is based on the normalized rig/export, not an assumption
that changing an extension fixes the old asset. The validated GLB is supplied to
compare the same geometry/skin while preserving its complete material setup.
Reference: [Roblox export requirements](https://create.roblox.com/docs/art/modeling/export-requirements).

## Local validation performed

The validation reads the final exported files, not just their source scene:

- One mesh, one skin, 17 expected bones, 4,072 triangles; source UVs/weights retained.
- Zero scale-animation and zero weight-animation channels in **both** files.
- FBX cluster bind matrices agree with mesh/bone BindPose matrices; all skin
  vertices have one weight of 1.0. Unit scaling is verified in the raw FBX.
- Independent GLB matrix/skinning evaluation verifies each inverse bind matrix
  reconstructs the neutral pose, then numerically skins each animated frame.
- FBX is re-imported with the default bone orientation preserved; its neutral pose
  and every animation frame are compared against the original Blender source.
- **123 frames per format** checked: Idle 61, Walk 31, SwordAttack 31.
- All triangles remain; no body/armor edges change length beyond floating-point
  noise. Sword/hand relative transform remains constant throughout all clips.
- Maximum FBX source-pose difference: approximately **0.00000252 Blender units**.
  Maximum FBX edge-length change: approximately **0.000000624** units.
- Three deliberately corrupted GLBs (scale channel, displaced head inverse bind,
  sword weighted to head) are rejected, proving those validation guards can fail.

Blender's FBX importer synthesizes constant unit-scale FCurves when decomposing
its imported transforms. The validator checks they are constant/unit; it also
checks separately that no such scale curve actually exists in the exported FBX.
Do not re-export through Blender's default FBX settings: that regenerates scale
channels. Use the repeatable pipeline below.

## Exact Studio Test 1

1. Pull `main`. In a separate test place or empty test area, open **3D Importer**.
2. Choose **`assets/knight/Knight_Roblox_Test_v2.fbx`**, not the legacy GLB.
3. Keep it a normal custom skinned model; do not auto-rig/convert it to R15 or
   apply avatar body-conversion tools.
4. Inspect the preview **before playing any clip**. Head must meet torso, shoulders,
   forearms/hands, legs/feet and sword must remain in the intended assembled pose.
5. Confirm the unsupported **scale or weight animation** warning is absent.
6. Import the model; inspect Basic_Knight and the Knight_Rig/bone hierarchy.
   It is one MeshPart with skinned bone regions, not sixteen separate body MeshParts.
7. Inspect the available animation takes; they contain Knight_Idle, Knight_Walk and
   Knight_SwordAttack (FBX labels may include the `Knight_Rig|` prefix).
8. Preview Idle, then Walk, then SwordAttack using the importer/Animation Editor's
   imported animation controls. Confirm 2s/1s/1s timing and intact rigid proportions.
9. During attack windup, impact and recovery, watch head, shoulder armor, forearms,
   both hands, legs/feet and the sword. Sword must move with the right hand and
   no part should stretch, drift, grow or shrink.
10. If the importer offers take selection, check each of the three takes explicitly;
    do not infer Walk/Attack passed from a successful Idle preview.
11. Optionally import `Knight_Roblox_Test_v2.glb` separately to compare the same
    corrected skin and original full material graph. Do not import both on top of
    each other, which can create a misleading overlap.
12. Keep this test model separate from the live Knight and combat scripts.
    No gameplay integration or placeholder replacement is included in this change.

## Remaining Roblox-specific limits

No Roblox Studio runtime is available here: importer preview, Roblox animation
conversion and runtime bone playback need the manual test above. This is a custom
17-bone skeleton, not stock R15; existing humanoid animations are not assumed to fit.

The **texture images are unchanged**, including the packed metallic/roughness map.
FBX does not translate the original glTF packed metallic/roughness shader graph
exactly; Studio SurfaceAppearance may require manually assigning the unchanged
maps. Base color and normal bytes are embedded unchanged in FBX. The .blend/GLB
preserve the original full graph/maps. No texture-quality or appearance redesign
was performed.

## Repeatable pipeline

Run from the repository root with **Blender 4.3.2** (the version used here):

```sh
blender --background --disable-autoexec --python-exit-code 1 \
  assets/knight/Knight_Rigged_Animated.blend \
  --python tools/knight/export_roblox.py -- --output-dir assets/knight

blender --background --factory-startup --disable-autoexec --python-exit-code 1 \
  --python tools/knight/validate_roblox.py -- --asset-dir assets/knight
```

The exporter starts from the preserved v1 source and writes only v2 files. It
asserts the expected input structure, geometry/UV/weights and unchanged packed
texture hashes. Source and exported animation scales must remain unit scale.
The validator writes its report only after all checks pass. `--python-exit-code 1`
ensures a Python validation error makes Blender exit unsuccessfully.

No game systems, procedural placeholder, texture quality or evolution models
are changed. This is Test 1 compatibility work only.
