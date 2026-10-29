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

**🌟 Features**

- **🎨 Dynamic Material Color Schemes:** Deep Matugen and Wallust integration automatically creates GTK, Qt, shell and terminal palettes directly from your active wallpaper.

- **🏝️ Dynamic Island and Shell Widgets:** Customized Quickshell panels offer fluid desktop status widgets, app launcher integration, power menus and media controls.

- **⚡ Seamless Keybind Architecture:** Built-in IPC command routing and pre-configured Hyprland shortcuts provide smooth workspace management and instant shell responsiveness.

- **📦 Complete Automated Deployment:** A robust zero-headache install.sh takes care of all official and AUR dependencies SDDM themes, GTK/Qt font configurations and colorschemes from the start.

---

### **INSTALLATION**

> [!NOTE]  
> The installation methods are **exclusively designed for Arch Linux running Hyprland**.

You can install Pulsar using either the **One-Line Online Installer** or via a **Local Git Clone**.

---

### Option 1: Online Installer (Recommended)

Run the automated one-line installer directly in your terminal:

```bash
curl -fsSL https://is.gd/pulsarqs | bash
```
---

### Option 2: Local Installation

If you prefer to review the source code before running or want to install locally, follow these steps:

1. Install Git:
```bash
sudo pacman -S git --needed
```
2. Clone the repo
```bash
git clone --depth=1 https://github.com/lunardagger420/pulsar.git
```
3. Navigate to the directory and run the installer:
```bash
cd pulsar && ./install.sh
```

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
