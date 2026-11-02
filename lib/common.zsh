# linux-compat: helpers shared by the interactive shell and the bin/ scripts.

typeset -g LC_HOME=${LC_HOME:-${${(%):-%x}:A:h:h}}
typeset -g LC_STATE=${LC_STATE:-$LC_HOME/state}

# Homebrew prefix (Apple Silicon first, then Intel).
if [[ -z $HOMEBREW_PREFIX ]]; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    typeset -gx HOMEBREW_PREFIX=/opt/homebrew
  elif [[ -x /usr/local/bin/brew ]]; then
    typeset -gx HOMEBREW_PREFIX=/usr/local
  fi
fi

# True when debug logging is on (state file, so bin/ scripts see it too).
_lc_debug_on() { [[ -e $LC_STATE/debug ]] }

# Debug line on stderr, dimmed. Silent unless debug is on.
_lc_log() {
  _lc_debug_on || return 0
  print -ru2 -- $'\e[2m[linux-compat] '"$*"$'\e[0m'
}

# Log a translated command line (array name in $1), quoted so it can be copy-pasted.
_lc_log_cmd() {
  _lc_debug_on || return 0
  local -a __c; __c=("${(@P)1}")
  _lc_log "→ ${(j: :)${(@q-)__c}}"
}

# Error message styled like the Linux tool would print it.
_lc_err() { print -ru2 -- "$*" }

# GNU binary for a tool, if Homebrew installed one: gsed, ggrep, gdate...
# Prints the path and returns 0, or returns 1.
_lc_gnu_bin() {
  [[ -n $HOMEBREW_PREFIX && -x $HOMEBREW_PREFIX/bin/g$1 ]] || return 1
  print -r -- $HOMEBREW_PREFIX/bin/g$1
}

# bin/ scripts: hand over to the real GNU tool when Homebrew installed it.
_lc_exec_gnu() {
  local g
  g=$(_lc_gnu_bin $1) || return 0
  shift
  _lc_log "→ ${g:t} $*"
  exec $g "$@"
}

# Directories with un-prefixed GNU tools (used for running Linux scripts).
_lc_gnu_path() {
  emulate -L zsh
  [[ -n $HOMEBREW_PREFIX ]] || return 1
  local -a dirs; local f
  for f in coreutils gnu-sed grep findutils gnu-tar gawk gnu-which make; do
    [[ -d $HOMEBREW_PREFIX/opt/$f/libexec/gnubin ]] && dirs+=($HOMEBREW_PREFIX/opt/$f/libexec/gnubin)
  done
  (( $#dirs )) || return 1
  print -r -- ${(j.:.)dirs}
}

# Run brew as the real user even under sudo (brew refuses to run as root).
_lc_brew() {
  local brew=${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/bin/brew}
  if [[ -z $brew || ! -x $brew ]]; then
    _lc_err "linux-compat: Homebrew is required for this command. Install it from https://brew.sh"
    return 127
  fi
  if (( EUID == 0 )) && [[ -n $SUDO_USER ]]; then
    _lc_log "→ sudo -u $SUDO_USER brew $*"
    command sudo -u $SUDO_USER $brew "$@"
  else
    _lc_log "→ brew $*"
    $brew "$@"
  fi
}
