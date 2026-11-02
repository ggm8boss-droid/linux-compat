#!/bin/zsh
# linux-compat self-test.   zsh tests/run-tests.zsh [-v]
#   1. translations: what each Linux command line turns into (runs on any OS with zsh)
#   2. package managers / systemctl against a fake brew (any OS)
#   3. bash habits, in an interactive sub-shell (any OS)
#   4. live: really runs the translated commands (macOS only)

emulate -R zsh
setopt extended_glob
typeset -g T_HOME=${0:A:h:h}
typeset -gi T_PASS=0 T_FAIL=0 T_VERBOSE=${T_VERBOSE:-0}
[[ $1 == -v ]] && T_VERBOSE=1
export T_VERBOSE
# Own state dir, so the user's `linuxcompat debug on` doesn't add noise.
[[ $1 == --inner ]] || export LC_STATE=$(command mktemp -d)

ok()   { (( ++T_PASS )); (( T_VERBOSE )) && print -r -- "  ok   $1"; return 0 }
bad()  { (( ++T_FAIL )); print -r -- "  FAIL $1"; shift; local l; for l; do print -r -- "         $l"; done; return 0 }
same() { if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1" "got:  ${(q-)2}" "want: ${(q-)3}"; fi }

# tr CMD ARGS... :: EXPECTED ARGS...      (compares the translated argv)
tr_is() {
  local -i sep=${argv[(i)::]}
  local -a cmd=("${(@)argv[1,sep-1]}") want=("${(@)argv[sep+1,-1]}") reply
  local -i rc
  _lc_build "${cmd[@]}"; rc=$?
  if (( rc )); then
    bad "${(j: :)${(@q-)cmd}}" "translation failed (status $rc)"
  elif [[ ${(j: :)${(@q)reply}} == ${(j: :)${(@q)want}} ]]; then
    ok "${(j: :)${(@q-)cmd}}"
  else
    bad "${(j: :)${(@q-)cmd}}" "got:  ${(j: :)${(@q-)reply}}" "want: ${(j: :)${(@q-)want}}"
  fi
}

# ---------------------------------------------------------------- 1. translations

t_translations() {
  print "translations (BSD fallback)"
  source $T_HOME/lib/common.zsh
  source $T_HOME/lib/datetr.zsh
  source $T_HOME/lib/gnu.zsh
  _lc_g=()                        # force the BSD translations even if GNU tools exist
  _lc_readlink_f=1

  tr_is sed -i 's/a/b/' f                :: sed -i '' s/a/b/ f
  tr_is sed -i.bak -e 's/a/b/' f         :: sed -i .bak -e s/a/b/ f
  tr_is sed -r 's/(a)/\1/' f             :: sed -E 's/(a)/\1/' f
  tr_is sed --in-place=.orig s/x/y/ f    :: sed -i .orig s/x/y/ f
  tr_is sed -ni 's/a/b/p' f              :: sed -n -i '' s/a/b/p f
  tr_is sed -n '1p' f                    :: sed -n 1p f

  tr_is grep -P '\d+' f                  :: grep --color=auto -E '[0-9]+' f
  tr_is grep -oP '(?i)foo\s+bar' f       :: grep --color=auto -i -oE 'foo[[:space:]]+bar' f
  tr_is grep -P 'a.*?b' f                :: grep --color=auto -E 'a.*b' f
  tr_is grep -P '[\d_]+' f               :: grep --color=auto -E '[0-9_]+' f
  tr_is grep -P '[[:alpha:]\d]' f        :: grep --color=auto -E '[[:alpha:]0-9]' f
  tr_is grep -rn needle                  :: grep --color=auto -rn needle .
  tr_is grep -rn needle src              :: grep --color=auto -rn needle src
  tr_is grep -e foo -r                   :: grep --color=auto -e foo -r .
  tr_is grep --color=never x f           :: grep --color=never x f
  tr_is grep -A 2 -i x f                 :: grep --color=auto -A 2 -i x f

  tr_is ls --color=auto -la              :: ls -G -la
  tr_is ls --group-directories-first -lh :: ls -G -lh
  tr_is ls --color=never -l              :: ls -l
  tr_is ls --color=always                :: env CLICOLOR_FORCE=1 ls -G
  tr_is ls --all --human-readable -l     :: ls -G -a -h -l

  tr_is date -d '2024-03-05 10:20:30' '+%F %T' :: date -j -f '%Y-%m-%d %H:%M:%S' '2024-03-05 10:20:30' '+%F %T'
  tr_is date -d '2 days ago' +%F         :: date -v-2d +%F
  tr_is date -d yesterday                :: date -v-1d
  tr_is date --date='+3 hours'           :: date -v+3H
  tr_is date -d 'next monday' +%u        :: date -v+1d -v+mon -v0H -v0M -v0S +%u
  tr_is date -d 'last friday'            :: date -v-1d -v-fri -v0H -v0M -v0S
  tr_is date -d @0 -u +%Y                :: date -u -r 0 +%Y
  tr_is date -d '2024-01-31 +1 day' +%F  :: date -j -v+1d -f '%Y-%m-%d %H:%M:%S' '2024-01-31 0:0:0' +%F
  tr_is date -d 'tomorrow 10:30' +%H:%M  :: date -v+1d -v10H -v30M -v0S +%H:%M
  tr_is date -d '1 week 2 days ago'      :: date -v-1w -v-2d
  tr_is date -I                          :: date +%Y-%m-%d
  tr_is date -u +%s                      :: date -u +%s
  local -a reply
  if _lc_build date -d 'not a date' 2>/dev/null; then bad "date -d 'not a date' should fail"; else ok "date -d 'not a date' fails"; fi

  tr_is stat -c '%s %n' f                :: stat -t '%Y-%m-%d %H:%M:%S %z' -f '%z %N' -- f
  tr_is stat -c %a f                     :: stat -t '%Y-%m-%d %H:%M:%S %z' -f %OLp -- f
  tr_is stat --format='%U:%G' f          :: stat -t '%Y-%m-%d %H:%M:%S %z' -f %Su:%Sg -- f
  tr_is stat f                           :: stat -x -- f
  tr_is readlink -f .                    :: readlink -f .
  tr_is readlink link                    :: readlink link

  tr_is find -name '*.txt'               :: find . -name '*.txt'
  tr_is find . -type f -executable       :: find . -type f -perm +111
  tr_is find . -regextype posix-extended -regex '.*\.(c|h)' :: find -E . -regex '.*\.(c|h)'
  tr_is find . -printf '%p\n'            :: find . -print
  tr_is find . -printf '%s %p\n'         :: find . -exec stat -n -f $'%z %N\n' '{}' ';'

  tr_is xargs -r echo                    :: xargs echo
  tr_is xargs -0r rm                     :: xargs -0 rm
  tr_is xargs -i cp {} /tmp              :: xargs -I '{}' cp '{}' /tmp
  tr_is xargs -n1 -P4 echo               :: xargs -n 1 -P 4 echo
  tr_is xargs -d '\n' echo               :: _lc_impl_xargs_d $'\n' echo

  tr_is du --max-depth=1 -h .            :: du -d 1 -h .
  tr_is du -sh --apparent-size x         :: du -sh -A x
  tr_is df -hT                           :: df -h
  tr_is df -x tmpfs                      :: df -T notmpfs
  tr_is df -T                            :: df
  tr_is du -sh                           :: du -sh

  tr_is head -n -2 f                     :: perl -ne 'BEGIN { $n = shift } push @b, $_; print shift @b if @b > $n' -- 2 f
  tr_is head -5 f                        :: head -n 5 f
  tr_is head --lines=3 f                 :: head -n 3 f
  tr_is tail --follow=name -n 5 log      :: tail -F -n 5 log
  tr_is tail -n +2 f                     :: tail -n +2 f

  tr_is cp -t /dst a b                   :: cp a b /dst
  tr_is cp -r --reflink=auto a b         :: cp -r -c a b
  tr_is mv --no-clobber a b              :: mv -n a b

  tr_is base64 -d f                      :: base64 -D -i f
  tr_is base64 -w0 f                     :: base64 -b 0 -i f

  tr_is ps aux --sort=-%mem              :: ps aux -m
  tr_is ps -eo pid,cmd                   :: ps -eo pid,command
  tr_is ps --sort=-pcpu -ef              :: ps -r -ef
  tr_is top -b -n 1                      :: top -l 1
  tr_is top -o %MEM                      :: top -o mem
  tr_is netstat -tulpn                   :: lsof -nP -iTCP -sTCP:LISTEN -iUDP
  tr_is netstat -tlnp                    :: lsof -nP -iTCP -sTCP:LISTEN
  tr_is netstat -rn                      :: netstat -rn
  tr_is netstat -an -p tcp               :: netstat -an -p tcp
  tr_is hostname -I                      :: _lc_impl_ips
  tr_is hostname                         :: hostname
  tr_is uptime -p                        :: _lc_impl_uptime p
  tr_is zcat a.gz                        :: gzip -dc a.gz

  print "translations (GNU tools installed)"
  _lc_g=(sed /b/gsed ls /b/gls grep /b/ggrep)
  tr_is sed -i 's/a/b/' f                :: /b/gsed -i s/a/b/ f
  tr_is ls -la                           :: /b/gls --color=auto -la
  tr_is ls -G -la                        :: /b/gls --color=auto --color=auto -la
  tr_is grep -P '\d' f                   :: /b/ggrep --color=auto -P '\d' f
  tr_is grep --color=never x             :: /b/ggrep --color=never x
  tr_is netstat -tlnp                    :: lsof -nP -iTCP -sTCP:LISTEN

  print "perl regex -> ERE"
  local REPLY
  _lc_pcre2ere '\w+\s\d\S\W\D'; same '\w+\s\d\S\W\D' "$REPLY" '[[:alnum:]_]+[[:space:]][0-9][^[:space:]][^[:alnum:]_][^0-9]'
  _lc_pcre2ere 'a+?b{2,3}?';    same 'lazy quantifiers' "$REPLY" 'a+b{2,3}'
  _lc_pcre2ere '\.\\';          same 'escapes kept' "$REPLY" '\.\\'
}

# ---------------------------------------------------------------- 2. package managers

t_packages() {
  print "package managers / services (fake brew)"
  local tmp=$(mktemp -d) log
  log=$tmp/log
  mkdir -p $tmp/bin
  cat > $tmp/bin/brew <<'EOF'
#!/bin/sh
echo "brew $*" >> "$LC_TEST_LOG"
case "$1 $2" in
  "services list") printf 'Name Status User File\nredis none\npostgresql@16 started me ~/x.plist\n';;
esac
exit 0
EOF
  chmod +x $tmp/bin/brew
  local n
  for n in apt-get yum dnf pacman service; do
    [[ $n == service ]] && ln -s $T_HOME/bin/systemctl $tmp/$n || ln -s $T_HOME/bin/apt $tmp/$n
  done

  run() {   # run TOOL ARGS... ; prints the brew calls it made
    : >| $log
    local t=$1; shift
    local p=$tmp/$t; [[ -e $p ]] || p=$T_HOME/bin/$t
    HOMEBREW_PREFIX=$tmp LC_TEST_LOG=$log zsh $p "$@" >/dev/null 2>&1
    print -r -- "${(j:; :)${(f)"$(<$log)"}}"
  }
  same 'apt install -y python3-pip nodejs htop curl' "$(run apt install -y python3-pip nodejs htop curl)" 'brew install python node htop'
  same 'apt-get remove -y htop'          "$(run apt-get remove -y htop)"     'brew uninstall htop'
  same 'apt update'                      "$(run apt update)"                 'brew update'
  same 'apt upgrade'                     "$(run apt upgrade)"                'brew upgrade'
  same 'apt search ripgrep'              "$(run apt search ripgrep)"         'brew search ripgrep'
  same 'apt install libxml2-dev'         "$(run apt install libxml2-dev)"    'brew info --formula libxml2; brew install libxml2'
  same 'apt list --installed'            "$(run apt list --installed)"       'brew list --versions'
  same 'yum install -y docker.io'        "$(run yum install -y docker.io)"   'brew install --cask docker'
  same 'yum update'                      "$(run yum update)"                 'brew upgrade'
  same 'dnf check-update'                "$(run dnf check-update)"           'brew outdated'
  same 'pacman -Syu'                     "$(run pacman -Syu)"                'brew update; brew upgrade'
  same 'pacman -S --noconfirm git'       "$(run pacman -S --noconfirm git)"  'brew install git'
  same 'pacman -Rns git'                 "$(run pacman -Rns git)"            'brew uninstall git'
  same 'systemctl start redis'           "$(run systemctl start redis)"      'brew services list; brew services run redis'
  same 'systemctl restart postgresql'    "$(run systemctl restart postgresql)" 'brew services list; brew services restart postgresql@16'
  same 'systemctl enable --now redis-server' "$(run systemctl enable --now redis-server)" 'brew services list; brew services start redis'
  same 'service redis stop'              "$(run service redis stop)"         'brew services list; brew services kill redis'
  same 'systemctl daemon-reload'         "$(run systemctl daemon-reload)"    ''
  HOMEBREW_PREFIX=$tmp LC_TEST_LOG=$log zsh $T_HOME/bin/systemctl start nosuch >/dev/null 2>&1
  same 'systemctl start nosuch exit code' $? 5
  rm -rf $tmp
}

# ---------------------------------------------------------------- 3. bash habits

t_bashcompat_inner() {    # runs inside `zsh -f -i`
  source $T_HOME/linux-compat.zsh
  local -a arr
  shopt -s nullglob;  [[ -o nullglob ]] && ok 'shopt -s nullglob' || bad 'shopt -s nullglob'
  shopt -u nullglob;  [[ -o nullglob ]] && bad 'shopt -u nullglob' || ok 'shopt -u nullglob'
  shopt -q globstar && ok 'shopt -q globstar' || bad 'shopt -q globstar'
  mapfile -t arr < <(print -l one 'two words' three)
  same 'mapfile -t' "${(j:|:)arr}" 'one|two words|three'
  print -l x y | readarray lines
  same 'readarray from a pipe' "${(j:|:)lines}" 'x|y'
  local v
  read -r -p 'prompt: ' v <<< 'hello world' 2>/dev/null
  same 'read -p' "$v" 'hello world'
  read -r -a arr <<< 'a b c'
  same 'read -a' "${(j:|:)arr}" 'a|b|c'
  read -n 2 v <<< 'xyz'
  same 'read -n 2' "$v" 'xy'
  same 'echo without -e keeps \n' "$(echo 'a\nb')" 'a\nb'
  same 'echo -e' "$(echo -e 'a\tb')" $'a\tb'
  same 'unmatched glob passes through' "$(print -r -- /nonexistent/*.nothing)" '/nonexistent/*.nothing'

  local REPLY
  _lc_ps1_from_bash '\u@\h:\w\$ '
  same 'PS1 \u@\h:\w\$' "$REPLY" '%n@%m:%~%(!.#.$) '
  _lc_ps1_from_bash '\[\e[32m\]\W\[\e[0m\] '
  same 'PS1 colours' "$REPLY" $'%{\e[32m%}%1~%{\e[0m%} '

  local BUFFER
  BUFFER='echo ${name,,} ${name^^}'; _lc_bash_syntax
  same '${x,,} ${x^^}' "$BUFFER" 'echo ${(L)name} ${(U)name}'
  BUFFER='echo ${!ref} ${!arr[@]} ${!LC_*}'; _lc_bash_syntax
  same '${!x} ${!a[@]} ${!p*}' "$BUFFER" 'echo ${(P)ref} ${(k)arr} ${(k)parameters[(I)LC_*]}'
  BUFFER='echo ${name^}'; _lc_bash_syntax
  same '${x^}' "$BUFFER" 'echo ${(U)name[1]}${name[2,-1]}'
  BUFFER='echo ${HOME} ${#x} ${x:-y}'; _lc_bash_syntax
  same 'normal expansions untouched' "$BUFFER" 'echo ${HOME} ${#x} ${x:-y}'

  local name=MiXeD; same '${(L)} works' "${(L)name}" mixed
  local tmp=$(mktemp -d)
  print -r -- 'echo "bash=${BASH_VERSION%%.*}"' > $tmp/t.sh
  [[ $(_lc_script $tmp/t.sh) == bash=<-> ]] && ok 'script without shebang runs in bash' || bad 'script without shebang runs in bash'
  rm -rf $tmp
  print "__COUNTS__ $T_PASS $T_FAIL"
}

t_bashcompat() {
  print "bash habits (interactive shell)"
  local out tmp=$(mktemp -d)
  out=$(ZDOTDIR=$tmp zsh -f -i -c "source ${(q)T_HOME}/tests/run-tests.zsh --inner" 2>&1 </dev/null)
  rm -rf $tmp
  local -a c lines
  c=(${=${(M)${(f)out}:#__COUNTS__*}})
  lines=(${${(f)out}:#__COUNTS__*})
  (( $#lines )) && print -rl -- $lines
  if (( $#c == 3 )); then (( T_PASS += c[2], T_FAIL += c[3] )); else bad 'interactive shell crashed' "$out"; fi
}

# ---------------------------------------------------------------- 4. live (macOS)

t_live() {     # $1 = gnu | bsd
  local tmp=$(command mktemp -d) out
  source $T_HOME/lib/common.zsh; source $T_HOME/lib/datetr.zsh; source $T_HOME/lib/gnu.zsh
  if [[ $1 == bsd ]]; then
    _lc_g=()
    print "live commands (macOS, BSD fallback translations)"
  else
    (( $#_lc_g )) || return 0
    print "live commands (macOS, GNU tools: ${(k)_lc_g})"
  fi
  cd $tmp || return
  path+=($T_HOME/bin)

  print hello > f; sed -i 's/hello/bye/' f
  same 'sed -i edits in place' "$(<f)" bye
  [[ -e "f''" || -e f- ]] && bad 'sed -i left a backup file' || ok 'sed -i no backup file'
  sed -i.bak 's/bye/hi/' f
  same 'sed -i.bak' "$(<f) $(<f.bak)" 'hi bye'
  same 'grep -P \d' "$(print 'abc 123' | grep -oP '\d+')" 123
  same 'grep -P \w+@' "$(print 'mail bob@example ok' | grep -oP '\w+@\w+')" bob@example
  mkdir -p sub; print needle > sub/x
  [[ $(grep -rl needle) == (./|)sub/x ]] && ok 'grep -rl with no path' || bad 'grep -rl with no path' "$(grep -rl needle 2>&1)"
  same 'date -d absolute' "$(date -d '2024-03-05 10:20:30' '+%F %T')" '2024-03-05 10:20:30'
  same 'date -d @0 -u' "$(date -d @0 -u +%Y)" 1970
  same 'date -d yesterday' "$(date -d yesterday +%F)" "$(command date -v-1d +%F)"
  same 'date -d "2 days ago"' "$(date -d '2 days ago' +%F)" "$(command date -v-2d +%F)"
  same 'date -d "next monday"' "$(date -d 'next monday' +%u)" 1
  same 'date -d "2024-01-31 +1 day"' "$(date -d '2024-01-31 +1 day' +%F)" 2024-02-01
  same 'date +%N is numeric' "$(date +%N | tr -d 0-9)" ''
  touch -d '2020-01-02 03:04:05' f
  same 'touch -d + stat -c %Y' "$(stat -c %Y f)" "$(command date -j -f '%Y-%m-%d %H:%M:%S' '2020-01-02 03:04:05' +%s)"
  same 'stat -c %s %n' "$(stat -c '%s %n' f.bak)" '4 f.bak'
  same 'readlink -f' "$(readlink -f .)" "${PWD:A}"
  print -l 1 2 3 > n
  same 'head -n -1' "$(head -n -1 n | tr '\n' ,)" 1,2,
  same 'head -c -2' "$(head -c -2 n | tr '\n' ,)" 1,2,
  same 'find without a path' "$(find -name n)" ./n
  chmod +x n
  same 'find -executable' "$(find . -maxdepth 1 -type f -executable)" ./n
  same 'xargs -r on empty input' "$(print -n | xargs -r echo ran)" ''
  same "xargs -d '\\n'" "$(printf 'a b\nc\n' | xargs -d '\n' -n1 echo | tr '\n' ,)" 'a b,c,'
  ls --color=auto -la >/dev/null && ok 'ls --color=auto -la' || bad 'ls --color=auto -la'
  du --max-depth=0 -h . >/dev/null && ok 'du --max-depth' || bad 'du --max-depth'
  df -hT >/dev/null && ok 'df -hT' || bad 'df -hT'
  same 'base64 -w0 | base64 -d' "$(print -n hello | base64 -w0 | base64 -d)" hello
  mkdir dst; cp -t dst n f
  same 'cp -t' "$(print dst/*(:t))" 'f n'
  gzip -c n > n.gz
  same 'zcat file.gz' "$(zcat n.gz | tr '\n' ,)" 1,2,3,
  same 'tac' "$(tac n | tr '\n' ,)" 3,2,1,
  timeout 1 sleep 5; same 'timeout exit code' $? 124
  same 'timeout passes status' "$(timeout 5 sh -c 'exit 3'; print $?)" 3
  same 'sha256sum' "$(print -n abc | sha256sum)" 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  -'
  same 'md5sum' "$(md5sum n)" "$(md5 -q n)  n"
  md5sum n > n.md5
  same 'md5sum -c' "$(md5sum -c n.md5)" 'n: OK'
  [[ $(nproc) == <1-> ]] && ok nproc || bad nproc
  [[ $(free -h) == *Mem:* ]] && ok free || bad free "$(free -h 2>&1)"
  [[ $(lsblk) == *disk0* || $(lsblk) == *disk1* ]] && ok lsblk || bad lsblk "$(lsblk 2>&1)"
  [[ $(ip a) == *lo0* ]] && ok 'ip a' || bad 'ip a' "$(ip a 2>&1 | head -5)"
  [[ $(ip -br a) == lo0* ]] && ok 'ip -br a' || bad 'ip -br a' "$(ip -br a 2>&1 | head -3)"
  ip r >/dev/null && ok 'ip r' || bad 'ip r'
  [[ $(lscpu) == *'CPU(s):'* ]] && ok lscpu || bad lscpu
  [[ -n $(pidof zsh) ]] && ok pidof || bad pidof
  same 'shuf -i 1-5' "$(shuf -i 1-5 | sort -n | tr '\n' ,)" 1,2,3,4,5,
  [[ $(uptime -p) == up\ * ]] && ok 'uptime -p' || bad 'uptime -p' "$(uptime -p)"
  ps aux --sort=-%mem >/dev/null && ok 'ps --sort' || bad 'ps --sort'
  [[ $(lsb_release -a) == *macOS* ]] && ok lsb_release || bad lsb_release
  cd /; rm -rf $tmp
}

# ---------------------------------------------------------------- main

if [[ $1 == --inner ]]; then t_bashcompat_inner; return 0 2>/dev/null || exit 0; fi

# Each group that defines the wrappers runs in a sub-shell, so they can't leak
# into the harness; the sub-shell reports its counts on a __COUNTS__ line.
in_subshell() {
  local l
  local -a cnt
  ( T_PASS=0 T_FAIL=0; "$@"; print "__COUNTS__ $T_PASS $T_FAIL" ) 2>&1 | while IFS= read -r l; do
    if [[ $l == __COUNTS__* ]]; then cnt=(${=l}); (( T_PASS += cnt[2], T_FAIL += cnt[3] ))
    else print -r -- "$l"; fi
  done
}

print "linux-compat self-test ($T_HOME)"
in_subshell t_translations
t_packages
t_bashcompat
if [[ $OSTYPE == darwin* ]]; then
  in_subshell t_live gnu
  in_subshell t_live bsd
else
  print "live commands: skipped (not macOS)"
fi
rm -rf $LC_STATE
print
print "passed: $T_PASS   failed: $T_FAIL"
(( T_FAIL == 0 ))
