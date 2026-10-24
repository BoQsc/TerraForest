# Empty hands and punching - accepted baseline for now

The user requested a commit of current work as a baseline on 2026-10-24, after
reporting that 0.72 m punching reach was impractically close. Reach is now 1.65 m;
contact timing/damage and the tools' 3.5 m reach remain unchanged. This deliberate
gameplay allowance does not extend the authored arm or claim physical contact at
all allowed distances. Historical 0.72 m measurements below describe the preceding
revision. The user subsequently stated "We accepted this for now" on 2026-10-24.
This accepts the current baseline; the known close-up mesh limitations below remain.

The first delivery was rejected for unnatural motion/keying and broken hand
deformation; its evidence is in `rejected_v1/`. The second was described as a
useful empty-hand baseline, but explicitly not accepted. The user rejected its
instant, awkward punch and said it felt like punching UI rather than the world.
That delivery is preserved in `unaccepted_v2/`. The two older videos retain their
original names and do not represent the current animation.

The third revision turns the resting hands inward with loose fingers and a small
wrist bend. The fist closes by frame 8 and the wrist straightens before driving
from frame 12 to contact at frame 28 (0.467 s). Shoulder advance, torso rotation
and a modest forward incline support a stroke that travels about 35 cm into
depth from the loaded position, with about 9 cm of upward travel. The full cycle
is 68 frames at 60 FPS (1.133 s), with withdrawal and relaxation keyed separately.
The repaired finger skin from the second revision is retained.

The first world capture exposed contact below the crosshair. The contact pose
was raised and centered; a world check now measures the striking knuckle within
7 cm of the actual hit point. Bare hands also no longer inherit the tools' 3.5 m
range. Their 0.72 m ray matches the visible arm-length strike with a small contact
allowance. The existing target, occlusion and permission checks remain in force;
damage is unchanged. Equipped tools keep their existing reach and original mesh.

`Unarmed.world-contact-v3.mp4` records a real native block in a disposable world,
from an angle where its side is visible: one normal-speed punch, then one at
half speed. It uses the normal attack/contact/damage path. Animation advances by
fixed capture increments; PNG capture throughput and background-world timing are
not a gameplay FPS benchmark. Studio stills and current reports use the `V3.*`
and `v3-*.json` names. Earlier `Reworked.*` files belong to the unaccepted v2.

Twenty-two runtime checks cover pose seams, planted root/feet, mirrored palms,
straight striking wrists, fixed closed-fist joints, depth travel, aim alignment,
skin weights, preserved mesh attributes and tool restoration. Shared timing
(27 checks), accepted pickaxe (11 checks), character runtime and targeted package
checks pass. Eighteen passing graphical world checks cover real empty-slot selection and mouse input,
one 5-damage hit at contact, no inventory wear, recovery, equip cancellation,
close-range selection and a distant air punch that cannot damage the block.
The recorded block scenario does not certify zombie/terrain motion quality at
all camera pitches or target distances.

The current revision is accepted for now by the user. Coarse knuckle creases and
shirt/shoulder clipping remain visible in close third-person views; this acceptance
does not claim those mesh/wardrobe limitations were corrected.
Rebuild details are in `addons/characters/authoring/Human.unarmed.README.md`.
