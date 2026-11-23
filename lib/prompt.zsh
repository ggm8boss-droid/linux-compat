# Git Bash style prompt (same look as WinLinuxCompat's):
#
#   user@host MINGW64 ~/some/path (branch)
#   $
#
# Reads .git itself (no git process per prompt). The branch goes through psvar (%9v), never
# into the prompt text, so a branch named `$(...)` can't run even with PROMPT_SUBST on.
#
# Modes (state files, new tabs):  auto (default) = only replaces the stock macOS/zsh prompt,
# so oh-my-zsh / powerlevel10k / a custom PROMPT are kept;  `linuxcompat prompt on` = always
# (state/prompt-on);  `linuxcompat prompt off` = never (state/noprompt).
# LC_PROMPT_TAG changes the purple word (default MINGW64, like Git Bash's $MSYSTEM).

# "branch" / "branch|MERGING" / "(1a2b3c4...)" for the repo containing $1, in REPLY ('' outside one).
_lc_git_head() {
  emulate -L zsh
  setopt extended_glob
  REPLY=
  local d=${1:-$PWD} g= l h s= b r
  while :; do
    if [[ -f $d/.git/HEAD ]]; then g=$d/.git; break; fi
    if [[ -f $d/.git ]]; then          # worktree / submodule: ".git" is a file "gitdir: <path>"
      IFS= read -r l < $d/.git 2>/dev/null
      if [[ $l == gitdir:* ]]; then
        g=${${l#gitdir:}## #}
        [[ $g == /* ]] || g=$d/$g
      fi
      break
    fi
    [[ $d == / || -z $d ]] && break
    d=${d:h}
  done
  [[ -n $g && -f $g/HEAD ]] || return 0
  IFS= read -r h < $g/HEAD 2>/dev/null

  # in-progress operations, same names as Git Bash (git-prompt.sh)
  for r in rebase-merge rebase-apply; do
    if [[ -d $g/$r ]]; then
      s='|REBASE'
      if [[ -f $g/$r/head-name ]]; then
        IFS= read -r l < $g/$r/head-name
        [[ $l == refs/* ]] && h="ref: $l"
      fi
      break
    fi
  done
  if [[ -z $s ]]; then
    if   [[ -e $g/MERGE_HEAD ]];       then s='|MERGING'
    elif [[ -e $g/CHERRY_PICK_HEAD ]]; then s='|CHERRY-PICKING'
    elif [[ -e $g/REVERT_HEAD ]];      then s='|REVERTING'
    elif [[ -e $g/BISECT_LOG ]];       then s='|BISECTING'
    fi
  fi

  if   [[ $h == 'ref: refs/heads/'* ]]; then b=${h#ref: refs/heads/}
  elif [[ $h == 'ref: '* ]];            then b=${h#ref: }
  elif (( ${#h} >= 7 ));                then b="(${h[1,7]}...)"      # detached HEAD
  else return 0
  fi
  REPLY=$b$s
}

# The stock prompts we may replace in auto mode: macOS /etc/zshrc, zsh's built-in, empty.
_lc_prompt_is_stock() {    # [prompt], default $PROMPT
  local p=${1-$PROMPT}
  [[ -z $p || $p == '%n@%m %1~ %# ' || $p == '%m%# ' ]]
}

() {
  local tag=${LC_PROMPT_TAG:-MINGW64} title=
  tag=${tag//\%/%%}
  # window title "MINGW64:/full/path", like Git Bash; not on dumb terminals
  [[ $TERM != (dumb|) ]] && title=$'%{\e]0;'"$tag"$':%/\a%}'
  typeset -g _lc_prompt=$title$'\n%F{green}%n@%m %F{magenta}'"$tag"$' %F{yellow}%~%F{cyan}%(9V. (%9v).)%f\n$ '
}

typeset -g _lc_prompt_force=
[[ -e $LC_STATE/prompt-on ]] && _lc_prompt_force=1

_lc_prompt_precmd() {
  local REPLY
  _lc_git_head $PWD 2>/dev/null
  psvar[9]=$REPLY             # %9V is false when it's empty
  # forced mode wins over themes that rewrite PROMPT before every prompt (p10k, omz)
  if [[ -n $_lc_prompt_force && $PROMPT != $_lc_prompt ]]; then PROMPT=$_lc_prompt; RPROMPT=; fi
}

if [[ -n $_lc_prompt_force ]] || _lc_prompt_is_stock; then
  PROMPT=$_lc_prompt
  [[ -n $_lc_prompt_force ]] && RPROMPT=
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _lc_prompt_precmd     # after bashcompat's _lc_precmd (sourced first)
fi
