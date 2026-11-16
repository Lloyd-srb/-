# Wolf mesh tooling (offline)

Used to check the owner's imported wolf model without Roblox Studio.

```
# 1. What is in the FBX: triangles, bones, textures
python3 tools/wolfmesh/fbxinfo.py assets/wolf/Moonfang_Stalker_mixamo.fbx

# 2. Which bone controls which part of the mesh (skin weights)
python3 tools/wolfmesh/weights.py assets/wolf/Moonfang_Stalker_mixamo.fbx

# 3. Export the skeleton fixture used by tests, and the skin for previews
python3 tools/wolfmesh/export.py assets/wolf/Moonfang_Stalker_mixamo.fbx \
    tests/fixtures/moonfang_skeleton.json /tmp/skin.json

# 4. Solve the game's animations on that skeleton with the game's own code,
#    then draw each pose (front + side view)
lune run tools/wolfmesh/poses.luau /tmp/poses.json
python3 tools/wolfmesh/render.py /tmp/skin.json /tmp/poses.json /tmp/renders
```

`export.py` and `render.py` need numpy and Pillow. The bone mapping lives in
`Config.WolfRig.Mesh`; `tests/WolfMesh.spec.luau` checks it against the fixture.
