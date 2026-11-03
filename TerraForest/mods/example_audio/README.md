# Example sound replacement

This data-only pack makes walking on grass quieter and uses one NOX variant.
Merge into `user://mods/enabled.cfg`, then restart the world:

```ini
[audio]
manifests=PackedStringArray("res://mods/example_audio/pack.audio.module.json")
```

The pack declares its dependency and explicitly replaces `nox.step.grass.walk`.
Remove the entry to restore the bundled sound. Other surfaces remain available.
To install your own loose pack, use `user://mods/<your-pack>/...` instead.
WAV/Ogg files require no editor import; scripts, scenes and PCKs are not admitted
through the audio data loader. This is a restricted loader, not an OS sandbox.

Original metadata: CC0-1.0. Recording: Nox_Sound_Design, CC0-1.0.
See [retained notice](../../addons/audio_runtime/packs/nox/NOTICE.txt) and
[file provenance](../../addons/audio_runtime/packs/nox/provenance.json).
