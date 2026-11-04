#!/bin/sh
# linux-compat installer. Run from the unpacked folder:   zsh install.sh
#   --yes        answer yes to every question (Homebrew + GNU tools)
#   --no-brew    don't install Homebrew or the GNU tools
set -e

SRC=$(cd "$(dirname "$0")" && pwd)
DEST="$HOME/.linux-compat"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
YES=0; NOBREW=0
for a in "$@"; do
  case $a in --yes|-y) YES=1;; --no-brew) NOBREW=1;; esac
done

ask() {   # ask "question" -> 0 for yes
  [ $YES = 1 ] && return 0
  printf '%s [Y/n] ' "$1"
  read -r ans </dev/tty || ans=n
  case $ans in [nN]*) return 1;; *) return 0;; esac
}

if [ "$(uname -s)" != Darwin ]; then
  echo "linux-compat is for macOS (this is $(uname -s))."; exit 1
fi

echo "Installing linux-compat to $DEST"
mkdir -p "$DEST/state"
if [ "$SRC" != "$DEST" ]; then
  for d in bin lib tests; do rm -rf "$DEST/$d"; cp -R "$SRC/$d" "$DEST/$d"; done
  cp "$SRC/linux-compat.zsh" "$SRC/uninstall.sh" "$SRC/README.md" "$DEST/"
  rm -rf "$DEST/try"; cp -R "$SRC/try" "$DEST/try"; cp "$SRC/try.sh" "$DEST/"
fi
chmod +x "$DEST"/bin/*

# Extra names for multi-purpose scripts.
link() { target=$1; shift; for n in "$@"; do ln -sf "$target" "$DEST/bin/$n"; done; }
link apt        apt-get apt-cache aptitude dpkg yum dnf pacman zypper apk snap
link systemctl  service
link xdg-open   gnome-open nautilus
link xclip      xsel
link sha256sum  sha1sum sha224sum sha384sum sha512sum md5sum
link lsusb      lspci

# Files copied from a download can carry the quarantine flag.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

if ! grep -q '>>> linux-compat >>>' "$ZSHRC" 2>/dev/null; then
  {
    echo ''
    echo '# >>> linux-compat >>>'
    echo '[ -f "$HOME/.linux-compat/linux-compat.zsh" ] && source "$HOME/.linux-compat/linux-compat.zsh"'
    echo '# <<< linux-compat <<<'
  } >> "$ZSHRC"
  echo "Added linux-compat to $ZSHRC"
fi

# Homebrew: needed for apt/yum/... and for the exact GNU tools.
BREW=
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x $b ] && BREW=$b && break; done
if [ $NOBREW = 0 ]; then
  if [ -z "$BREW" ] && ask "Homebrew isn't installed. Install it now (needed for apt/yum/dnf)?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x $b ] && BREW=$b && break; done
  fi
  if [ -n "$BREW" ] && ask "Install the GNU versions of sed, grep, date, find, etc. (most accurate Linux behaviour)?"; then
    "$BREW" install coreutils gnu-sed grep findutils gnu-tar gawk bash wget watch
  fi
fi

case $SHELL in
  */zsh) ;;
  *) echo "Note: your login shell is $SHELL. Switch to zsh with:  chsh -s /bin/zsh";;
esac

echo
echo "Done. Open a new Terminal tab (or run: exec zsh) and Linux commands just work."
echo "  linuxcompat status      what's active"
echo "  linuxcompat debug on    show each translation (handy for reporting bugs)"
echo "  linuxcompat test        run the self-test"
echo "  linuxcompat uninstall   remove everything"
