#!/usr/bin/env bash

set -e  # Exit immediately on error

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure script is run on Arch Linux
if [ ! -f /etc/arch-release ]; then
    echo -e "${RED}Error: This installation script is designed exclusively for Arch Linux.${NC}"
    exit 1
fi

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}    Installing lunardagger420 Pulsar Rice       ${NC}"
echo -e "${BLUE}================================================${NC}\n"

CONFIG_DIR="$HOME/.config"
LOCAL_SHARE_FONTS="$HOME/.local/share/fonts"
BACKUP_DIR="$HOME/.config/cfg_backups/backup_$(date +%Y%m%d_%H%M%S)"
REPO_URL="https://github.com/lunardagger420/pulsar.git"

# ==========================================
# 0. Environment Detection & Fetch Repo
# ==========================================
if [ -d "./hypr" ] && [ -d "./quickshell" ] && [ -d "./colorschemes" ] && [ -t 0 ]; then
    DOTFILES_DIR="$(pwd)"
    echo -e "${GREEN}✓ Local install detected.${NC}"
else
    echo -e "${YELLOW}Remote install detected. Fetching repository...${NC}"
    sudo pacman -S --needed git --noconfirm
    DOTFILES_DIR=$(mktemp -d)
    git clone --depth=1 "$REPO_URL" "$DOTFILES_DIR"
    TRAP_CLEANUP=true
fi

# Cleanup temporary repository on exit if fetched remotely
cleanup() {
    if [ "$TRAP_CLEANUP" = true ] && [ -d "$DOTFILES_DIR" ]; then
        rm -rf "$DOTFILES_DIR"
    fi
}
trap cleanup EXIT

# ==========================================
# 1. Check and Install Paru (AUR Helper)
# ==========================================
echo -e "\n${YELLOW}[1/6] Checking for AUR helper...${NC}"
if command -v paru &> /dev/null; then
    AUR_HELPER="paru"
    echo -e "${GREEN}✓ Found paru: $(command -v paru)${NC}"
elif command -v yay &> /dev/null; then
    AUR_HELPER="yay"
    echo -e "${GREEN}✓ Found yay: $(command -v yay)${NC}"
else
    echo -e "${YELLOW}No AUR helper found. Installing paru-bin...${NC}"
    sudo pacman -S --needed base-devel git --noconfirm
    
    TEMP_DIR=$(mktemp -d)
    git clone https://aur.archlinux.org/paru-bin.git "$TEMP_DIR/paru-bin"
    cd "$TEMP_DIR/paru-bin"
    makepkg -si --noconfirm
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    AUR_HELPER="paru"
    echo -e "${GREEN}✓ Installed paru successfully.${NC}"
fi

# ==========================================
# 2. Install Packages (Official & AUR)
# ==========================================
echo -e "\n${YELLOW}[2/6] Installing official repository packages...${NC}"
PACMAN_DEPS=(
    hyprland
    quickshell
    matugen
    hypridle
    hyprlock
    brightnessctl
    sddm
    qt5-base
    qt6-base
    qt6-declarative
    qt6-5compat
    qt6-svg
    adw-gtk-theme
    papirus-icon-theme
    nwg-look
    kitty
    firefox
    nautilus
    fish
    starship
    fastfetch
    neovim
    curl
)
sudo pacman -S --needed "${PACMAN_DEPS[@]}" --noconfirm

echo -e "\n${YELLOW}[3/6] Installing AUR packages...${NC}"
AUR_DEPS=(
    bibata-cursor-theme-bin
    papirus-folders
)
$AUR_HELPER -S --needed "${AUR_DEPS[@]}" --noconfirm

# Apply grey Papirus folder icons
echo -e "\nChanging Papirus folder colors to grey..."
papirus-folders -C grey || true

# ==========================================
# 3. Download and Install Google Sans Flex
# ==========================================
echo -e "\n${YELLOW}[4/6] Installing Google Sans Flex font...${NC}"
mkdir -p "$LOCAL_SHARE_FONTS"

FONT_URL="https://raw.githubusercontent.com/end-4/google-sans-flex/main/GoogleSansFlex-VariableFont_GRAD%2CROND%2Copsz%2Cslnt%2Cwdth%2Cwght.ttf"
curl -fsSL "$FONT_URL" -o "$LOCAL_SHARE_FONTS/GoogleSansFlex-VariableFont.ttf"

fc-cache -f > /dev/null 2>&1
echo -e "${GREEN}✓ Google Sans Flex installed to $LOCAL_SHARE_FONTS${NC}"

# ==========================================
# 4. Configure GTK 3, GTK 4, Qt5/6 & nwg-look
# ==========================================
echo -e "\n${YELLOW}[5/6] Applying adw-gtk3 theme, dark mode, and Google Sans Flex font...${NC}"

# 1. Direct GTK 3 Settings File
mkdir -p "$CONFIG_DIR/gtk-3.0"
cat << 'EOF' > "$CONFIG_DIR/gtk-3.0/settings.ini"
[Settings]
gtk-theme-name=adw-gtk3
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
gtk-font-name=Google Sans Flex 11
gtk-application-prefer-dark-theme=1
EOF

# 2. Direct GTK 4 Settings File
mkdir -p "$CONFIG_DIR/gtk-4.0"
cat << 'EOF' > "$CONFIG_DIR/gtk-4.0/settings.ini"
[Settings]
gtk-theme-name=adw-gtk3
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
gtk-font-name=Google Sans Flex 11
gtk-application-prefer-dark-theme=1
EOF

# 3. Apply via gsettings if running inside a graphical session
if command -v gsettings &> /dev/null; then
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3' || true
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
    gsettings set org.gnome.desktop.interface font-name 'Google Sans Flex 11' || true
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' || true
    gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic' || true
fi

# 4. Configure nwg-look settings generator
mkdir -p "$CONFIG_DIR/nwg-look"
cat << 'EOF' > "$CONFIG_DIR/nwg-look/gsettings"
{
  "font-name": "Google Sans Flex 11",
  "gtk-theme-name": "adw-gtk3",
  "icon-theme-name": "Papirus-Dark",
  "cursor-theme-name": "Bibata-Modern-Classic",
  "cursor-size": 24,
  "prefer-dark-theme": true
}
EOF

# 5. Configure Qt5 & Qt6 Global Styling
cat << 'EOF' > "$CONFIG_DIR/Trolltech.conf"
[Qt]
font="Google Sans Flex,11,-1,5,50,0,0,0,0,0,Regular"
style=adw-gtk3
fallbackFont="Sans Serif"
EOF

echo -e "${GREEN}✓ Theme, dark preference, icons, and font applied across GTK 3, GTK 4, Qt5, Qt6, and nwg-look.${NC}"

# ==========================================
# 5. Backup Existing Configs & Deploy
# ==========================================
echo -e "\n${YELLOW}[6/6] Backing up and deploying configurations...${NC}"
mkdir -p "$BACKUP_DIR"

for target in hypr quickshell colorschemes; do
    if [ -e "$CONFIG_DIR/$target" ]; then
        echo -e "Moving existing $CONFIG_DIR/$target -> $BACKUP_DIR/$target"
        mv "$CONFIG_DIR/$target" "$BACKUP_DIR/"
    fi
done

mkdir -p "$CONFIG_DIR"
cp -r "$DOTFILES_DIR/hypr" "$CONFIG_DIR/"
cp -r "$DOTFILES_DIR/quickshell" "$CONFIG_DIR/"

if [ -d "$DOTFILES_DIR/colorschemes" ]; then
    cp -r "$DOTFILES_DIR/colorschemes" "$CONFIG_DIR/"
    echo -e "${GREEN}✓ Wallpapers & colorschemes deployed to $CONFIG_DIR/colorschemes${NC}"
else
    echo -e "${YELLOW}Warning: colorschemes directory not found in repository.${NC}"
fi

echo -e "${GREEN}✓ Config files deployed to ~/.config${NC}"

# Clone Qylock and install 'Pixel Dusk City' SDDM theme
echo -e "\nInstalling 'Pixel Dusk City' SDDM theme from Qylock..."
QYLOCK_TEMP=$(mktemp -d)
git clone --depth=1 https://github.com/Darkkal44/qylock.git "$QYLOCK_TEMP"

THEME_SRC=$(find "$QYLOCK_TEMP" -maxdepth 3 -type d -iname "*Pixel*Dusk*City*" -o -iname "*dusk-city*" | head -n 1)

if [ -n "$THEME_SRC" ]; then
    THEME_NAME=$(basename "$THEME_SRC")
    sudo mkdir -p "/usr/share/sddm/themes/$THEME_NAME"
    sudo cp -r "$THEME_SRC/"* "/usr/share/sddm/themes/$THEME_NAME/"
    sudo chmod -R 755 "/usr/share/sddm/themes/$THEME_NAME"
    
    sudo mkdir -p /etc/sddm.conf.d
    echo -e "[Theme]\nCurrent=$THEME_NAME" | sudo tee /etc/sddm.conf.d/theme.conf > /dev/null
    echo -e "${GREEN}✓ SDDM theme '$THEME_NAME' installed and enabled.${NC}"
else
    echo -e "${RED}Warning: Could not locate Pixel Dusk City folder inside Qylock repo.${NC}"
fi

rm -rf "$QYLOCK_TEMP"

echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}        Installation Complete Successfully! 🎉   ${NC}"
echo -e "${GREEN}================================================${NC}"
echo -e "You can now start Hyprland or restart SDDM to enjoy your desktop!"
