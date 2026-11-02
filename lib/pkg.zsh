# Linux package managers -> Homebrew. Used by bin/apt, bin/yum, bin/pacman, ...

# Linux package name -> brew name. Special values:
#   @skip   macOS already has it        @xcode  Xcode Command Line Tools
#   @cask:X install the cask X
typeset -gA _lc_pkgmap
_lc_pkgmap=(
  build-essential @xcode  gcc gcc  g++ gcc  clang @xcode  make @xcode  libc6-dev @xcode
  python3 python  python python  python3-pip python  python-pip python  python3-venv python
  python3-dev python  python-is-python3 @skip  pip python
  nodejs node  npm node
  docker.io @cask:docker  docker-ce @cask:docker  docker-ce-cli docker  containerd.io @skip
  docker-compose docker-compose  docker-compose-plugin docker-compose
  golang go  golang-go go  default-jdk openjdk  default-jre openjdk
  ruby-full ruby  rustc rust  cargo rust
  libssl-dev openssl  openssl openssl  zlib1g-dev zlib  libffi-dev libffi
  postgresql postgresql@17  postgresql-client libpq  libpq-dev libpq
  mysql-server mysql  mariadb-server mariadb  redis-server redis  redis-tools redis
  sqlite3 sqlite  libsqlite3-dev sqlite
  fd-find fd  silversearcher-ag the_silver_searcher  p7zip-full sevenzip  p7zip sevenzip
  pkg-config pkgconf  bash-completion bash-completion@2  gnupg2 gnupg
  vim-gtk3 vim  vim-nox vim  neovim neovim  netcat-openbsd netcat  netcat netcat
  google-chrome-stable google-chrome  chromium-browser chromium  code visual-studio-code
  net-tools @skip  iproute2 @skip  iputils-ping @skip  dnsutils @skip  bind9-dnsutils @skip
  openssh-client @skip  openssh-server @skip  software-properties-common @skip
  apt-transport-https @skip  lsb-release @skip  ca-certificates @skip  locales @skip
  tzdata @skip  curl @skip  unzip @skip  zip @skip  less @skip  sudo @skip  procps @skip
  util-linux @skip  lsof @skip  man-db @skip  xclip @skip  xsel @skip  cron @skip
  rsync @skip  ssh @skip  passwd @skip  file @skip  bzip2 @skip  gzip @skip  tar @skip
  ufw @skip  systemd @skip  dbus @skip  xdg-utils @skip
)

# Resolve Linux names. Fills the caller's arrays: formulae casks; sets xcode=1.
_lc_pkg_resolve() {
  local p m c
  for p; do
    m=${_lc_pkgmap[$p]}
    if [[ -z $m ]]; then
      case $p in
        openjdk-<->-jdk*|openjdk-<->-jre*) m=openjdk@${${p#openjdk-}%%-*};;
        python3-*)
          _lc_err "linux-compat: '$p' is a Python package; use: pip3 install ${p#python3-}"
          continue;;
        lib*-dev|lib*-devel)                # headers come with the brew formula
          c=${${p%-dev}%-devel}
          if _lc_brew info --formula $c &>/dev/null; then m=$c; else m=${c#lib}; fi;;
        *-dev|*-devel) m=${${p%-dev}%-devel};;
        *) m=$p;;
      esac
    fi
    case $m in
      @skip)   _lc_log "$p: already part of macOS";;
      @xcode)  xcode=1;;
      @cask:*) casks+=(${m#@cask:});;
      *)       formulae+=($m);;
    esac
  done
  formulae=(${(u)formulae}); casks=(${(u)casks})
}

_lc_pkg_install() {     # install [--reinstall] names...
  local verb=install
  [[ $1 == --reinstall ]] && { verb=reinstall; shift }
  local -a formulae casks
  local -i xcode=0 rc=0
  _lc_pkg_resolve "$@"
  if (( xcode )); then
    if xcode-select -p &>/dev/null; then
      _lc_log "Xcode Command Line Tools already installed"
    else
      _lc_log "→ xcode-select --install"
      xcode-select --install
    fi
  fi
  (( $#formulae )) && { _lc_brew $verb $formulae || rc=$? }
  (( $#casks ))    && { _lc_brew $verb --cask $casks || rc=$? }
  return $rc
}

_lc_pkg_remove() {
  local -a formulae casks
  local -i xcode=0
  _lc_pkg_resolve "$@"
  (( $#formulae || $#casks )) || return 0
  _lc_brew uninstall $formulae $casks
}

_lc_pkg_upgrade() {     # no names = everything
  local -a formulae casks
  local -i xcode=0
  (( $# )) || { _lc_brew upgrade; return }
  _lc_pkg_resolve "$@"
  _lc_brew upgrade $formulae $casks
}

_lc_pkg_list() { _lc_brew list --versions "$@" }

# Drop the "assume yes"/quiet style flags every Linux tool has; leaves the rest in reply.
_lc_pkg_args() {
  local a
  reply=()
  for a; do
    case $a in
      -y|--yes|--assume-yes|-q|-qq|--quiet|--no-install-recommends|--install-recommends|\
      --noconfirm|--needed|--classic|--strict|--devmode|-n|--non-interactive|--no-cache|\
      --allow-unauthenticated|--allow-downgrades|--fix-missing|--show-progress|-m|--nobest|\
      --refresh|--skip-broken|--best|-V|--verbose) ;;
      -[yq]*) ;;
      *) reply+=("$a");;
    esac
  done
}

_lc_pkg() {
  emulate -L zsh
  setopt extended_glob
  local tool=$1; shift
  local cmd fix= a
  local -a reply args
  if [[ $tool == pacman ]]; then _lc_pacman "$@"; return; fi
  if [[ $tool == dpkg ]]; then _lc_dpkg "$@"; return; fi
  for a in "$@"; do [[ $a == (-f|--fix-broken) ]] && fix=1; done
  _lc_pkg_args "${(@)@:#(-f|--fix-broken)}"
  args=("${reply[@]}")
  cmd=$args[1]; shift args

  case $tool:$cmd in
    *:(install|in|add|groupinstall))
      if [[ $cmd == groupinstall || $args[1] == *(#i)development* ]]; then
        args=(build-essential)
      fi
      if (( ! $#args )); then
        [[ -n $fix ]] && { _lc_brew missing; return }
        return 0
      fi
      _lc_pkg_install $args;;
    *:group)
      [[ $args[1] == install ]] && _lc_pkg_install build-essential;;
    *:reinstall)                 _lc_pkg_install --reinstall $args;;
    *:(remove|purge|erase|rm|del|uninstall)) _lc_pkg_remove $args;;
    *:autoremove)                _lc_brew autoremove;;
    *:(update|refresh|ref|makecache))
      if [[ $tool == (yum|dnf) && $cmd == update ]]; then _lc_pkg_upgrade $args
      else _lc_brew update; fi;;
    *:(upgrade|full-upgrade|dist-upgrade|up|safe-upgrade)) _lc_pkg_upgrade $args;;
    *:(check-update|list-updates)) _lc_brew outdated;;
    snap:refresh)                _lc_pkg_upgrade $args;;
    *:(search|se|find|search-names)) _lc_brew search $args;;
    *:(show|info|policy|showpkg|madison|if))
      local -a formulae casks; local -i xcode=0
      _lc_pkg_resolve $args
      _lc_brew info $formulae $casks;;
    *:depends)                   _lc_brew deps --tree $args;;
    *:rdepends)                  _lc_brew uses --installed $args;;
    *:list)
      case $args[1] in
        --upgradable|updates) _lc_brew outdated;;
        --installed|installed|'') _lc_pkg_list;;
        *) _lc_brew search $args;;
      esac;;
    *:(clean|autoclean|clean-all|cc)) _lc_brew cleanup;;
    *:(edit-sources|repolist|config-manager|modules|repos)) _lc_log "no package sources to edit on macOS (Homebrew uses taps: brew tap)";;
    *:(provides|whatprovides))
      _lc_err "$tool: '$cmd' is not available on macOS"; return 1;;
    *:(''|-h|--help|help))
      print "$tool (linux-compat, backed by Homebrew)"
      print "usage: $tool install|remove|update|upgrade|search|show|list|autoremove|clean PACKAGE...";;
    *)
      _lc_err "$tool: unknown command '$cmd'"; return 100;;
  esac
}

_lc_pacman() {
  local op=$1 a
  local -a reply pk
  shift
  _lc_pkg_args "$@"; pk=("${reply[@]}")
  pk=(${pk:#--*})
  case $op in
    -S*s*)  _lc_brew search $pk;;
    -S*i*)  local -a formulae casks; local -i xcode=0; _lc_pkg_resolve $pk; _lc_brew info $formulae $casks;;
    -S*c*)  _lc_brew cleanup;;
    -S*)
      [[ $op == *y* ]] && { _lc_brew update || return }
      [[ $op == *u* ]] && { _lc_brew upgrade || return }
      (( $#pk )) && _lc_pkg_install $pk
      return 0;;
    -R*)    _lc_pkg_remove $pk;;
    -Q*i*)  _lc_brew info $pk;;
    -Q*l*)  _lc_brew list $pk;;
    -Q*e*)  _lc_brew leaves;;
    -Q*s*)  _lc_pkg_list | command grep -i -- "${pk[1]:-.}";;
    -Q*u*)  _lc_brew outdated;;
    -Q*)    _lc_pkg_list $pk;;
    -U*)    _lc_err "pacman: Arch packages can't be installed on macOS; use the package name with -S"; return 1;;
    *)      print "usage: pacman -S|-Syu|-Ss|-Si|-R|-Q|-Qi PACKAGE..."; return 1;;
  esac
}

_lc_dpkg() {
  case $1 in
    -l|--list)              shift; _lc_pkg_list "$@";;
    -L|--listfiles)         shift; _lc_brew list "$@";;
    -s|--status)            shift; _lc_brew info "$@";;
    -r|-P|--remove|--purge) shift; _lc_pkg_remove "$@";;
    --get-selections)       _lc_brew list -1;;
    -i|--install)           _lc_err "dpkg: .deb packages can't be installed on macOS; use: apt install NAME"; return 1;;
    -S|--search)            _lc_err "dpkg-query: no path found matching pattern $2"; return 1;;
    --print-architecture)   [[ $(uname -m) == arm64 ]] && print arm64 || print amd64;;
    *)                      _lc_err "dpkg: option '$1' is not available on macOS"; return 2;;
  esac
}
