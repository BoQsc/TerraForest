# Steam installation consistency

- Status: Installation verified on the second computer; game launch/reopen still unreported.
- Updated: 2026-11-04. Initial discovery-only fix: `cb73d62b`; complete default/logging fix: `39a4c1d7`.
- User review: 2026-11-04: "Seems alright", with a successful second-computer installer log. Earlier defaults/routing/logging behavior was rejected.
- Symptom: The same copied checkout produced different installation results on another Windows computer.

## Images

No screenshot supplied or generated. This issue is verified through actual stored
Steam fields and Windows Shell-link read-back, not a visual acceptance claim.

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
This closes the previously pending second-computer installation check. The log
does not report launching gameplay or reopening the last world.

## Remaining / resume here

Successful game launch and Last World reopen on the second computer remain
unreported. Return on launch feedback; close that remaining functional check with
successful launch from both Steam/desktop entries and a confirmed last-world
reopen. Installation itself is verified by the supplied log above.

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
