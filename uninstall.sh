#!/bin/bash
# Removes what install.sh added.
set -uo pipefail
omarchy plugin disable omext.taskbar >/dev/null 2>&1
# (Omarchy's dock: omext core turns it back on.)
[[ -L $HOME/.config/omarchy/plugins/omext.taskbar ]] && rm "$HOME/.config/omarchy/plugins/omext.taskbar"
hypr_conf=$HOME/.config/hypr/hyprland.lua
[[ -f $hypr_conf ]] && sed -i "/^-- BEGIN omext-taskbar\$/,/^-- END omext-taskbar\$/d" "$hypr_conf" && { hyprctl reload >/dev/null 2>&1 || true; }
menu_conf=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
[[ -f $menu_conf ]] && sed -i "\|^ *// BEGIN omext-taskbar\$|,\|^ *// END omext-taskbar\$|d" "$menu_conf"
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/omext/taskbar"
echo "uninstall: done"
