# linux-compat

Type Linux/bash commands in the macOS Terminal and they just work: `apt install`,
`sed -i`, `date -d yesterday`, `grep -P`, `free -h`, `ip a`, `systemctl start redis`,
`read -p`, `${var,,}`... It runs inside zsh (the default Mac shell). Nothing is printed
unless you turn debug on.

## Try it first (nothing is installed)

```sh
cd ~/Downloads/LinuxCompat      # wherever the folder is
sh try.sh
```

This opens a test shell with linux-compat loaded and your normal zsh setup, with a yellow
`[linux-compat test]` in front of the prompt. Type `exit` to go back. Nothing outside the
folder is created or changed: `~/.zshrc` is read but never edited, and the test shell
keeps its own history inside the folder. Use `sh try.sh --clean` to leave your `~/.zshrc`
out too. To undo it completely, delete the folder.

Run `linuxcompat test` in the test shell and send back the output.

## Install

1. Copy the `LinuxCompat` folder to the Mac (zip, AirDrop, USB...).
2. In Terminal:

   ```sh
   cd ~/Downloads/LinuxCompat      # wherever the folder is
   zsh install.sh
   ```

   It asks two things:
   - **Install Homebrew?** Needed for `apt`/`yum`/`dnf`/`pacman` (they become `brew`).
   - **Install GNU tools?** Homebrew's real GNU `sed`, `grep`, `date`, `find`... Strongly
     recommended: with them, flags behave exactly like Linux. Without them, linux-compat
     translates the flags for the built-in macOS tools, which covers the common cases.
3. Open a new Terminal tab.

Everything lives in `~/.linux-compat`, plus three lines at the end of `~/.zshrc`.

## Commands

| | |
|---|---|
| `linuxcompat status` | what's active, which GNU tools were found |
| `linuxcompat debug on` / `off` | show each translation, dimmed, e.g. `[linux-compat] → sed -i '' s/a/b/ f` |
| `linuxcompat test` | self-test (send the output if something's wrong) |
| `linuxcompat install-gnu` | install the GNU tools later |
| `linuxcompat gnu-everywhere on` | also give GNU tools to every program and script, not just what you type |
| `linuxcompat off` / `on` | disable / re-enable for new tabs |
| `linuxcompat uninstall` | remove it (keeps a backup of `.zshrc`) |

## What gets translated

**Same command, different flags** (uses GNU tool if installed, otherwise translates):
`sed` (`-i`, `-r`, `--in-place`), `grep` (`-P`, `-r` without a path, colour), `ls`
(`--color`, long options), `date` (`-d STRING`, `-I`, `%N`), `stat` (`-c FORMAT`), `readlink -f`,
`find` (no path, `-executable`, `-regextype`, simple `-printf`), `xargs` (`-r`, `-d`, `-i`),
`du --max-depth`, `df -T`, `head -n -N`, `tail --follow=name`, `cp`/`mv -t`, `base64 -d/-w`,
`touch -d`, `ps --sort`, `top -b -n`, `netstat -tulpn`, `hostname -I`, `uptime -p`, `zcat`,
and `sudo` in front of any of these.

**Linux-only commands** (added to the end of PATH, so a real tool always wins):
`apt` `apt-get` `apt-cache` `dpkg` `yum` `dnf` `pacman` `zypper` `apk` `snap` → Homebrew ·
`systemctl` `service` → `brew services` · `journalctl` → `log show`/`log stream` ·
`free` `lsblk` `lscpu` `nproc` `ip` `ss` `pidof` `lsusb` `lspci` `ldd` `lsb_release`
`hostnamectl` `timedatectl` · `xdg-open` · `xclip`/`xsel` → clipboard · `tac` `timeout`
`watch` `shuf` `realpath` `sha256sum` `md5sum`... · `wget` → curl · `poweroff`.

Package names are mapped too: `build-essential` → Xcode tools, `python3-pip` → python,
`nodejs` → node, `docker.io` → Docker Desktop, `libssl-dev` → openssl, and so on.
`sudo apt ...` drops the sudo (Homebrew refuses to run as root).

**Bash habits:** `# comments` at the prompt, unmatched `*` passed through like bash,
`echo` without `-e` leaves `\n` alone, `read -p/-a/-n`, `mapfile`/`readarray`, `shopt`,
`history`/`history 10`/`history -c`, `help`, `complete`/`compgen`, `~/.bash_aliases`,
`PROMPT_COMMAND`, bash-style `PS1='\u@\h:\w\$ '`, Ctrl-U, and `${var,,}` `${var^^}` `${!var}`
`${!arr[@]}` `${!prefix*}`.

**Linux scripts:** `bash x.sh`, `sh x.sh` and `./x.sh` use Homebrew's bash 5 (macOS has 3.2)
and get the GNU tools first on PATH, so scripts written for Linux run unchanged.

## Limits

- zsh arrays start at 1, bash arrays at 0. That can't be translated.
- The `${var,,}` rewrite is shown on screen when it fires (history keeps what you typed).
- Without the GNU tools: GNU-only regex in `sed` (`\+`, `\|`), Perl look-arounds in
  `grep -P`, and rare flags aren't covered. `linuxcompat install-gnu` fixes all of that.
- `apt install` of a package with no Homebrew equivalent fails the way brew does.
