# Godot UID sidecars

Godot's `.uid` files are resource identity metadata and belong in version control
with their source files. They are separate from the generated `.godot/` cache.

Enable this repository's pre-commit hook once per checkout:

```sh
git config --local core.hooksPath .githooks
```

Before each commit, the hook stages existing UID sidecars for staged GDScript,
shader, shader-include and GDExtension sources. It also includes newly generated,
untracked UID files whose sources are already tracked. It does not stage unrelated
source changes, import files, ignored build/report output, or loose new resources
that have not been added to Git. It does not invent missing UIDs: let Godot import
new resources before committing them.

Git does not activate cloned hooks automatically. Run the command above in each
new checkout. Explicitly bypassing hooks also bypasses this safeguard.
