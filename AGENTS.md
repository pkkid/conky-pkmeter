# Repository Guidelines

- Keep application and polling logic in Lua. Do not add helper scripts or invoke Python or another language interpreter.
- Document every Lua function with the existing two-line comment style: a short title followed by a concise description.
- Follow the existing module layout: shared code belongs in `pkm/`, widgets in `pkm/widgets/`, and user settings in `config.lua`.
- Keep changes small and consistent with nearby Lua code. Avoid new dependencies unless they are necessary.
- Review `README.md` after every change. Update it for user-facing behavior, setup, configuration, or dependency changes, and keep it short and concise.
- Validate changed Lua files with `luac -p` before finishing.
- Do not modify unrelated code or overwrite the user's uncommitted changes.
