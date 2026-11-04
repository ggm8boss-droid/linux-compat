# linux-compat test shell (started by try.sh). Loads your own .zshenv, read only.
[[ -f $LC_TRY_USER_ZDOTDIR/.zshenv ]] && source $LC_TRY_USER_ZDOTDIR/.zshenv
ZDOTDIR=$LC_TRY_DIR/try     # in case your .zshenv sets ZDOTDIR: keep reading try/.zshrc
