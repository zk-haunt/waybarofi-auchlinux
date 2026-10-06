# Add user configurations here
# For Zsh to load your beloved configurations,
# we loaded a config file for you to customize shell settings before loading zshrc
# Edit $ZDOTDIR/user.zsh to customize settings before loading zshrc

#  Plugins 
# oh-my-zsh plugins are loaded  in $ZDOTDIR/.user.zsh file, see the file for more information

#  Aliases 
# Override aliases here in '$ZDOTDIR/.zshrc' (already set in .zshenv)
alias resetportal="~/.config/hypr/scripts/reset-portal.sh"
alias secscan="$HOME/auchlinux/scripts/malware-scanner.sh"
alias changecursor="~/.config/hypr/scripts/gtk-theme-picker.sh cursor"
alias changetheme="~/.config/hypr/scripts/gtk-theme-picker.sh"

#  Autosuggestions — make suggestions visible (default fg=8 is invisible on dark backgrounds)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#888888,underline"

#  Theme Switcher CLI — switch Zsh theme from the terminal
# Usage: zsh-theme         (helper menu / show available themes)
#        zsh-theme cycle   (cycle to next theme)
#        zsh-theme <name>  (switch to specific theme)
#        zsh-theme status  (show current theme)
zsh-theme() {
    lua ~/.config/hypr/hyprland/luascript/zsh-theme.lua "$@"
}

#  Rofi Theme Switcher CLI — switch Rofi launcher design from the terminal
# Usage: rofi-theme         (helper menu / show available layouts)
#        rofi-theme cycle   (cycle to next layout)
#        rofi-theme <name>  (switch to specific layout)
#        rofi-theme status  (show current layout)
rofi-theme() {
    lua ~/.config/hypr/hyprland/luascript/rofi-theme.lua "$@"
}

#  This is your file 
# Add your configurations here
export EDITOR=code

# Waybar theme switcher alias
alias waybar-theme="$HOME/.config/waybar/scripts/waybar-theme"
