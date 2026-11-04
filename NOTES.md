# linux-compat notes

zsh layer for macOS Terminal that makes Linux/bash commands work. Written on Windows, never run
on a Mac by me; the user's friend tests it (`linuxcompat test`, then `linuxcompat debug on`).

## Decisions (asked the user, 2026-11-02)
- Scope: GNU-vs-BSD flags, package managers, Linux-only tools, bash-only syntax. All four.
- Hybrid: use Homebrew's GNU tool (gsed, ggrep...) when installed, else translate flags for BSD.
- Silent, with `linuxcompat debug on` to show translations.
- Homebrew assumed OK; installer offers it.
- No C (the user meant: don't write to the C: drive, see ../CLAUDE.md). Everything is zsh, plus perl
  one-liners (perl ships with macOS) for timeout/head -n -N/shuf/readlink fallback.

## Layout
- `linux-compat.zsh` loader (sourced from ~/.zshrc), `linuxcompat` command, state files in `state/`
  (debug, disabled, gnu-everywhere) so bin/ scripts see debug too.
- `lib/gnu.zsh` wrappers: `functions[name]="_lc_run name"`; translators fill `$reply` (argv),
  reply[1] may be `_lc_impl_*` for pipelines. `sudo` wrapper reuses the translators.
  Defined via `functions[...]`, not `name()`, because oh-my-zsh aliases `ls`/`grep` and `name()` would
  hit "defining function based on alias".
- `lib/datetr.zsh` GNU `date -d` strings -> BSD `-j -f` / `-v` / `-r`.
- `lib/bashcompat.zsh` options, read/shopt/mapfile/history, PS1, accept-line rewrite of `${x,,}` etc.
- `bin/` Linux-only commands, appended to PATH. Multi-name scripts use `${0:t}`; the installer makes
  the symlinks (apt-get -> apt, service -> systemctl, md5sum -> sha256sum, ...).

## Test mode (try.sh), added 2026-11-04
- The friend didn't want ~/.zshrc touched. `sh try.sh` runs `zsh -i` with `ZDOTDIR=<folder>/try`.
  `try/.zshenv` and `try/.zshrc` source the user's real files (read only), set HISTFILE inside
  the folder, source linux-compat.zsh, restore ZDOTDIR for child processes, and add a yellow
  prompt marker in precmd. `--clean` skips the user's .zshrc.
- try.sh makes the bin/ symlinks in the folder itself (listed in .gitignore). `LC_TRY=1` makes
  `linuxcompat uninstall` refuse to run and `status` say "test shell".
- Banner printed by try.sh, not .zshrc (p10k instant prompt complains about output during init).
- Docker check: fake HOME snapshot (ls --full-time + md5) identical before/after; user alias,
  prompt and .zshenv were loaded; --clean drops them; folder path with a space works.

## Gotchas
- Never `local x` twice in one function without a value: zsh prints the existing value.
- `status` is read-only in zsh (alias of `$?`); don't use it as a variable.
- `emulate -L zsh` in `shopt` would undo its own setopt, so shopt has none.
- Prompts containing `%` are zsh prompts (p10k, omz) and are never converted.

## Testing
- `tests/run-tests.zsh`: translations + fake-brew package/systemctl tests + interactive bash-habit
  tests run on any zsh (Linux too); live tests only on macOS (GNU mode and forced BSD mode).
- No zsh on this PC: run it in Docker (`alpine:3.22` + `apk add zsh perl bash`), project mounted
  read-only and copied in. 2026-11-02: 126/126 pass; GNU mode smoke-tested with a fake
  HOMEBREW_PREFIX whose g* files are wrapper scripts (not symlinks: Alpine's coreutils is one
  multi-call binary that dispatches on argv[0], so a `gdate` symlink breaks). Installer dry-run with
  a fake `uname` printing Darwin. The macOS live tests have NOT run yet; that's the friend's job.
- Bug found that way: `_lc_build` returned its last `[[ ]] &&` status, so wrappers silently did nothing.
  Now `reply` empty = failure, and tr_is checks the status.
- Package for the friend: `..\LinuxCompat-1.0.0.tar.gz` (rebuild with tar --exclude=state).
