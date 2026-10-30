# Boot splash

`boot_splash.png` preserves Godot's original 800 x 600 splash artwork at native
size, centered on a transparent 1920 x 1080 canvas. The footer reads
**TerraForest • Open source**, centered near the bottom in 26 px Segoe UI.
Godot supplies its default dark background. Keep-aspect stretching matches the
project's 1920 x 1080 presentation and preserves the image proportions on other
window sizes; the footer margin scales with the image.

Rebuild on Windows using `powershell -NoProfile -File tools/build_boot_splash.ps1`
from the project directory. The retained input is
`source/godot-default.png`, copied from Godot's `main/splash.png`; the source
directory is excluded from Godot imports. No generated or redrawn logo is used.
The retained source PNG matches the image embedded in the installed Godot 4.7.2
engine (SHA-256: `54bf3f11d3e71c76e44f7012c4a8d27ecfd035f63f7c159adc00c182a0c3f932`).

The Godot logo is copyright 2017 Andrea Calabró, licensed under CC BY 4.0.
See `GODOT_LOGO_LICENSE.txt` for attribution, source and modification details.
Detailed reuse terms and component notices are available from **Credits & licenses**
in the world browser. The footer does not relicense Godot or its logo.
