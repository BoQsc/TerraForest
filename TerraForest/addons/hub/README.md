# TerraForest community hub

Forge-backed community features for the created-by-us release: live chat, news
and issues pulled from public project files, and an update row that is a
placeholder on purpose. No Steam dependency; players are anonymous.

| File | Role |
|---|---|
| `config.gd` | Public Forge project id, host, room names. **Never** the secret key. |
| `identity.gd` | Anonymous nickname + tag in `user://hub/identity.json`. |
| `realtime.gd` | Forge room socket (`wss://…/api/socket?…&fmt=j`), JSON frames, reconnect. |
| `chat.gd` | Rooms (`tf/general`, `tf/world/<slot>`), presence, comment history (200 lines/room). |
| `community_panel.gd` | Overlay UI: Chat / News / Issues / Updates. |
| `hub_window.gd` | The taskbar notification-area icon, close-to-tray and the tray menu (kept alive by `WorldSession`). |
| `tray_icon.png` | 256 px square tray icon (Godot has no `.ico` loader). |
| `settings.gd` | `user://hub/settings.json`; the tray is **experimental and off by default**. |
| `feeds.gd` | Fetches `news.json` / `issues.json` from `https://forge.boqsc.eu/~/<project>/`, caches to `user://hub/`. |
| `forge_client.gd` | Small REST helper (public reads; upload/delete for tooling). |
| `publish/publish_feeds.py` | Publisher-side only: merges and uploads the two JSON feeds. |

## Messages

Chat travels as a Forge `event` with `event: "tf.chat"` and
`data: {text, nickname, room, v}`. The sender identity on the wire is the
nickname; text is capped at 400 characters and stripped of control characters.
The UI neutralises `[` / `]` so a peer cannot inject BBCode.

## Rooms

* `tf/general` – the hub lounge.
* `tf/world/<slot>` – per saved world (lowercase, room-safe characters only).

## Publishing news and issues (maintainer only)

```sh
set FORGE_KEY=fsk_...              # never commit this
python addons/hub/publish/publish_feeds.py newsletter --title "..." --body "..."
python addons/hub/publish/publish_feeds.py version --set 1.0.0-dev
python addons/hub/publish/publish_feeds.py issue --title "..." --body "..." --kind bug
python addons/hub/publish/publish_feeds.py show
```

`news.json` items may carry `latest_version`; the hub's **Updates** tab only
displays it. Nothing downloads, replaces or restarts the game.

Note: Forge answers `301` and files that are not published yet redirect the same
way; the hub always shows the error text instead of a blank tab and falls back
to the cached copy when one exists.

## Checks

```sh
godot --headless --path . --script res://tests/check_hub.gd              # offline
godot --headless --path . --script res://tests/check_hub.gd -- --hub-live
godot --headless --path . --script res://tests/check_hub_chat_live.gd
godot --headless --path . --script res://tests/check_hub_wiring.gd
```

The live checks need network access. They create `tf/check` and `tf/check-2`
rooms on the public project, and `check_hub_chat_live.gd` posts one message to
`tf/general`. Two panels in one process only see each other once both are
inside the tree; the panel enables its per-frame pump deferred for that reason.

The tray has a windowed check (no `--headless`): it asserts the icon exists,
the native menu is attached, closing the window minimizes instead of quitting,
and the tray restores it:

```sh
godot --path . --script res://tests/check_hub_tray_live.gd
```

`check_hub_tray.gd` is the headless half (owner created, support detection).
