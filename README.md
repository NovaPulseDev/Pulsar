<div align="center">

  <img src="assets/logo.png" alt="Pulsar Meteor Logo" width="180">

### **PULSAR**
### *"Where fluidity meets the void."*

[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-Framework-blue?logo=arch-linux)](https://archlinux.org)
[![Hyprland](https://img.shields.io/badge/WM-Hyprland-blueviolet?logo=wayland)](https://hyprland.org)
[![Quickshell](https://img.shields.io/badge/UI-Quickshell-ff69b4)](https://github.com/outfoxxed/quickshell)

---
<div align="left">

Pulsar is a feature-rich, dynamic Hyprland and Quickshell desktop environment powered by Matugen material color extraction and custom shell widgets. Designed with a sleek, space-inspired aesthetic where fluidity meets the void, Pulsar transforms your workflow with real-time dynamic color schemes, interactive dynamic island notifications, and intuitive desktop controls built specifically for Arch Linux.

**🌟 Features**

- **🎨 Dynamic Material Color Schemes:** Deep Matugen and Wallust integration automatically creates GTK, Qt, shell and terminal palettes directly from your active wallpaper.

- **🏝️ Dynamic Island and Shell Widgets:** Customized Quickshell panels offer fluid desktop status widgets, app launcher integration, power menus and media controls.

- **⚡ Seamless Keybind Architecture:** Built-in IPC command routing and pre-configured Hyprland shortcuts provide smooth workspace management and instant shell responsiveness.

- **📦 Complete Automated Deployment:** A robust zero-headache install.sh takes care of all official and AUR dependencies SDDM themes, GTK/Qt font configurations and colorschemes from the start.

> [DISCLOSURE]  
> The Quickshell configuration **WAS MADE WITH AI.** I am not a good Quickshell maker and **I am not willing to learn QML.** Everything else **WAS MADE BY ME.** I felt like I had to throw this out there, just for others to know.

---

### **📥 Installation**

> [NOTE]  
> The installation methods are **exclusively designed for Arch Linux running Hyprland**.

You can install Pulsar using either the **One-Line Online Installer** or via a **Local Git Clone**.

---

### Option 1: Online Installer (Recommended)

Run the automated one-line installer directly in your terminal:

```bash
curl -fsSL https://is.gd/getpulsar | bash
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
---

### ⌨️ Keybindings

> *Master the void with lightning-fast navigation.*

| Keybind | Action |
| :--- | :--- |
| <kbd>Super</kbd> + <kbd>Space</kbd> | App Launcher |
| <kbd>Super</kbd> + <kbd>C</kbd> | Control Center |
| <kbd>Super</kbd> + <kbd>Y</kbd> | Theme Picker |
| <kbd>Super</kbd> + <kbd>H</kbd> | Wallpaper Picker |
| <kbd>Super</kbd> + <kbd>L</kbd> | Lock Screen |

> **Note:** All additional keybindings and custom IPC commands can be configured directly in `~/.config/hypr/modules/binds.lua`.

---

### 🏝️ Control Center

Your command hub is built directly into the user interface. You can start the Control Center quickly using <kbd>Super</kbd> + <kbd>C</kbd>. By simply clicking the **Dynamic Island**.

- **📶 Wi-Fi Module:**

*Left-click* to turn Wi-Fi on or off.

*Right-click* to open the network manager that shows the current connection status, available SSIDs and signal strength.

- **🔊 Sound Module:**

*Left-click. Drag* horizontally to adjust the master volume smoothly.

*Right-click* to go to the audio hub (control audio outputs, inputs and volume levels, for each application).

- **☀️ Brightness:**

*Left-click and drag* horizontally to adjust the screen brightness.

*Right-click* to see display parameters.

- **🔔 Notifications:**

*Left-click* the notification container to quickly look at your alert history.

*(Bluetooth module coming soon!)*

---

### 🎨 Wallpapers & Color Schemes

Pulsar relies on  theme folders to power its dynamic color engine, Matugen. 

> ⚠️ **Important Directory Rule:** All wallpaper theme folders **must** be placed inside `~/.config/colorschemes/` mapped to their corresponding theme names. 
> 
> I’ve included a selection of default wallpapers, filtered to their themes, right out of the box in `~/.config/colorschemes` to get you started immediately.*

---

### 🙏 Credits

Huge thanks to these amazing creators and projects:

- **[@saneaspect](https://youtube.com/@saneaspect)** & **[@enhaoswen](https://github.com/enhaoswen)** — Dynamic island inspiration
- **[@end-4](https://github.com/end-4/dots-hyprland)** — Material You design & starship prompt
- **[@LazyVim](https://github.com/LazyVim/LazyVim)** — Minimal Neovim setup
- **[@InioX](https://github.com/InioX)** — Matugen color engine
- **[@LierB](https://github.com/LierB/fastfetch)** — Fastfetch config
