# linux-compat: lets Linux/bash commands work in macOS zsh.
# Sourced from ~/.zshrc by the installer. See README.md.

[[ -n $ZSH_VERSION ]] || return 0

typeset -g LC_VERSION=1.0.0
typeset -g LC_HOME=${${(%):-%x}:A:h}
source $LC_HOME/lib/common.zsh
[[ -d $LC_STATE ]] || mkdir -p $LC_STATE

# Homebrew on PATH, so apt -> brew works even if the user never ran `brew shellenv`.
if [[ -x $HOMEBREW_PREFIX/bin/brew ]] && (( ! $+commands[brew] )); then
  eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"
fi

linuxcompat() {
  emulate -L zsh
  local f
  case $1 in
    debug)
      case $2 in
        on)  : >| $LC_STATE/debug; print "linux-compat: debug on (translations are shown dimmed)";;
        off) rm -f $LC_STATE/debug; print "linux-compat: debug off";;
        *)   _lc_debug_on && print on || print off;;
      esac;;
    gnu-everywhere)
      case $2 in
        on)  : >| $LC_STATE/gnu-everywhere; print "linux-compat: GNU tools first on PATH for all programs (open a new tab)";;
        off) rm -f $LC_STATE/gnu-everywhere; print "linux-compat: GNU tools only in this shell (open a new tab)";;
        *)   [[ -e $LC_STATE/gnu-everywhere ]] && print on || print off;;
      esac;;
    install-gnu)
      _lc_brew install coreutils gnu-sed grep findutils gnu-tar gawk bash wget watch;;
    off) : >| $LC_STATE/disabled; print "linux-compat: disabled for new shells (\`linuxcompat on\` to re-enable)";;
    on)  rm -f $LC_STATE/disabled; print "linux-compat: enabled for new shells";;
    status)
      print "linux-compat $LC_VERSION ($LC_HOME)"
      print "  enabled:        $([[ -e $LC_STATE/disabled ]] && print no || print yes)"
      print "  debug:          $(_lc_debug_on && print on || print off)"
      print "  gnu-everywhere: $([[ -e $LC_STATE/gnu-everywhere ]] && print on || print off)"
      print "  homebrew:       ${HOMEBREW_PREFIX:-not installed}"
      local -a have miss
      for f in sed grep date stat readlink find xargs tar awk ls; do
        _lc_gnu_bin $f >/dev/null && have+=($f) || miss+=($f)
      done
      print "  GNU tools:      ${have:-none}"
      (( $#miss )) && print "  BSD fallback:   $miss  (\`linuxcompat install-gnu\` for exact GNU behaviour)"
      ;;
    test) zsh $LC_HOME/tests/run-tests.zsh "${@:2}";;
    uninstall) zsh $LC_HOME/uninstall.sh;;
    *)
      print "usage: linuxcompat status | debug on|off | gnu-everywhere on|off | install-gnu | on | off | test | uninstall";;
  esac
}

[[ -e $LC_STATE/disabled ]] && return 0

# Linux-only commands (apt, systemctl, free, ...). Appended, so real tools always win.
(( ${path[(Ie)$LC_HOME/bin]} )) || path+=($LC_HOME/bin)

if [[ -e $LC_STATE/gnu-everywhere ]] && __lc_gp=$(_lc_gnu_path); then
  path=(${(s.:.)__lc_gp} $path)
  unset __lc_gp
fi

source $LC_HOME/lib/datetr.zsh
source $LC_HOME/lib/gnu.zsh
source $LC_HOME/lib/bashcompat.zsh
