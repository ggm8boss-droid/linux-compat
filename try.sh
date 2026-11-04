#!/bin/sh
# Try linux-compat WITHOUT installing it.
#
#   sh try.sh            opens a test shell: your normal zsh setup + linux-compat
#   sh try.sh --clean    opens a plain zsh + linux-compat (your ~/.zshrc is not loaded)
#
# Nothing outside this folder is created or changed. ~/.zshrc and ~/.zshenv are only
# read, never written; the test shell keeps its history in this folder. Type `exit` to
# go back to your normal shell. To get rid of it, delete the folder.
DIR=$(cd "$(dirname "$0")" && pwd)
CLEAN=0
for a in "$@"; do
  case $a in
    --clean) CLEAN=1;;
    -h|--help) sed -n '2,9p' "$0"; exit 0;;
  esac
done

if ! command -v zsh >/dev/null 2>&1; then
  echo "zsh not found."; exit 1
fi

# Everything below only touches this folder.
chmod +x "$DIR"/bin/* 2>/dev/null
link() { target=$1; shift; for n in "$@"; do ln -sf "$target" "$DIR/bin/$n"; done; }
link apt        apt-get apt-cache aptitude dpkg yum dnf pacman zypper apk snap
link systemctl  service
link xdg-open   gnome-open nautilus
link xclip      xsel
link sha256sum  sha1sum sha224sum sha384sum sha512sum md5sum
link lsusb      lspci
xattr -dr com.apple.quarantine "$DIR" 2>/dev/null || true
mkdir -p "$DIR/state"

echo "linux-compat test shell  (nothing is installed; your settings are untouched)"
[ $CLEAN = 1 ] && echo "  --clean: your ~/.zshrc is NOT loaded"
echo "  try Linux commands, e.g.  free -h   ip a   readlink -f .   sed -i 's/a/b/' file"
echo "  linuxcompat debug on   shows how each command was translated"
echo "  linuxcompat test       runs the self-test"
echo "  exit                   back to your normal shell"
echo

LC_TRY=1 \
LC_TRY_DIR=$DIR \
LC_TRY_CLEAN=$CLEAN \
LC_TRY_USER_ZDOTDIR=${ZDOTDIR:-$HOME} \
LC_TRY_OLD_ZDOTDIR=${ZDOTDIR-} \
ZDOTDIR=$DIR/try \
  zsh -i
rc=$?
echo "Left the linux-compat test shell. Nothing was changed outside $DIR"
exit $rc
