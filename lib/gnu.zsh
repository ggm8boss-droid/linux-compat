# Wrappers for commands that exist on macOS but take different flags (GNU vs BSD).
#
# For each wrapped tool:
#   1. if Homebrew's GNU version is installed (gsed, ggrep, gdate, ...), use it as-is;
#   2. otherwise translate the GNU flags to the BSD ones (_lc_tr_<tool>).
# Tools in _lc_always have no GNU twin and are always translated.
#
# Every translator fills $reply with the command line to run; reply[1] is a
# command name, or an _lc_impl_* function for things a single command can't do.
# A translator that can't translate prints the error and leaves reply empty;
# its exit status is not used.

typeset -gA _lc_g _lc_wrapped
typeset -ga _lc_always=(ps netstat hostname uptime top zcat)

# Build the real command line for `name args...` into $reply. Fails if reply is empty.
_lc_build() {
  local name=$1; shift
  reply=()
  if (( ${_lc_always[(Ie)$name]} )); then
    _lc_tr_$name "$@"
  elif (( $+_lc_g[$name] )); then
    reply=($_lc_g[$name] "$@")
    if [[ $name == (ls|grep) && -z ${(M)@:#--colo(u|)r*} ]]; then
      reply[2,1]=(--color=auto)
    fi
    # oh-my-zsh aliases `ls -G` (BSD colour); for GNU ls -G means --no-group
    if [[ $name == ls ]]; then
      local -i k
      for (( k = 2; k <= $#reply; k++ )); do
        [[ $reply[k] == -- ]] && break
        [[ $reply[k] == -G ]] && reply[k]=--color=auto
      done
    fi
  elif (( $+functions[_lc_tr_$name] )); then
    _lc_tr_$name "$@"
  else
    reply=($name "$@")
  fi
  (( $#reply ))
}

_lc_run() {
  emulate -L zsh
  setopt extended_glob
  local name=$1; shift
  local -a reply orig
  orig=($name "$@")
  _lc_build $name "$@" || return 1
  [[ ${(j: :)${(q)reply}} != ${(j: :)${(q)orig}} ]] && _lc_log_cmd reply
  if [[ $reply[1] == _lc_impl_* ]]; then
    "${reply[@]}"
  else
    command "${reply[@]}"
  fi
}

# ---------------------------------------------------------------- sed

_lc_tr_sed() {
  local a rest c
  reply=(sed)
  while (( $# )); do
    a=$1; shift
    case $a in
      --) reply+=(-- "$@"); return 0;;
      --in-place)        reply+=(-i '');;
      --in-place=*)      reply+=(-i "${a#*=}");;
      --regexp-extended) reply+=(-E);;
      --quiet|--silent)  reply+=(-n);;
      --unbuffered)      reply+=(-l);;
      --expression=*)    reply+=(-e "${a#*=}");;
      --expression)      reply+=(-e "$1"); shift;;
      --file=*)          reply+=(-f "${a#*=}");;
      --file)            reply+=(-f "$1"); shift;;
      --posix|--debug|--sandbox|--follow-symlinks|-s|--separate) ;;
      -[^-]*)
        rest=${a#-}
        while [[ -n $rest ]]; do
          c=$rest[1]; rest=$rest[2,-1]
          case $c in
            i)   reply+=(-i "$rest"); rest=;;      # GNU: -iSUFFIX, plain -i = no backup
            r|E) reply+=(-E);;
            e|f) if [[ -n $rest ]]; then reply+=(-$c "$rest"); else reply+=(-$c "$1"); shift; fi
                 rest=;;
            s)   ;;
            *)   reply+=(-$c);;
          esac
        done;;
      *) reply+=("$a");;
    esac
  done
}

# ---------------------------------------------------------------- grep

# Perl regex -> POSIX ERE for the common cases (\d \s \w, lazy quantifiers). Result in REPLY.
_lc_pcre2ere() {
  local p=$1 o= c n
  local -i i=1 inb=0 first=0
  while (( i <= $#p )); do
    c=$p[i]
    if [[ $c == '\' ]] && (( i < $#p )); then
      n=$p[i+1]; (( i += 2 ))
      if (( inb )); then
        case $n in
          d) o+='0-9';; s) o+='[:space:]';; w) o+='[:alnum:]_';; *) o+="\\$n";;
        esac
      else
        case $n in
          d) o+='[0-9]';;       D) o+='[^0-9]';;
          s) o+='[[:space:]]';; S) o+='[^[:space:]]';;
          w) o+='[[:alnum:]_]';; W) o+='[^[:alnum:]_]';;
          *) o+="\\$n";;
        esac
      fi
      first=0
      continue
    fi
    if (( inb )); then
      if [[ $c == '[' && $p[i+1] == (:|.|=) ]]; then        # [:alpha:] inside a bracket
        n=${p[i,-1]%%(:|.|=)\]*}
        o+="$n$p[i+$#n,i+$#n+1]"; (( i += $#n + 2 )); first=0; continue
      fi
      if (( first )) && [[ $c == '^' ]]; then o+=$c; (( i++ )); continue; fi
      [[ $c == ']' ]] && (( ! first )) && inb=0
      first=0
    elif [[ $c == '[' ]]; then
      inb=1; first=1
    elif [[ $c == '?' && $o[-1] == [*+?\}] ]]; then           # lazy quantifier
      (( i++ )); continue
    fi
    o+=$c; (( i++ ))
  done
  REPLY=$o
}

_lc_tr_grep() {
  local a rest c v REPLY
  local -i pcre=0 have_e=0 ppos=0 i icase=0 rec=0 npos=0
  local -a out pidx
  while (( $# )); do
    a=$1; shift
    case $a in
      --) out+=(--)
          if (( $# )); then out+=("$@"); (( ppos )) || ppos=$(( $#out - $# + 1 )); (( npos += $# )); fi
          break;;
      --perl-regexp)  pcre=1; out+=(-E);;
      --regexp=*)     out+=(-e "${a#*=}"); pidx+=($#out); have_e=1;;
      --regexp)       out+=(-e "$1"); shift; pidx+=($#out); have_e=1;;
      --file=*)       have_e=1; out+=("$a");;
      --file)         have_e=1; out+=("$a" "$1"); shift;;
      --recursive|--dereference-recursive) rec=1; out+=("$a");;
      --initial-tab|-T|--no-ignore-case) ;;
      -[^-]*)
        rest=${a#-}; v=-
        while [[ -n $rest ]]; do
          c=$rest[1]; rest=$rest[2,-1]
          case $c in
            P) pcre=1; v+=E;;
            T) ;;
            [efmABCdD])
              [[ $v != - ]] && out+=($v); v=-
              if [[ -n $rest ]]; then out+=(-$c "$rest"); rest=; else out+=(-$c "$1"); shift; fi
              [[ $c == e ]] && pidx+=($#out)
              [[ $c == [ef] ]] && have_e=1;;
            [rR]) rec=1; v+=$c;;
            *) v+=$c;;
          esac
        done
        [[ $v != - ]] && out+=($v);;
      *) out+=("$a"); (( ppos )) || ppos=$#out; (( npos++ ));;
    esac
  done
  (( ! have_e && ppos )) && pidx+=($ppos)
  # GNU grep -r with no path searches "."; BSD grep would read stdin.
  (( rec && npos - ! have_e <= 0 )) && out+=(.)
  if (( pcre )); then
    for i in $pidx; do
      if [[ $out[i] == '(?i)'* ]]; then out[i]=${out[i]#'(?i)'}; icase=1; fi
      _lc_pcre2ere "$out[i]"; out[i]=$REPLY
    done
    (( icase )) && out[1,0]=(-i)
  fi
  reply=(grep)
  [[ -z ${(M)out:#--colo(u|)r*} ]] && reply+=(--color=auto)
  reply+=("${out[@]}")
}

# ---------------------------------------------------------------- ls

_lc_tr_ls() {
  local a rest c v color=auto
  reply=(ls)
  while (( $# )); do
    a=$1; shift
    case $a in
      --) reply+=(-- "$@"); break;;
      --colo(u|)r|--colo(u|)r=(always|yes|force)) color=always;;
      --colo(u|)r=(auto|tty|if-tty))              color=auto;;
      --colo(u|)r=(never|no|none))                color=never;;
      --all)              reply+=(-a);;
      --almost-all)       reply+=(-A);;
      --human-readable)   reply+=(-h);;
      --reverse)          reply+=(-r);;
      --recursive)        reply+=(-R);;
      --directory)        reply+=(-d);;
      --inode)            reply+=(-i);;
      --size)             reply+=(-s);;
      --classify|--file-type) reply+=(-F);;
      --numeric-uid-gid)  reply+=(-n);;
      --dereference)      reply+=(-L);;
      --full-time)        reply+=(-lT);;
      --sort=size)        reply+=(-S);;
      --sort=time)        reply+=(-t);;
      --sort=none)        reply+=(-f);;
      --hide|--ignore|--time-style|--block-size|--quoting-style|--indicator-style) shift;;
      --*) ;;                                   # GNU-only cosmetics (--group-directories-first, ...)
      -[^-]*)
        rest=${a#-}; v=-
        while [[ -n $rest ]]; do
          c=$rest[1]; rest=$rest[2,-1]
          case $c in
            [XNZ]) ;;
            U) v+=f;;
            I) [[ -z $rest ]] && shift; rest=;;
            *) v+=$c;;
          esac
        done
        [[ $v != - ]] && reply+=($v);;
      *) reply+=("$a");;
    esac
  done
  case $color in
    always) reply=(env CLICOLOR_FORCE=1 ls -G "${(@)reply[2,-1]}");;
    auto)   reply[2,1]=(-G);;
  esac
}

# ---------------------------------------------------------------- date

_lc_tr_date() {
  local a d= have_d=0 utc=0
  local -a out opts
  while (( $# )); do
    a=$1; shift
    case $a in
      -d|--date)  d=$1; have_d=1; shift;;
      --date=*)   d=${a#*=}; have_d=1;;
      -d*)        d=${a#-d}; have_d=1;;
      -u|--utc|--universal) opts+=(-u);;
      -I|--iso-8601|--iso-8601=date)  out=(+%Y-%m-%d);;
      -Ih*|--iso-8601=hours)          out=(+%Y-%m-%dT%H%z);;
      -Im*|--iso-8601=minutes)        out=(+%Y-%m-%dT%H:%M%z);;
      -Is*|--iso-8601=seconds)        out=(+%Y-%m-%dT%H:%M:%S%z);;
      -In*|--iso-8601=ns)             out=(+%Y-%m-%dT%H:%M:%S,000000000%z);;
      -R|--rfc-2822|--rfc-email)      out=(+'%a, %d %b %Y %H:%M:%S %z');;
      --rfc-3339=date)                out=(+%Y-%m-%d);;
      --rfc-3339=*)                   out=(+'%Y-%m-%d %H:%M:%S%z');;
      -r|--reference) opts+=(-r "$1"); shift;;
      --reference=*)  opts+=(-r "${a#*=}");;
      +*)  out=("$a");;
      *)   opts+=("$a");;
    esac
  done
  # %N (nanoseconds) isn't supported by BSD date.
  if [[ $out[1] == *%N* ]]; then
    out[1]=${out[1]//\%N/$(perl -MTime::HiRes=time -e 'printf "%09d", (time - int time) * 1e9')}
  fi
  reply=(date $opts)
  if (( have_d )); then
    local -a reply_save=($reply)
    if ! _lc_date_args "$d"; then
      _lc_err "date: invalid date '$d'"
      reply=(); return 1
    fi
    reply=($reply_save $reply)
  fi
  reply+=($out)
}

# ---------------------------------------------------------------- stat

_lc_stat_fmt() {      # GNU stat format -> BSD stat -f format. Result in REPLY.
  local f=$1 o= c
  local -i i=1
  local -A M
  M=(n %N N %N s %z U %Su G %Sg u %u g %g a %OLp A %Sp Y %m X %a Z %c W %B
     y %Sm x %Sa z %Sc w %SB F %HT h %l i %i b %b B 512 d %d o %k f %Xp t %Hr T %Lr % %%)
  while (( i <= $#f )); do
    c=$f[i]
    if [[ $c == % ]] && (( i < $#f )); then
      (( i++ )); c=$f[i]
      o+=${M[$c]-%$c}
    else
      o+=$c
    fi
    (( i++ ))
  done
  REPLY=$o
}

_lc_tr_stat() {
  local a fmt= REPLY
  local -i printf=0 fs=0
  local -a files opts
  while (( $# )); do
    a=$1; shift
    case $a in
      -c|--format) fmt=$1; shift;;
      -c*)         fmt=${a#-c};;
      --format=*)  fmt=${a#*=};;
      --printf)    fmt=$1; printf=1; shift;;
      --printf=*)  fmt=${a#*=}; printf=1;;
      -L|--dereference) opts+=(-L);;
      -f|--file-system) fs=1;;
      -t|--terse) ;;
      --) files+=("$@"); break;;
      *) files+=("$a");;
    esac
  done
  if (( fs )); then reply=(df -P "${files[@]}"); return 0; fi
  reply=(stat $opts)
  if [[ -n $fmt ]]; then
    (( printf )) && { fmt=${(g::)fmt}; reply+=(-n) }
    _lc_stat_fmt "$fmt"
    reply+=(-t '%Y-%m-%d %H:%M:%S %z' -f "$REPLY")
  else
    reply+=(-x)
  fi
  reply+=(-- "${files[@]}")
}

# ---------------------------------------------------------------- readlink

typeset -g _lc_readlink_f
_lc_tr_readlink() {
  local a
  local -i canon=0 nonl=0
  local -a files
  for a; do
    case $a in
      --canonicalize*|-[fem]|-[fem]n|-n[fem]) canon=1; [[ $a == *n* ]] && nonl=1;;
      -n|--no-newline) nonl=1;;
      -[qsvz]|--quiet|--silent|--verbose|--zero) ;;
      *) files+=("$a");;
    esac
  done
  if (( ! canon )); then
    reply=(readlink); (( nonl )) && reply+=(-n); reply+=("${files[@]}"); return 0
  fi
  if [[ -z $_lc_readlink_f ]]; then         # macOS 12.3+ has readlink -f
    command readlink -f / &>/dev/null && _lc_readlink_f=1 || _lc_readlink_f=0
  fi
  if (( _lc_readlink_f )); then
    reply=(readlink -f); (( nonl )) && reply+=(-n)
    reply+=("${files[@]}")
  elif (( nonl )); then
    reply=(perl -MCwd=abs_path -e 'print join "\n", map { abs_path($_) // $_ } @ARGV' -- "${files[@]}")
  else
    reply=(perl -MCwd=abs_path -le 'print abs_path($_) // $_ for @ARGV' -- "${files[@]}")
  fi
}

# ---------------------------------------------------------------- find

_lc_tr_find() {
  local a fmt REPLY
  local -i ere=0
  local -a pre expr
  while [[ $1 == -[HLP] ]]; do pre+=($1); shift; done
  [[ $1 == -O[0-9]# ]] && shift
  [[ $1 == -D ]] && shift 2
  # GNU find defaults to "." when no path is given; BSD find requires one.
  if (( ! $# )) || [[ $1 == ([-\(\!]*|\)) ]]; then expr+=(.); fi
  while (( $# )); do
    a=$1; shift
    case $a in
      -regextype)   shift; ere=1;;
      -executable)  expr+=(-perm +111);;
      -readable)    expr+=(-perm +444);;
      -writable)    expr+=(-perm +222);;
      -mount)       expr+=(-xdev);;
      -wholename)   expr+=(-path);;
      -iwholename)  expr+=(-ipath);;
      -printf|-fprintf)
        [[ $a == -fprintf ]] && shift
        fmt=$1; shift
        case $fmt in
          '%p\n') expr+=(-print);;
          '%p\0') expr+=(-print0);;
          '%f\n') expr+=(-exec basename {} \;);;
          *)                                     # rebuild it as a stat -f format
            # find letters -> GNU stat letters (find %u/%g are names, %U/%G numbers)
            fmt=${fmt//\%U/$'\1'}; fmt=${fmt//\%G/$'\2'}
            fmt=${fmt//\%u/%U}; fmt=${fmt//\%g/%G}
            fmt=${fmt//$'\1'/%u}; fmt=${fmt//$'\2'/%g}
            fmt=${fmt//\%T@/%Y}; fmt=${fmt//\%t/%y}; fmt=${fmt//\%f/%n}; fmt=${fmt//\%p/%n}
            fmt=${fmt//\%m/%a}; fmt=${fmt//\%M/%A}
            _lc_stat_fmt "${(g::)fmt}"
            expr+=(-exec stat -n -f "$REPLY" {} \;);;
        esac;;
      *) expr+=("$a");;
    esac
  done
  reply=(find $pre)
  (( ere )) && reply+=(-E)
  reply+=("${expr[@]}")
}

# ---------------------------------------------------------------- xargs

_lc_tr_xargs() {
  local a rest c delim=
  local -a out
  while (( $# )); do
    a=$1; shift
    case $a in
      -r|--no-run-if-empty) ;;                    # BSD never runs on empty input
      --null)           out+=(-0);;
      --verbose)        out+=(-t);;
      --interactive)    out+=(-p);;
      --max-args=*)     out+=(-n "${a#*=}");;
      --max-lines=*)    out+=(-L "${a#*=}");;
      --max-procs=*)    out+=(-P "${a#*=}");;
      --replace)        out+=(-I '{}');;
      --replace=*)      out+=(-I "${a#*=}");;
      -i)               out+=(-I '{}');;
      -i*)              out+=(-I "${a#-i}");;
      -l)               out+=(-L 1);;
      -d|--delimiter)   delim=$1; shift;;
      -d*)              delim=${a#-d};;
      --delimiter=*)    delim=${a#*=};;
      -[^-]*)
        rest=${a#-}
        while [[ -n $rest ]]; do
          c=$rest[1]; rest=$rest[2,-1]
          case $c in
            r) ;;
            [nLPIsEJ]) if [[ -n $rest ]]; then out+=(-$c "$rest"); rest=; else out+=(-$c "$1"); shift; fi;;
            *) out+=(-$c);;
          esac
        done;;
      *) out+=("$a" "$@"); break;;            # the command and its args
    esac
  done
  if [[ -n $delim ]]; then
    reply=(_lc_impl_xargs_d "${(g::)delim}" "${out[@]}")
  else
    reply=(xargs "${out[@]}")
  fi
}

_lc_impl_xargs_d() {      # xargs -d DELIM: split stdin on DELIM, then xargs -0
  local d=$1; shift
  command tr "$d" '\0' | command xargs -0 "$@"
}

# ---------------------------------------------------------------- du / df

_lc_tr_du() {
  local a rest c v
  reply=(du)
  while (( $# )); do
    a=$1; shift
    case $a in
      --) reply+=(-- "$@"); break;;
      --max-depth=*)     reply+=(-d "${a#*=}");;
      --max-depth)       reply+=(-d "$1"); shift;;
      --summarize)       reply+=(-s);;
      --human-readable|--si) reply+=(-h);;
      --apparent-size|-b|--bytes) reply+=(-A);;
      --total)           reply+=(-c);;
      --all)             reply+=(-a);;
      --one-file-system) reply+=(-x);;
      --dereference)     reply+=(-L);;
      --exclude=*)       reply+=(-I "${a#*=}");;
      --exclude)         reply+=(-I "$1"); shift;;
      --block-size=[Kk]*|-BK|-Bk) reply+=(-k);;
      --block-size=[Mm]*|-BM|-Bm) reply+=(-m);;
      --block-size=[Gg]*|-BG|-Bg) reply+=(-g);;
      --time*|--block-size=*|-B*) ;;
      *) reply+=("$a");;
    esac
  done
}

_lc_tr_df() {
  local a rest c v
  reply=(df)
  while (( $# )); do
    a=$1; shift
    case $a in
      --) reply+=(-- "$@"); break;;
      --human-readable)   reply+=(-h);;
      --si)               reply+=(-H);;
      --inodes)           reply+=(-i);;
      --local)            reply+=(-l);;
      --portability)      reply+=(-P);;
      --type=*)           reply+=(-T "${a#*=}");;
      --exclude-type=*)   reply+=(-T "no${a#*=}");;
      -t)                 reply+=(-T "$1"); shift;;
      -x)                 reply+=(-T "no$1"); shift;;
      --print-type|--total|--output*|--sync|--no-sync|--all) ;;
      -[^-]*)
        rest=${a#-}; v=-
        while [[ -n $rest ]]; do
          c=$rest[1]; rest=$rest[2,-1]
          [[ $c == T ]] || v+=$c          # GNU -T = print type; BSD -T = filter
        done
        [[ $v != - ]] && reply+=($v);;
      *) reply+=("$a");;
    esac
  done
}

# ---------------------------------------------------------------- head / tail

_lc_tr_head() {
  local a n= mode=
  local -a out files
  while (( $# )); do
    a=$1; shift
    case $a in
      --lines=*)   out+=(-n "${a#*=}");;
      --bytes=*)   out+=(-c "${a#*=}");;
      -n|--lines)  out+=(-n "$1"); shift;;
      -c|--bytes)  out+=(-c "$1"); shift;;
      -n*|-c*)     out+=(${a[1,2]} "${a[3,-1]}");;
      -[0-9]*)     out+=(-n "${a#-}");;
      -q|-v|--quiet|--silent|--verbose) ;;
      --) files+=("$@"); break;;
      *) files+=("$a");;
    esac
  done
  # GNU: -n -N / -c -N = everything except the last N
  if [[ $out[-1] == -[0-9]* ]]; then
    n=${out[-1]#-}
    if [[ $out[-2] == -c ]]; then
      reply=(perl -0777 -ne 'BEGIN { $n = shift } print substr($_, 0, length($_) - $n) if length($_) > $n' -- "$n" "${files[@]}")
    else
      reply=(perl -ne 'BEGIN { $n = shift } push @b, $_; print shift @b if @b > $n' -- "$n" "${files[@]}")
    fi
    return 0
  fi
  reply=(head "${out[@]}" "${files[@]}")
}

_lc_tr_tail() {
  local a
  reply=(tail)
  while (( $# )); do
    a=$1; shift
    case $a in
      --) reply+=(-- "$@"); break;;
      --lines=*)  reply+=(-n "${a#*=}");;
      --bytes=*)  reply+=(-c "${a#*=}");;
      --lines)    reply+=(-n "$1"); shift;;
      --bytes)    reply+=(-c "$1"); shift;;
      --follow|--follow=descriptor) reply+=(-f);;
      --follow=name) reply+=(-F);;
      --retry|--pid=*|--sleep-interval=*|-z|--zero-terminated|--verbose|-v) ;;
      -s|--pid|--sleep-interval) shift;;
      *) reply+=("$a");;
    esac
  done
}

# ---------------------------------------------------------------- cp / mv

_lc_tr_cpmv() {
  local tool=$1 a target=
  shift
  local -a out
  while (( $# )); do
    a=$1; shift
    case $a in
      --) out+=(-- "$@"); break;;
      -t|--target-directory) target=$1; shift;;
      --target-directory=*)  target=${a#*=};;
      -T|--no-target-directory|--strip-trailing-slashes) ;;
      --no-clobber)   out+=(-n);;
      --recursive)    out+=(-R);;
      --archive)      out+=(-a);;
      --verbose)      out+=(-v);;
      --force)        out+=(-f);;
      --interactive)  out+=(-i);;
      --preserve*)    out+=(-p);;
      --no-dereference) out+=(-P);;
      --dereference)  out+=(-L);;
      --reflink*)     out+=(-c);;             # APFS clone
      *) out+=("$a");;
    esac
  done
  reply=($tool "${out[@]}")
  [[ -n $target ]] && reply+=("$target")
}
_lc_tr_cp() { _lc_tr_cpmv cp "$@" }
_lc_tr_mv() { _lc_tr_cpmv mv "$@" }

# ---------------------------------------------------------------- base64 / touch

_lc_tr_base64() {
  local a
  reply=(base64)
  while (( $# )); do
    a=$1; shift
    case $a in
      -d|--decode)         reply+=(-D);;
      -w|--wrap)           reply+=(-b "$1"); shift;;
      -w*)                 reply+=(-b "${a#-w}");;
      --wrap=*)            reply+=(-b "${a#*=}");;
      -i|--ignore-garbage) ;;
      -di|-id)             reply+=(-D);;
      -)                   ;;
      -*)                  reply+=("$a");;
      *)                   reply+=(-i "$a");;
    esac
  done
}

_lc_tr_touch() {
  local a d=
  local -i have_d=0
  local -a out
  while (( $# )); do
    a=$1; shift
    case $a in
      -d|--date)      d=$1; have_d=1; shift;;
      --date=*)       d=${a#*=}; have_d=1;;
      --reference=*)  out+=(-r "${a#*=}");;
      --reference)    out+=(-r "$1"); shift;;
      --no-create)    out+=(-c);;
      --no-dereference) out+=(-h);;
      --time=access|--time=atime|--time=use) out+=(-a);;
      --time=modify|--time=mtime) out+=(-m);;
      --) out+=(-- "$@"); break;;
      *) out+=("$a");;
    esac
  done
  if (( have_d )); then
    if ! _lc_date_args "$d"; then
      _lc_err "touch: invalid date format '$d'"
      reply=(); return 1
    fi
    d=$(command date "${reply[@]}" +%Y%m%d%H%M.%S) || { reply=(); return 1 }
    out[1,0]=(-t "$d")
  fi
  reply=(touch "${out[@]}")
}

# ---------------------------------------------------------------- ps / top / netstat

_lc_tr_ps() {
  local a k
  reply=(ps)
  while (( $# )); do
    a=$1; shift
    case $a in
      --sort|--sort=*)
        if [[ $a == --sort ]]; then k=$1; shift; else k=${a#*=}; fi
        case ${k%%,*} in
          (-|+|)(%mem|pmem|rss|vsz|size)) reply+=(-m);;
          (-|+|)(%cpu|pcpu|cpu|time))     reply+=(-r);;
        esac;;
      --forest|--no-headers|--headers|-H) ;;
      --pid|-q)        reply+=(-p "$1"); shift;;
      --pid=*)         reply+=(-p "${a#*=}");;
      --user|--User)   reply+=(-u "$1"); shift;;
      -[^-]#o|--format|-O) [[ $a == --format ]] && a=-o
                       reply+=("$a" "${1//cmd/command}"); shift;;     # -o, -eo, -axo ...
      --format=*)      reply+=(-o "${${a#*=}//cmd/command}");;
      -C)              reply=(_lc_impl_ps_C "$1"); return 0;;
      *) reply+=("$a");;
    esac
  done
}

_lc_impl_ps_C() {         # ps -C name: processes with that exact name
  local pids; pids=$(command pgrep -x -- "$1" | command paste -sd, -)
  [[ -n $pids ]] || { command ps -o pid,tty,time,comm -p 0 2>/dev/null | command head -1; return 1 }
  command ps -o pid,tty,time,comm -p "$pids"
}

_lc_tr_top() {
  local a k
  local -i batch=0
  local -a out
  while (( $# )); do
    a=$1; shift
    case $a in
      -b|--batch) batch=1;;
      -n)  out+=(-l "$1"); shift;;
      -n*) out+=(-l "${a#-n}");;
      -d)  out+=(-s "${1%.*}"); shift;;
      -u|-U) out+=(-U "$1"); shift;;
      -p)  out+=(-pid "${1%%,*}"); shift;;
      -o)  k=${(L)${1#[+-]}}; shift
           case $k in %cpu|cpu) k=cpu;; %mem|mem|res|rss) k=mem;; time*) k=time;; esac
           out+=(-o "$k");;
      -c|-i|-H|-S) ;;
      *) out+=("$a");;
    esac
  done
  if (( batch )) && [[ -z ${(M)out:#-l} ]]; then out+=(-l 1); fi
  reply=(top "${out[@]}")
}

_lc_tr_netstat() {
  local a flags=
  # Linux-style clusters only: -tulpn, -tlnp, -antp, ...
  for a; do
    case $a in
      -p|-f|-I|-w) reply=(netstat "$@"); return 0;;   # macOS netstat syntax, leave it
      -[^-]*) flags+=${a#-};;
      *) reply=(netstat "$@"); return 0;;
    esac
  done
  if [[ $flags == *l* || $flags == *p* ]]; then
    reply=(lsof -nP)
    [[ $flags == *t* || $flags != *u* ]] && reply+=(-iTCP)
    [[ $flags == *l* ]] && reply+=(-sTCP:LISTEN)
    [[ $flags == *u* || $flags != *t* ]] && reply+=(-iUDP)
  elif [[ $flags == *t* && $flags != *u* ]]; then
    reply=(netstat -an -p tcp)
  elif [[ $flags == *u* && $flags != *t* ]]; then
    reply=(netstat -an -p udp)
  else
    reply=(netstat "$@")
  fi
}

# ---------------------------------------------------------------- hostname / uptime / zcat

_lc_tr_hostname() {
  case $1 in
    -I|--all-ip-addresses|-i|--ip-address) reply=(_lc_impl_ips);;
    --fqdn|--long|-A|--all-fqdns) reply=(hostname -f);;
    --short) reply=(hostname -s);;
    *) reply=(hostname "$@");;
  esac
}

_lc_impl_ips() {          # Linux prints every address on one line with a trailing space
  emulate -L zsh
  setopt extended_glob
  local line out=
  for line in ${(f)"$(command ifconfig)"}; do
    [[ $line == [[:space:]]#inet\ * ]] || continue
    line=${${line##[[:space:]]#inet }%% *}
    [[ $line == 127.* ]] && continue
    out+="$line "
  done
  print -r -- "$out"
}

_lc_tr_uptime() {
  case $1 in
    -p|--pretty) reply=(_lc_impl_uptime p);;
    -s|--since)  reply=(_lc_impl_uptime s);;
    *) reply=(uptime "$@");;
  esac
}

_lc_impl_uptime() {
  emulate -L zsh
  zmodload -F zsh/datetime p:EPOCHSECONDS
  local bt=${${$(command sysctl -n kern.boottime)#*sec = }%%,*}
  local -i up=$(( EPOCHSECONDS - bt )) w d h m
  local -a parts
  if [[ $1 == s ]]; then
    command date -r $bt '+%Y-%m-%d %H:%M:%S'; return
  fi
  (( w = up / 604800, d = up % 604800 / 86400, h = up % 86400 / 3600, m = up % 3600 / 60 ))
  (( w )) && parts+=("$w week${${w:#1}:+s}")
  (( d )) && parts+=("$d day${${d:#1}:+s}")
  (( h )) && parts+=("$h hour${${h:#1}:+s}")
  parts+=("$m minute${${m:#1}:+s}")
  print -r -- "up ${(j:, :)parts}"
}

_lc_tr_zcat() { reply=(gzip -dc "$@") }      # macOS zcat wants .Z files

# ---------------------------------------------------------------- sudo

# sudo runs real binaries, so translate the command it's given too.
function sudo {
  emulate -L zsh
  setopt extended_glob
  local -a opts reply
  local name
  while [[ $1 == -* ]]; do
    case $1 in
      --) opts+=($1); shift; break;;
      -[ugpChrtUD]|--user|--group|--prompt|--close-from|--host|--role|--type|--other-user|--chdir)
        opts+=($1 $2); shift 2;;
      *) opts+=($1); shift;;
    esac
  done
  if (( ! $# )) || [[ -n ${(M)opts:#(-[a-zA-Z]#[slivkKe][a-zA-Z]#|--shell|--login|--list|--validate|--edit|--reset-timestamp)} ]]; then
    command sudo "${opts[@]}" "$@"; return
  fi
  name=$1
  case $name in
    apt|apt-get|apt-cache|aptitude|yum|dnf|pacman|zypper|snap|apk|brew)
      _lc_log "dropping sudo: Homebrew must not run as root"
      "$@"; return;;
  esac
  if (( $+_lc_wrapped[$name] )); then
    shift
    _lc_build $name "$@" || return
    if [[ $reply[1] == _lc_impl_* ]]; then "${reply[@]}"; return; fi
    reply[1]=${commands[$reply[1]]:-$reply[1]}
    _lc_log "→ sudo ${(j: :)${(@q-)reply}}"
    command sudo "${opts[@]}" "${reply[@]}"; return
  fi
  # Our Linux-only tools: sudo's PATH may not include our bin/.
  if [[ ${commands[$name]} == $LC_HOME/bin/* ]]; then
    shift; command sudo "${opts[@]}" ${commands[$name]} "$@"; return
  fi
  command sudo "${opts[@]}" "$@"
}

# ---------------------------------------------------------------- define the wrappers

() {
  local t
  for t in sed grep ls date stat readlink find xargs du df head tail cp mv base64 touch \
           sort cut wc tr split mktemp tar awk $_lc_always; do
    if (( ! ${_lc_always[(Ie)$t]} )) && [[ -n $HOMEBREW_PREFIX && -x $HOMEBREW_PREFIX/bin/g$t ]]; then
      _lc_g[$t]=$HOMEBREW_PREFIX/bin/g$t
    elif (( ! $+functions[_lc_tr_$t] )); then
      continue                          # no GNU binary and nothing to translate
    fi
    _lc_wrapped[$t]=1
    functions[$t]="_lc_run $t \"\$@\""
  done
}
