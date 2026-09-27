# Runtime texture payloads

The four .trtex files contain the exact PNG/JPEG bytes shipped in v0.4.3. They were renamed, not resampled or recompressed. runtime_assets.gd inspects the file signature, uses Godot buffer decoders and generates mipmaps. Raw .trtex files are explicitly included in both export presets. Export itself has not been run in the build container.

The original sand payload is JPEG; the other three are PNG. See THIRD_PARTY_TEXTURES.md for the unchanged user-supplied asset provenance/rights disclaimer.
