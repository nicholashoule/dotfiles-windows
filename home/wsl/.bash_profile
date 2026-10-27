# shellcheck shell=bash
# .bash_profile
#
# Login shell setup. Bash reads this for login shells, as WSL starts them, and
# for `bash -l`. It reads only the first of ~/.bash_profile, ~/.bash_login, and
# ~/.profile, so Ubuntu's ~/.profile is ignored while this file exists;
# ~/.bashrc puts ~/bin and ~/.local/bin on PATH, as that file would.
#
# Order of operations:
#   1. /etc/profile    system login environment, read by bash before this file
#   2. ~/.bashrc       shared setup, so login and non-login shells match
#
# This is dotfiles-linux's .bash_profile without its terminal settings for
# Ptyxis and GNOME Terminal: in WSL, Windows Terminal draws the text, with the
# font the Windows side installs. Keep per-shell settings (aliases,
# completions, prompt) in ~/.bashrc or ~/.bashrc.d.

# Shared setup from ~/.bashrc
if [ -f ~/.bashrc ]; then
    # shellcheck source=/dev/null
    . ~/.bashrc
fi
