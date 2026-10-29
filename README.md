<div align="center">

  <img src="assets/logo.png" alt="Pulsar Meteor Logo" width="180">

### **PULSAR**
### *"Where fluidity meets the void."*

[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-Framework-blue?logo=arch-linux)](https://archlinux.org)
[![Hyprland](https://img.shields.io/badge/WM-Hyprland-blueviolet?logo=wayland)](https://hyprland.org)
[![Quickshell](https://img.shields.io/badge/UI-Quickshell-ff69b4)](https://github.com/outfoxxed/quickshell)

---
<div align="left">

### **OVERVIEW**

Pulsar is a feature-rich, dynamic Hyprland and Quickshell desktop environment powered by Matugen material color extraction and custom shell widgets. Designed with a sleek, space-inspired aesthetic where fluidity meets the void, Pulsar transforms your workflow with real-time dynamic color schemes, interactive dynamic island notifications, and intuitive desktop controls built specifically for Arch Linux.

**🌟 Key Highlights**

- 🎨 Dynamic Material Color Schemes: Deep Matugen and Wallust integration automatically creates GTK, Qt, shell and terminal palettes directly from your active wallpaper.

- 🏝️ Dynamic Island and Shell Widgets: Customized Quickshell panels offer fluid desktop status widgets, app launcher integration, power menus and media controls.

- ⚡ Seamless Keybind Architecture: Built-in IPC command routing and pre-configured Hyprland shortcuts provide smooth workspace management and instant shell responsiveness.

- 📦 Complete Automated Deployment: A robust zero-headache install.sh takes care of all official and AUR dependencies SDDM themes, GTK/Qt font configurations and colorschemes from the start.

---

### **INSTALLATION**

Note: The two installation methods **ONLY WORK ON ARCH LINUX AND ONLY ON HYPRLAND.** This is a choice.

Now there are two ways that you can do this, the online installer way or the git clone / local install way.

### *Online install*

For the online install, just copy / type this into the shell.
```bash
curl -fsSL https://is.gd/pulsarqs | bash
```
### *Local install*

For the local install, you will need git.

First, install git.
```pacman
sudo pacman -S --needed git
```

Then clone the repo.
```git
git clone https://github.com/lunardagger420/pulsar.git --depth=1
```

Finally, cd into the folder and run the installer.
```cd
cd ~/pulsar && ./install.sh
```

---

### KEYBINDS

| Keybind | Action |
| :--- | :--- |
| <kbd>Super</kbd> + <kbd>Space</kbd> | App Launcher |
| <kbd>Super</kbd> + <kbd>C</kbd>  | Control Center |
| <kbd>Super</kbd> + <kbd>Y</kbd> | Theme Picker |
| <kbd>Super</kbd> + <kbd>H</kbd> | Wallpaper Picker |
| <kbd>Super</kbd> + <kbd>L</kbd> | Lock Screen |

All the other keybinds can be configured in ~/.config/hypr/modules/binds.lua, along with the ipc commands provided.

---

### CONTROL CENTER
The control center holds the wifi, sound, display and notification modules (bluetooth coming soon).
For the control center, you are also able to click the island to access it, along with <kbd>Super + C</kbd> .

- To access the wifi module, right click the wifi box. Left clicking will toggle it. This will show the connected wifi and the available wifis, including the data strength too.
- To access the sound module, right click the sound box. Left clicking and dragging it left to right will adjust volume. This will show outputs, inputs and app volume.
- To access the display module, right click the display box. Left clicking and dragging it left to right will adjust brightness. This will show displays and their brightness.
- To access the notification module, left click the notification box. This will show notifications.

---

### WALLPAPERS
  The wallpaper folders (please put the folders in their corresponding themes) HAS to be located in ~/.config/colorschemes. I have given you some default wallpapers in ~/.config/colorschemes.

---

### CREDITS
I want to thank these people as I could not have done this rice without them.

- [@saneaspect](https://youtube.com/@saneaspect) & [@enhaoswen](https://github.com/enhaoswen) for inspiration for the dynamic island.
- [@end-4's dots](https://github.com/end-4/dots-hyprland) for providing such a great starship prompt and popularizing the Material You design on Hyprland.
- [@LazyVim](https://github.com/LazyVim/LazyVim) for providing a minimal starter for NeoVim.
- [@InioX](https://github.com/InioX) for giving us Matugen.
- [@LierB](https://github.com/LierB/fastfetch) for creating the fastfetch configuration.
