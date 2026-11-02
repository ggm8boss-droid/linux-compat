#!/bin/sh
# Removes linux-compat: the ~/.zshrc block and ~/.linux-compat.
DEST="$HOME/.linux-compat"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

printf 'Remove linux-compat from this Mac? [y/N] '
read -r ans </dev/tty || ans=n
case $ans in [yY]*) ;; *) echo "Nothing changed."; exit 0;; esac

if grep -q '>>> linux-compat >>>' "$ZSHRC" 2>/dev/null; then
  cp "$ZSHRC" "$ZSHRC.linux-compat.bak"
  /usr/bin/sed -i '' '/^# >>> linux-compat >>>$/,/^# <<< linux-compat <<<$/d' "$ZSHRC"
  echo "Removed the block from $ZSHRC (backup: $ZSHRC.linux-compat.bak)"
fi
rm -rf "$DEST"
echo "Removed $DEST. Open a new Terminal tab to finish."
echo "(Homebrew and any GNU tools it installed are left in place: brew uninstall coreutils ... to remove them.)"
