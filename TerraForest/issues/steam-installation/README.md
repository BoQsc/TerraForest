# Steam installation consistency

- Status: Artwork filename/timing correction installed; engineering checks pass, visible appearance pending. Entry/link checks pass; game launch/reopen unreported.
- Updated: 2026-11-04. Initial discovery-only fix: `cb73d62b`; complete default/logging fix: `39a4c1d7`.
- User review: 2026-11-04: initially "Seems alright" with a second-computer log, then reported missing artwork in Steam. User scoped this follow-up to artwork; metadata work is excluded for now.
- Symptom: The same copied checkout produced different installation results on another Windows computer.

## Images

No screenshot supplied or generated. Stored-file/Shell-link checks did not establish
Steam artwork visibility. The user's report supersedes the earlier broad installation
conclusion; visible artwork acceptance is pending.

## Changes and verification

Confirmed causes: Last World/artwork were opt-in; desktop creation independently
searched accounts and compared launch options as exact text, so harmless quoting
differences (including project paths without spaces) selected direct execution.
First-time accounts needed an existing shortcuts file. Each entry was written in
its own Steam restart; writes were based on data read before Steam's final flush.
Launcher output, installer output and summary history went to three files; returned
failure codes could be logged as success and stderr/import failures were missing.

The default now installs both entries, their artwork and two Steam-routed desktop
links. One account/file is used throughout; the active/recent account can have no
existing `shortcuts.vdf`. One batch is merged after shutdown, backed up and checked
after restart. Both desktop links are read back and their stored protocol targets
and arguments verified. Incomplete registration stops with an error.

One `steam/logs/install.log` captures dependencies, stdout/stderr, exceptions, the
actual return code, selected paths/account, installer hash, Steam entries and link
targets. Legacy GUI/history content is absorbed before removing those extra files.
Copy log in the window copies the current/latest run. No new dependency is used;
the changes and tests are original AI-assisted work under the code policy.

Verification: [Steam regressions](../../tests/test_steam_install.py) exercise real
temporary VDF/artwork/Windows `.lnk` writes, fresh accounts, repair from one entry
and native links, one simulated restart, shutdown-time preservation of unrelated
games, repeat installation, no-space paths, failure without fallback and one log.
The fixture mocks only process control and icon stamping; the prior live temporary
engine copy/icon/version check remains documented in `cb73d62b`.

A real default run here on 2026-11-04 exited 0, verified both live entries and both
desktop `steam://rungameid` URLs, and consolidated the logs folder to `install.log`.
Existing registration was already current, so that run needed no Steam restart.
A separate live shutdown/write/restart check then passed with exit 0: both entries,
Last World's user argument and both desktop URLs were verified after Steam reopened.
The real Tk widgets also build with Copy log and retain the failure reason.
Latest output stays in [the existing log](../../steam/logs/install.log); it is local
diagnostic output, not a versioned artifact. The full Python suite passes **62 tests**, including **34 Steam regressions**.

Second-computer evidence supplied by the user on 2026-11-04: a no-argument
`pythonw` launch from `C:\WINDOWS\system32` found the direct engine in the standard
Steam folder, selected the local account, installed two entries in one restart,
verified both afterward (three total shortcuts), copied all ten artwork files and
read back both desktop links as `steam://rungameid` URLs. The run reports
`install_to_steam code=0`. Installer SHA-256:
`1bb5b29ac0f12a7df1f9881d7ab0976747519547109e4f54aa72aae0d0ed0a27`.
This verifies the second-computer entries/desktop routing and records artwork
copies, but does not close artwork appearance. The subsequent user report rejects
that visible result. The log also does not report game launch or last-world reopen.

### Artwork timing/filename correction - 2026-11-04

Confirmed defects: the old log shows `started : Steam` before all artwork copy
lines. The client could therefore reload an empty/stale grid before those files
arrived. Both the manifest and brand also reversed capsule filenames: a portrait
was written to `<appid>.png` and a wide image to `<appid>p.png`.

The correction uses portrait `<appid>p.png` (600×900), wide `<appid>.png` (920×430),
and the existing hero/logo/icon suffixes. All ten files are installed and read back
inside the closed-Steam transaction, before restart. An artwork-only repair forces
one cache reload even if shortcut fields are unchanged. Exact-slot conflicting
JPG/JPEG images are preserved as backups; unrelated artwork is untouched. The log
records post-restart bytes, dimensions and hashes without claiming UI visibility.

Convention evidence (research only; no implementation or assets imported):
[SteamGridDB's horizontal-grid FAQ](https://www.steamgriddb.com/faq) and
[NonSteamLaunchers' artwork filename implementation](https://github.com/moraroy/NonSteamLaunchers-On-Steam-Deck/blob/main/NSLGameScanner.py).
Changes/tests are original AI-assisted maintenance under the existing code policy.
The generated artwork itself is unchanged. Metadata changes were explicitly deferred
by the user in favor of artwork-only work.

Verification: **70 Python tests pass**, including **42 Steam regressions**. New
checks independently assert each actual filename and PNG dimensions, require all
ten images before startup, repair the old swapped layout with unchanged shortcut
bytes, refresh an existing cache, preserve conflicting/unrelated artwork, keep dry
runs read-only and reject missing artwork after restart. Generator `--check` passes:
the five source PNGs are byte-for-byte unchanged.

A live artwork-only repair here exited 0: four capsule files were corrected before
`started : Steam`, both entries survived reload, and all ten files passed the
post-restart byte/dimension/hash checks. Both desktop Steam URLs verified afterward.
The initial automated probe waited on the interactive restart dialog and was stopped
before any Steam write; the unattended `--yes` rerun above completed. Both attempts
remain in the existing single log. No Steam UI screenshot or second-computer visual
review has been obtained; these checks do not establish visible artwork acceptance.

Latest second-computer report: uninstall/reinstall through `.pyw` did not restart
Steam and artwork remained absent. Its supplied 10:17:46 log still has installer
hash `1bb5b29ac0f12a7df1f9881d7ab0976747519547109e4f54aa72aae0d0ed0a27`
and writes portrait to `<appid>.png`, wide to `<appid>p.png`. This identifies the
pre-artwork-fix runtime, whose unchanged-entry path skips the restart; it is not
evidence of running `ed48a69e`. The current Windows source hash is
`75c94353be2fd088a629528e2930d36784e2cfcd52a69c67e2b755270635bba9`.
Read-only remote verification found `origin`'s published `master` at `ed48a69e`.
Prepared and ZIP/byte-verified a four-file runtime update for delivery, with project
folder instructions, hashes and the existing code license. The `.pyw` wrapper is
unchanged; updating only that file does not update `steam/lib` implementations.
Next evidence must first establish that the corrected runtime was actually loaded.

## Remaining / resume here

Successful game launch and Last World reopen on the second computer remain
unreported. Return on launch feedback; close that remaining functional check with
successful launch from both Steam/desktop entries and a confirmed last-world
reopen. Artwork appearance also remains open: update to the artwork repair, rerun
the normal installer and inspect each entry's portrait, recent-game wide image,
hero and logo after the restart. Close only with user/actual UI confirmation;
successful copies alone are insufficient. See the correction above.

Exported builds with separate PCK/native companions still need complete deployment;
automatic discovery alone does not deploy them. Return when shipping that package,
verify companion-file completeness and both launch modes, and retain per-build
runtime notices. Non-Windows installation remains outside this tooling.

## Reproduce / history

1. Earlier default: run the installer on a copied checkout without `--last-world`;
   observe only the plain Steam entry. Desktop creation can then select native
   launch for the missing entry or a quoting/account mismatch.
2. Current safe regression: from the project root, run
   `python -u -B -m unittest discover -s tests -t tests -p "test_*.py"`.
   Fixtures protect live Steam files and player saves.
3. Current read-only installation preview:
   `python steam/lib/install_to_steam.py --dry-run --no-log`.
   Expect two Steam entries/artwork/link plans by default.

[Installer instructions](../../steam/README.md) ·
[Foundation status](../../docs/WORLD_FOUNDATION_STATUS.md)
