# Bash habits in interactive zsh.

setopt INTERACTIVE_COMMENTS   # `cmd  # comment` at the prompt
setopt NO_NOMATCH             # unmatched globs are passed on unchanged (scp host:*.log, URLs with ?)
setopt BSD_ECHO               # echo leaves \n alone unless -e, like bash
[[ -n ${CLICOLOR+x} ]] || export CLICOLOR=1           # coloured ls, like Linux distros

bindkey '^U' backward-kill-line                       # bash: Ctrl-U deletes to start of line

# Completion: zsh's own, plus bash completion scripts (`complete`, `compgen`).
if (( ! $+functions[compdef] )); then
  autoload -Uz compinit && compinit -i
fi
autoload -U +X bashcompinit && bashcompinit

# Bash aliases file many Linux users keep.
[[ -r ~/.bash_aliases ]] && emulate ksh -c 'source ~/.bash_aliases'

# ---------------------------------------------------------------- builtins bash has and zsh doesn't

function shopt {
  local __o __on __m=
  local -i __q=0 __rc=0
  local -A __map
  __map=(nullglob NULL_GLOB dotglob GLOB_DOTS nocaseglob NO_CASE_GLOB extglob KSH_GLOB
         autocd AUTO_CD cdspell CORRECT histappend APPEND_HISTORY histverify HIST_VERIFY
         nocasematch NO_CASE_MATCH failglob NOMATCH huponexit HUP checkjobs CHECK_JOBS
         interactive_comments INTERACTIVE_COMMENTS globstar - checkwinsize - cmdhist -
         expand_aliases - lithist - progcomp - direxpand - dirspell - extdebug -)
  while [[ $1 == -* ]]; do
    case $1 in -s) __m=s;; -u) __m=u;; -q) __q=1;; esac
    shift
  done
  if [[ -z $__m ]]; then
    for __o in ${@:-${(ko)__map}}; do
      [[ -n $__map[$__o] ]] || { print -u2 "shopt: $__o: invalid shell option name"; __rc=1; continue }
      __on=off
      if [[ $__map[$__o] == - ]]; then __on=on
      elif [[ -o $__map[$__o] ]]; then __on=on; fi
      (( __q )) || printf '%-24s%s\n' $__o $__on
      [[ $__on == on ]] || __rc=1
    done
    return $__rc
  fi
  for __o; do
    [[ -n $__map[$__o] && $__map[$__o] != - ]] || continue
    if [[ $__m == s ]]; then setopt $__map[$__o]; else unsetopt $__map[$__o]; fi
  done
}

# bash read options: -p PROMPT, -a ARRAY, -n N, -e, -i TEXT.
function read {
  local -a __a __orig=("$@")
  local __p= __c __r
  local -i __tr=0 __k=0 __u=0
  while [[ $1 == -[^-]* ]]; do
    __r=${1#-}; shift
    while [[ -n $__r ]]; do
      __c=$__r[1]; __r=$__r[2,-1]
      case $__c in
        p)     __p=${__r:-$1}; [[ -z $__r ]] && shift; __r=; __tr=1;;
        a)     __a+=(-A); __tr=1;;
        [nN])  __a+=(-k ${__r:-$1}); [[ -z $__r ]] && shift; __r=; __k=1; __tr=1;;
        e)     __tr=1;;
        i)     [[ -z $__r ]] && shift; __r=; __tr=1;;
        [tdu]) __a+=(-$__c ${__r:-$1}); [[ -z $__r ]] && shift; __r=; [[ $__c == u ]] && __u=1;;
        *)     __a+=(-$__c);;
      esac
    done
  done
  [[ $1 == -- ]] && shift
  # Nothing bash-specific: hand zsh's own read its arguments untouched.
  if (( ! __tr )); then builtin read "${__orig[@]}"; return; fi
  (( __k && ! __u )) && __a+=(-u 0)
  if [[ -n $__p ]]; then
    if (( $# )); then argv[1]="$1?$__p"; else set -- "REPLY?$__p"; fi
  fi
  builtin read "${__a[@]}" "$@"
}

# mapfile / readarray [-t] [-d DELIM] [ARRAY]  (zsh arrays still start at 1)
function mapfile readarray {
  local __d=$'\n' __n=MAPFILE __data
  while [[ $1 == -* ]]; do
    case $1 in
      -d) __d=$2; shift;;
      -[nOsuCc]) shift;;
    esac
    shift
  done
  [[ -n $1 ]] && __n=$1
  __data=$(command cat; print -n x); __data=${__data%x}; __data=${__data%$__d}
  if [[ -z $__data ]]; then set -A $__n; else set -A $__n "${(@ps:$__d:)__data}"; fi
}

# bash: `history` = everything, `history 10` = last 10, -c clears.
function history {
  case $1 in
    '')    builtin fc -l 1;;
    <->)   builtin fc -l -$1;;
    -c)    local __s=$HISTSIZE; HISTSIZE=1; HISTSIZE=$__s;;
    -w)    builtin fc -W "${@:2}";;
    -r)    builtin fc -R "${@:2}";;
    -a)    builtin fc -A "${@:2}";;
    *)     builtin fc -l "$@";;
  esac
}

(( $+aliases[run-help] )) && unalias run-help
autoload -Uz run-help
function help {
  if (( $# )); then run-help "$@"; else print "Shell builtins are documented in: man zshbuiltins"; fi
}

# ---------------------------------------------------------------- running Linux scripts

# `bash script.sh` / `sh script.sh` / `./script.sh`: Homebrew's bash if present
# (macOS ships bash 3.2), with the GNU tools first on PATH for that script only.
_lc_shell() {
  emulate -L zsh
  local sh=$1 gp; shift
  [[ $sh == bash && -n $HOMEBREW_PREFIX && -x $HOMEBREW_PREFIX/bin/bash ]] && sh=$HOMEBREW_PREFIX/bin/bash
  if gp=$(_lc_gnu_path); then
    _lc_log "→ ${sh:t} $* (GNU tools on PATH)"
    PATH=$gp:$PATH command $sh "$@"
  else
    command $sh "$@"
  fi
}
function bash { _lc_shell bash "$@" }
function sh   { _lc_shell sh "$@" }

_lc_script() {        # suffix alias target for *.sh
  local first
  IFS= read -r first < $1 2>/dev/null
  case $first in
    '#!'*bash*)                         _lc_shell bash "$@";;
    '#!'*/sh|'#!'*/sh\ *|'#!'*'env sh'*) _lc_shell sh "$@";;
    '#!'*)                              command "$@";;      # python, zsh, ...
    *)                                  _lc_shell bash "$@";;  # no shebang: bash runs it on Linux
  esac
}
alias -s sh=_lc_script

# ---------------------------------------------------------------- PS1 / PROMPT_COMMAND

typeset -g _lc_ps1_done=
_lc_ps1_from_bash() {   # bash prompt escapes -> zsh prompt escapes. Result in REPLY.
  local p=$1
  p=${p//\%/%%}
  p=${p//'\['/%\{};      p=${p//'\]'/%\}}
  p=${p//'\e'/$'\e'};    p=${p//'\033'/$'\e'}; p=${p//'\x1b'/$'\e'}; p=${p//'\a'/$'\a'}; p=${p//'\007'/$'\a'}
  p=${p//'\u'/%n};       p=${p//'\h'/%m};      p=${p//'\H'/%M}
  p=${p//'\w'/%~};       p=${p//'\W'/%1~}
  p=${p//'\$'/%(!.#.\$)}
  p=${p//'\t'/%*};       p=${p//'\T'/%D\{%I:%M:%S\}}; p=${p//'\@'/%D\{%I:%M %p\}}; p=${p//'\A'/%D\{%H:%M\}}
  p=${p//'\d'/%D\{%a %b %d\}}
  p=${p//'\j'/%j};       p=${p//'\l'/%l};      p=${p//'\!'/%h};  p=${p//'\#'/%h}
  p=${p//'\s'/zsh};      p=${p//'\v'/$ZSH_VERSION}; p=${p//'\V'/$ZSH_VERSION}
  p=${p//'\n'/$'\n'};    p=${p//'\\'/\\}
  REPLY=$p
}

typeset -g _lc_pc_inherited=$PROMPT_COMMAND     # from a parent bash: not ours to run
_lc_precmd() {
  [[ -n $PROMPT_COMMAND && $PROMPT_COMMAND != $_lc_pc_inherited ]] && eval "$PROMPT_COMMAND"
  # A bash-style PS1 (export PS1='\u@\h:\w\$ ') gets converted once.
  # Prompts with % are zsh prompts (oh-my-zsh, powerlevel10k...) and are left alone.
  if [[ $PS1 != $_lc_ps1_done && $PS1 != *%* && $PS1 == *\\[uhHwW\$]* ]]; then
    local REPLY
    _lc_ps1_from_bash "$PS1"
    [[ $REPLY == *(\$\(|\`)* ]] && setopt PROMPT_SUBST
    PS1=$REPLY; _lc_ps1_done=$REPLY
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _lc_precmd

# ---------------------------------------------------------------- bash-only expansions

# zsh can't parse ${var,,} ${var^^} ${!var} ${!arr[@]} ${!prefix*}; rewrite them
# just before the line runs. History keeps what was typed.
typeset -g _lc_typed=
_lc_bash_syntax() {
  emulate -L zsh
  setopt extended_glob
  local b=$BUFFER o='${' c='}'
  [[ $b == *'${'(\!|[^}]#(,|\^)\})* ]] || return 0
  b=${b//(#b)\$\{([A-Za-z_][A-Za-z0-9_]#)(\[[^\]]#\]|),,\}/${o}(L)${match[1]}${match[2]}${c}}
  b=${b//(#b)\$\{([A-Za-z_][A-Za-z0-9_]#)(\[[^\]]#\]|)\^\^\}/${o}(U)${match[1]}${match[2]}${c}}
  b=${b//(#b)\$\{([A-Za-z_][A-Za-z0-9_]#),\}/${o}(L)${match[1]}[1]${c}${o}${match[1]}[2,-1]${c}}
  b=${b//(#b)\$\{([A-Za-z_][A-Za-z0-9_]#)\^\}/${o}(U)${match[1]}[1]${c}${o}${match[1]}[2,-1]${c}}
  b=${b//(#b)\$\{\!([A-Za-z_][A-Za-z0-9_]#)\[[@*]\]\}/${o}(k)${match[1]}${c}}
  b=${b//(#b)\$\{\!([A-Za-z_][A-Za-z0-9_]#)[@*]\}/${o}(k)parameters[(I)${match[1]}*]${c}}
  b=${b//(#b)\$\{\!([A-Za-z_][A-Za-z0-9_]#)\}/${o}(P)${match[1]}${c}}
  if [[ $b != $BUFFER ]]; then
    _lc_typed=$BUFFER
    _lc_log "→ $b"
    BUFFER=$b
  fi
}

_lc_addhistory() {
  [[ -n $_lc_typed ]] || return 0
  print -sr -- "$_lc_typed"
  _lc_typed=
  return 1
}
add-zsh-hook zshaddhistory _lc_addhistory

zmodload zsh/zleparameter 2>/dev/null
typeset -g _lc_prev_accept=
[[ $widgets[accept-line] == user:* ]] && _lc_prev_accept=${widgets[accept-line]#user:}
_lc_accept_line() {
  _lc_bash_syntax
  if [[ -n $_lc_prev_accept ]]; then $_lc_prev_accept "$@"; else zle .accept-line; fi
}
zle -N accept-line _lc_accept_line
