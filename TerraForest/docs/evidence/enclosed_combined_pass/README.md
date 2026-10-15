# Enclosed combined route and corrected height diagnosis

The original published checkpoint had canonical hash
36f7a3803944c4b71607c3de1d12990ec85a04b4e13754c11b02bd421b574195
and player spawn (811.5,49.1,1299). Later review-save hash
d35b2a41e518a19caeda9829f98fc6ffc0acf07c79e5db1a11b4dc61df5c6fdd
contains three remaining doors and a player around Y79.5. The previous diagnosis
mistook that changed player position for a building floor. No author of those
external save changes is inferred. The review save remains preserved.

Direct awaited terrain queries under all three remaining doors and four street
midpoints show terrain Y47, doors Y49. Generator4/seed1703 and identity terrain
transform restore correctly. No runtime height correction was warranted.

The retained generation stage combined_stage_d877dea2eec84388a81c3208eb14788b
was cloned and tested with run_combined_resource_route.py --source. All three
processes pass: actual E gathering, recipe UI, earned-brick placement, chest
deposit/withdraw; walking through an interacted door, car placement/entry,
keyboard drive 9.08 m and reverse/stop (return error1.92 m), walking back; exact
inventory, chest, vegetation removals, placed brick and door snapshot reopening.
Source hash remains unchanged. Display is fullscreen1920x1080/cap60.

The route relocates between gathering and chest stages; it does not prove a
continuous gather-to-house walk, large travel, actor routes, thermals or sustained
frame performance. Initial streamed receive hitches remain in logs. Door state
is verified after travel; other cottage doors remain unchanged.
