# linux-compat test shell (started by try.sh).
# Your own ~/.zshrc is sourced (read only) so the shell feels like yours, then linux-compat
# is loaded from this folder. Nothing here writes outside the folder.

if [[ $LC_TRY_CLEAN != 1 && -f $LC_TRY_USER_ZDOTDIR/.zshrc ]]; then
  source $LC_TRY_USER_ZDOTDIR/.zshrc
fi

# Keep test commands out of your real history file.
HISTFILE=$LC_TRY_DIR/try/.zsh_history

source $LC_TRY_DIR/linux-compat.zsh

# Programs started from here (another zsh, vim, ...) should see your normal ZDOTDIR.
if [[ -n $LC_TRY_OLD_ZDOTDIR ]]; then export ZDOTDIR=$LC_TRY_OLD_ZDOTDIR; else unset ZDOTDIR; fi

# Mark the prompt so it's obvious which shell this is (re-added if a theme rebuilds it).
_lc_try_mark() {
  [[ $PROMPT == *'[linux-compat test]'* ]] || PROMPT="%F{yellow}[linux-compat test]%f $PROMPT"
}
precmd_functions+=(_lc_try_mark)
