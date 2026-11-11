# Flesh hit audition log

Running record of every sound auditioned for the **flesh hit** (`flesh.hit`), so nothing
declined is proposed again. Add a row whenever a candidate is heard; only the user's
verdict is authoritative.

Status now: **SFXMint flesh 02** (`fxm_flesh_02.wav`) is the shipped default for
`flesh.hit`. The user judged it the most neutral of everything heard so far and asked
for it as the default while a better sound is sought. It is *not* a final approval.

## Shipped default

| Clip | Source / licence | Note |
|---|---|---|
| `fxm_flesh_02.wav` | SFXMint, CC0 (AI-generated) | Most neutral candidate heard; 0.38 s, 44.1 kHz mono; shipped at -16 dB with a 70 ms repeat guard |

## Declined by the user (do not propose again)

| Candidate | Source / licence | Verdict |
|---|---|---|
| Critical Hit 3 (`critical_hit_3_220ms.wav`) | Kaino, CC0 | Rejected: "very bad and out of topic"; never choose for flesh again |
| Slime Squelch 1 | Kaino, CC0 | Rejected |
| Slime Squelch 2 | Kaino, CC0 | Rejected |
| Punch 1 | Kaino, CC0 | Rejected |
| Punch 3 | Kaino, CC0 | Rejected |
| Eating Crunch 1 | Kaino, CC0 | Rejected |
| Sword Stab 2 | Kaino, CC0 | Rejected |
| Stone Thud 1 | Kaino, CC0 | Rejected |
| squishsplat_impact | EZduzziteh, OGA, CC0 | Rejected |
| squishpop | EZduzziteh, OGA, CC0 | Rejected |
| squish_01 | EZduzziteh, OGA, CC0 | Rejected |
| squish_03 | EZduzziteh, OGA, CC0 | Rejected |
| Eldritch Grim "Impact" clips 1, 5, 9, 13 | OGA Impacts/Gun/sfx, CC0 | Rejected |
| Wet towel on body 01, 09, 17, 37 | qubodup, OGA, CC0 | Rejected ("so far nothing good") |
| qubodup Impact Meat 01 | qubodup, OGA, CC0 | Rejected in game: "not great at all for flesh" |
| qubodup Impact Meat 02 | qubodup, OGA, CC0 | Rejected in game: "not good enough" |
| SFXMint flesh hit 01 | SFXMint, CC0 (AI-generated) | Rejected in game: "out of topic at all for flesh" |

## Kept for testing only (not approved)

| Candidate | Source / licence | Note |
|---|---|---|
| Wet Break 8 (`flesh_hit_wet8.wav`) | Zane Little, OGA, CC0 | Previous default. Shortlisted with Wet Break 7; superseded by `fxm_flesh_02` as the shipped default |

## Heard but not chosen

| Candidate | Source / licence | Note |
|---|---|---|
| Wet Break 7 | Zane Little, OGA, CC0 | Shortlisted alongside 8; drier attack; trimmed copy at `flesh_hit_wet7.wav` |

## Awaiting verdict

**SFXMint flesh hits 01–05** ([sfxmint.com/sounds/flesh-hit](https://sfxmint.com/sounds/flesh-hit),
CC0). Purpose-built combat flesh impacts, 0.38–0.59 s, converted to 44.1 kHz mono 16-bit
in `addons/audio_runtime/packs/Kaino/1/flesh_more/sfxmint/` (`fxm_flesh_01` … `_05`).
Note: these are AI-generated per the publisher's own caption. 06, 07 and 09 are still
to fetch (the host rate-limited the batch).

**qubodup Impact — Meat 01 / 02** (qubodup, [OGA "Impact"](https://opengameart.org/content/impact),
CC0). Two recordings made specifically as *meat* impacts, 0.5 s each, converted to
44.1 kHz mono 16-bit in
`addons/audio_runtime/packs/Kaino/1/flesh_more/q_meat/`.

## Sources still to try (not yet auditioned)

- **Wet towel club/pound/hit** — qubodup, OGA, CC0 (auditioning now: see below).
- **37 hits/punches** — Independent.nu, OGA, CC0 (`.7z`; 7-Zip is available at
  `C:\Program Files\7-Zip\7z.exe`).
- **Pound of Flesh 1 / 2** — magnuswaker, Freesound, CC0 (needs a Freesound account).
- **Squelching SFX [13]** — SoundDesignForYou, Freesound, CC0 (account).
- **Blunt Force Trauma** — TheFilmLook, Freesound, CC0 (account; stabbed melons).
- **Wet Impact** — Kastenfrosch, Freesound, CC0 (account).
- **StarNinjas impacts** — OGA, CC0 (cardboard hits; judged the wrong material from the
  listing, no clip played).

## Awaiting verdict

**Wet towel on body** (qubodup, OGA) — 40 real body-impact recordings, 44.1 kHz mono,
~0.4–0.6 s each. Ten converted for listening in
`addons/audio_runtime/packs/Kaino/1/flesh_more/towel/` (`towel_01` … `towel_37`).
Heard so far: 01, 09, 17, 37.

Licence note: the archive's own `-info.txt` says MIT/ZLIB/newBSD, but the author states
on the OGA page "Available under cc0. Ignore the txt info file in the 7z that says
otherwise." Treat as CC0; record that note if the clip ships.

## Not usable

- **Fleshy Fight Sounds** — will_leamon, OGA. Purpose-made for zombie combat but
  **OGA-BY 3.0**, not CC0, so it breaks the project's public-domain-first rule.
