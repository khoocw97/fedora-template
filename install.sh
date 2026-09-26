#!/bin/bash
# =====================================================================
# Fedora System Optimization, Hardware Setup & Application Installer
# =====================================================================

# Ensure the script runs with root/sudo privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m Error: Please run this script with sudo!\033[0m"
    exit 1
fi

# Color output function
color_echo() {
    local color="$1"
    local text="$2"
    case "$color" in
        "red")    echo -e "\033[0;31m$text\033[0m" ;;
        "green")  echo -e "\033[0;32m$text\033[0m" ;;
        "yellow") echo -e "\033[1;33m$text\033[0m" ;;
        "blue")   echo -e "\033[0;34m$text\033[0m" ;;
        *)        echo "$text" ;;
    esac
}

# Basic variable definition
ACTUAL_USER=${SUDO_USER:-$(logname 2>/dev/null)}

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║             FEDORA SYSTEM INTEGRATED SETUP SCRIPT             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo "Preparing to configure the system for regular user: $ACTUAL_USER..."
echo ""

# ---------------------------------------------------------------------
# 1. System upgrade
# ---------------------------------------------------------------------
color_echo "blue" "[1/5] Performing a system upgrade (this may take some time)..."
dnf up -y

# ---------------------------------------------------------------------
# 2. Set Hostname
# ---------------------------------------------------------------------
color_echo "blue" "[2/5] Setting the system hostname (only letters, numbers, _, -; no spaces)..."
while true; do
    read -p "Please enter hostname: " new_hostname
    if [ -z "$new_hostname" ]; then
        color_echo "red" "Error: cannot be empty."
        continue
    fi
    if [[ ! "$new_hostname" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        color_echo "red" "Error: only letters, numbers, _ or - allowed."
        continue
    fi
    break
done
color_echo "green" "Changing the hostname to: $new_hostname ..."
hostnamectl set-hostname "$new_hostname"

# ---------------------------------------------------------------------
# 3. Optimized DNF package manager
# ---------------------------------------------------------------------
color_echo "blue" "[3/5] Optimizing DNF configuration files..."
if [ -f /etc/dnf/dnf.conf ]; then
    # dnf5-plugins provides copr/config-manager for dnf5 (Fedora 41+)
    dnf install -y dnf5-plugins
    dnf config-manager setopt max_parallel_downloads=20 minrate=1M timeout=20
    color_echo "green" "-> Complete (parallel download=20)"
else
    color_echo "red" "-> Error: /etc/dnf/dnf.conf configuration file not found!"
fi

# ---------------------------------------------------------------------
# 4. Enable RPM Fusion & Terra repo / Multimedia decoder / Intel & AMD & Nvidia
# ---------------------------------------------------------------------
color_echo "blue" "[4/5] Enabling RPM Fusion and completing system multimedia decoders..."
# Enable Fedora's OpenH264 repo (H.264 codec for Firefox)
# dnf config-manager setopt fedora-cisco-openh264.enabled=1
dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
dnf install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf install -y 'rpmfusion-*-appstream-data'

# --- lspci install ---
command -v lspci >/dev/null 2>&1 || dnf install -y pciutils

# --- NVIDIA driver (hardware-aware, lspci) ---
nvidia_gpu_info=$(lspci 2>/dev/null | grep -i nvidia || true)
if [ -z "$nvidia_gpu_info" ]; then
    color_echo "yellow" "-> No NVIDIA GPU detected, skipping NVIDIA driver prompt"
else
    color_echo "blue" "NVIDIA GPU detected: $nvidia_gpu_info"
    color_echo "blue" "Select NVIDIA driver branch:"
    color_echo "blue" "[1] driver-580: Maxwell and Pascal"
    color_echo "blue" "[2] latest    : Current GeForce/Quadro/Tesla"
    NVIDIA_PKGS="nvidia-driver nvidia-settings nvidia-driver-cuda akmod-nvidia nvidia-driver-libs.i686"
    while true; do
        read -p "Select 1/2: " nvidia_choice
        case "$nvidia_choice" in
            1)
                dnf config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-nvidia-580.repo
                dnf config-manager setopt fedora-nvidia-580.priority=90
                color_echo "green" "-> NVIDIA 580 (LTS) repo enabled"
                break ;;
            2)
                dnf config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-nvidia.repo
                dnf config-manager setopt fedora-nvidia.priority=90
                color_echo "green" "-> NVIDIA latest repo enabled"
                break ;;
            *) color_echo "red" "Invalid choice, please enter 1 or 2." ;;
        esac
    done
    color_echo "blue" "-> Installing NVIDIA driver and CUDA components..."
    dnf install -y $NVIDIA_PKGS
    color_echo "blue" "-> Installing NVIDIA hardware acceleration..."
    dnf install -y libva-nvidia-driver
    color_echo "green" "-> NVIDIA driver and libva-nvidia-driver installed"
fi

# --- AMD mesa freeworld (hardware-aware, lspci) ---
amd_gpu_info=$(lspci 2>/dev/null | grep -i -E "amd|radeon" | grep -i -E "graphics|vga|display" || true)
if [ -z "$amd_gpu_info" ]; then
    color_echo "yellow" "-> No AMD GPU detected, skipping AMD mesa freeworld swap"
else
    color_echo "blue" "AMD GPU detected: $amd_gpu_info"
    color_echo "blue" "-> Installing mesa freeworld drivers..."
    dnf install -y mesa-va-drivers-freeworld mesa-va-drivers-freeworld.i686
    dnf swap -y mesa-vulkan-drivers{,-freeworld}
    dnf swap -y mesa-vulkan-drivers{,-freeworld}.i686
    color_echo "green" "-> mesa freeworld installed"
fi

# --- Intel VAAPI driver ---
intel_gpu_info=$(lspci 2>/dev/null | grep -i "intel" | grep -i -E "graphics|vga|display|arc" || true)
if [ -z "$intel_gpu_info" ]; then
    color_echo "yellow" "-> No Intel GPU detected, skipping Intel VAAPI driver prompt"
else
    color_echo "blue" "Intel GPU detected: $intel_gpu_info"
    color_echo "blue" "Select Intel VAAPI driver (hardware acceleration):"
    color_echo "blue" "[1] Older : 1st-4th Gen, HD 2000/3000/4000"
    color_echo "blue" "[2] Recent: 5th Gen+ / Core Ultra / Arc"
    while true; do
        read -p "Select 1/2: " intel_choice
        case "$intel_choice" in
            1) dnf install -y libva-intel-driver libva-intel-driver.i686; color_echo "green" "-> libva-intel-driver installed"; break ;;
            2) dnf install -y libva-intel-media-driver libva-intel-media-driver.i686; color_echo "green" "-> libva-intel-media-driver installed"; break ;;
            *) color_echo "red" "Invalid choice, please enter 1 or 2." ;;
        esac
    done
fi

# Replace ffmpeg-free package with the full FFmpeg package.
dnf swap ffmpeg-free ffmpeg --allowerasing -y
dnf install @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin -y

# ---------------------------------------------------------------------
# 5. Installation of core applications and tools
# ---------------------------------------------------------------------
color_echo "blue" "[5/5] Installing dnf packages..."

# === Enable COPR ===
COPR_REPOS=(
    "lihaohong/yazi"
    "imput/helium"
    "khoocw97/software"
)
for repo in "${COPR_REPOS[@]}"; do
    dnf copr enable "$repo" -y
done

# === Create Google-Chrome Repo ===
tee /etc/yum.repos.d/google-chrome.repo > /dev/null << 'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF

# === Enable Mega-CLI ===
FEDORA_VERSION=$(rpm -E %fedora)
dnf install -y "https://mega.nz/linux/repo/Fedora_${FEDORA_VERSION}/x86_64/megacmd-Fedora_${FEDORA_VERSION}.x86_64.rpm"

BASE_PKGS=(
    ddcutil brightnessctl fastfetch usbutils git wget curl rsync chezmoi make #  tools
    gnome-keyring gnome-keyring-pam # keyring
    adw-gtk3-theme qt5ct qt6ct # unified theme
    flatpak glibc-langpack-zh glibc-langpack-en # Flatpak & locale
    fuse fuse-libs # AppImage support
    pipewire wireplumber alsa-utils  # Sound
    cups gutenprint gutenprint-cups sane-backends # Printer&Scanner for Canon e400 series
    fcitx5 fcitx5-rime fcitx5-gtk fcitx5-qt librime librime-lua librime-octagram # fcitx5
    maple-mono-fonts lxgw-fonts bibata-cursor-themes # from khoocw97's repo
)
dnf install -y "${BASE_PKGS[@]}"

# --- Display manager: sddm ---
dnf install -y sddm qt6-qtdeclarative qt6-qtquickcontrols2 sddm-themes
systemctl enable sddm
systemctl set-default graphical.target
color_echo "green" "-> sddm installed"

# --- SDDM theme: simple-sddm ---
color_echo "blue" "-> Installing simple-sddm theme..."
SDDM_THEME_DIR=/usr/share/sddm/themes/simple-sddm
SDDM_TMP=$(mktemp -d)
if git clone --depth=1 https://github.com/khoocw97/simple-sddm.git "$SDDM_TMP"; then
    install -d "$SDDM_THEME_DIR"
    install -m 644 "$SDDM_TMP/metadata.desktop" "$SDDM_TMP/Main.qml" "$SDDM_THEME_DIR"/
    install -m 644 "$SDDM_TMP/preview/preview1.png" "$SDDM_THEME_DIR"/preview.png

    # Custom theme config lives in /etc; symlink it into the theme dir
    install -d /etc/sddm/themes/simple-sddm
    tee /etc/sddm/themes/simple-sddm/theme.conf > /dev/null <<'SDDMEOF'
[General]
# background=#0a0a0a  |  background=background.jpg  |  background=/usr/share/backgrounds/default.jpg
# TokyoNight Night #1a1b26 / Storm #24283b / Moon #222436
background=#13282b

# date / clock
showDate=true
dateFormat=dddd dd/MM/yyyy
showClock=true
clock12hr=true
clockSeconds=true

# box
hideBorders=false
boxBackground=true
boxBackgroundColor=#233b3f

# function key,
# show do not disable key, just not showing it
showShutdownKey=true
shutdownKey=F1
showRebootKey=true
rebootKey=F2
showPasswordToggleKey=true
passwordToggleKey=F7

# font
fontFamily=
fontSize=15
boxFontSize=15

# primaryScreen: empty=show on all (default) | eDP-1/HDMI-A-1=only that output (exact, case-sensitive), unknown falls back to system primary screen
primaryScreen=

# session / user / password
defaultInput=password

# input length (box width based on inputLen)
inputLen=20

# default show nothing,linux style, this echoes * per character
asterisk=*
SDDMEOF
    ln -sf /etc/sddm/themes/simple-sddm/theme.conf "$SDDM_THEME_DIR/theme.conf"

    # Select theme (comment any stale Current= in /etc/sddm.conf, it overrides sddm.conf.d)
    install -d /etc/sddm.conf.d
    printf '[Theme]\nCurrent=simple-sddm\n' > /etc/sddm.conf.d/10-simple-sddm.conf
    [ -f /etc/sddm.conf ] && sed -i 's/^[[:space:]]*Current[[:space:]]*=/#&/' /etc/sddm.conf

    color_echo "green" "-> simple-sddm theme installed"
else
    color_echo "red" "-> Failed to clone simple-sddm, theme not installed"
fi
rm -rf "$SDDM_TMP"

# --- Compositor: niri or umbriel ---
color_echo "blue" "Select compositor:"
color_echo "blue" "[1] niri    : + noctalia shell"
    color_echo "blue" "[2] umbriel : + noctalia shell"
while true; do
    read -p "Select 1/2: " wm_choice
    case "$wm_choice" in
        1)
            dnf install -y niri noctalia xwayland-satellite --exclude=alacritty,waybar,mako,swaylock
            tee /usr/share/xdg-desktop-portal/niri-portals.conf > /dev/null <<'PORTALEOF'
[preferred]
default=gnome;gtk;
org.freedesktop.impl.portal.Access=gtk;
org.freedesktop.impl.portal.FileChooser=gtk;
org.freedesktop.impl.portal.Notification=gtk;
org.freedesktop.impl.portal.Secret=gnome-keyring;
PORTALEOF
            color_echo "green" "-> niri + noctalia installed (GTK file chooser)"
            break ;;
        2)
            dnf install -y umbriel noctalia xwayland-satellite
            color_echo "green" "-> umbriel installed"
            break ;;
        *) color_echo "red" "Invalid choice, please enter 1 or 2." ;;
    esac
done

# Add user to lp group
usermod -aG lp "$ACTUAL_USER"
# Enable Printer service
systemctl enable --now cups

# === Personal Software ===
dnf makecache
dnf install -y firefox google-chrome-stable vlc yazi xournalpp helium-bin nemo kitty kdeconnectd

# === DVD Playback Support (optional) ===
color_echo "blue" "DVD playback requires RPM Fusion tainted repository and libdvdcss (may be restricted in some countries per RPM Fusion: Tainted free is for FLOSS packages where usage might be restricted in some countries)."
read -p "Install DVD playback support (libdvdcss)? [y/N]: " install_dvd
if [[ "$install_dvd" =~ ^[Yy]$ ]]; then
    color_echo "blue" "-> Enabling rpmfusion-free-tainted and installing libdvdcss..."
    dnf install -y rpmfusion-free-release-tainted
    dnf install -y libdvdcss
    color_echo "green" "-> DVD support installed (libdvdcss)"
else
    color_echo "yellow" "-> Skipped DVD support"
fi

# =====================================================================
# Application configuration area for non-ROOT user environments (Flatpak/Flathub)
# =====================================================================
echo ""
color_echo "blue" "Starting to hand over the configuration of Flatpak without permissions to the normal user environment..."

# Initialize and add Flathub as a normal user.
su - "$ACTUAL_USER" -c "flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"

# Define the list of Flatpak software to be installed.
FLATPAK_APPS=(
    "org.onlyoffice.desktopeditors"
    "com.obsproject.Studio"
    "com.github.tchx84.Flatseal"
    "it.mijorus.gearlever"
    "com.github.jeromerobert.pdfarranger"
    "org.localsend.localsend_app"
    "org.gnome.Loupe"
    "io.github.diegopvlk.Cine"
    "com.github.flxzt.rnote"
    "com.obsproject.Studio.Plugin.Gstreamer"
    "com.obsproject.Studio.Plugin.GStreamerVaapi"
    "io.github.kolunmi.Bazaar"
    "io.github.flattool.Warehouse"
    "io.missioncenter.MissionCenter"
    "com.protonvpn.www"
)
# Install
su - "$ACTUAL_USER" -c "flatpak install --user -y flathub ${FLATPAK_APPS[*]}"
# Automatically fix potential flatpak permission tree issues
su - "$ACTUAL_USER" -c "flatpak repair --user" 2>/dev/null

echo ""
color_echo "green" "======================================================="
color_echo "green" "Setup complete."
color_echo "green" "======================================================="

# --- Reboot ---
read -p "Reboot(y/n): " reboot_choice
if [[ $reboot_choice =~ ^[Yy]$ ]]; then
    color_echo "green" "Rebooting..."
    reboot
else
    color_echo "blue" "The restart has been postponed. Please remember to manually restart the system later."
fi
