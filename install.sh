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
    dnf config-manager setopt max_parallel_downloads=20 minrate=2M timeout=10
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
dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release

# --- Terra Mesa subrepo (optional) ---
color_echo "blue" "Terra Mesa subrepo provides Mesa build with OGC patches and more features enabled (docs.terrapkg.com). "
color_echo "blue" "Note: remove any mesa-*-freeworld from RPM Fusion before installing."
read -p "Enable Terra Mesa subrepo (terra-release-mesa)? [y/N]: " enable_mesa
if [[ "$enable_mesa" =~ ^[Yy]$ ]]; then
    color_echo "blue" "-> Enabling terra-mesa..."
    dnf install -y terra-release-mesa
    color_echo "blue" "-> Upgrading from terra-mesa..."
    dnf upgrade --repo=terra-mesa -y
    color_echo "green" "-> Terra Mesa subrepo enabled and upgraded"
else
    color_echo "yellow" "-> Skipped Terra Mesa subrepo"
fi

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
    while true; do
        read -p "Select 1/2: " nvidia_choice
        case "$nvidia_choice" in
            1) dnf install -y akmod-nvidia-580xx nvidia-driver-580xx; color_echo "green" "-> NVIDIA 580 driver installed"; break ;;
            2) dnf install -y akmod-nvidia nvidia-driver; color_echo "green" "-> NVIDIA latest driver installed"; break ;;
            *) color_echo "red" "Invalid choice, please enter 1 or 2." ;;
        esac
    done
    color_echo "blue" "-> Installing NVIDIA hardware acceleration..."
    dnf install -y libva-nvidia-driver
    color_echo "green" "-> libva-nvidia-driver installed"
fi

# --- Intel VAAPI driver ---
intel_gpu_info=$(lspci 2>/dev/null | grep -i "intel" | grep -i -E "graphics|vga|display|arc" || true)
if [ -z "$intel_gpu_info" ]; then
    color_echo "yellow" "-> No Intel GPU detected, skipping Intel VAAPI driver prompt"
else
    color_echo "blue" "Intel GPU detected: $intel_gpu_info"
    color_echo "blue" "Select Intel VAAPI driver:"
    color_echo "blue" "[1] Older : 1st-4th Gen, HD 2000/3000/4000"
    color_echo "blue" "[2] Recent: 5th Gen+ / Core Ultra / Arc"
    while true; do
        read -p "Select 1/2: " intel_choice
        case "$intel_choice" in
            1) dnf install -y libva-intel-driver; color_echo "green" "-> libva-intel-driver installed"; break ;;
            2) dnf install -y intel-media-driver; color_echo "green" "-> intel-media-driver installed"; break ;;
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

BASE_PKGS=(
    ly terminus-fonts umbriel-nightly noctalia gnome-keyring gnome-keyring-pam # login manager,wm,shell,keyring, ly font fix Lat2-Terminus16
    flatpak glibc-langpack-zh glibc-langpack-en # Flatpak & locale
    fuse fuse-libs # AppImage support
    fastfetch usbutils git wget curl rsync #  tools
    pipewire wireplumber alsa-utils  # Sound
    cups gutenprint gutenprint-cups sane-backends # Printer&Scanner for Canon e400 series
    fcitx5 fcitx5-rime fcitx5-gtk fcitx5-qt librime librime-lua librime-octagram # fcitx5
)
dnf install -y "${BASE_PKGS[@]}"

# --- Configure ly (TUI display manager, from fedora-niri) ---
# Fresh install has no fedora-niri checkout, so embed service content directly
if rpm -q ly >/dev/null 2>&1; then
    mkdir -p /etc/ly
    tee /etc/systemd/system/ly.service > /dev/null <<'LYEOF'
[Unit]
Description=TUI display manager
After=systemd-user-sessions.service plymouth-quit-wait.service
After=getty@tty2.service

[Service]
Type=idle
ExecStartPre=/usr/bin/printf '%%b' '\e]P011121D\e]P7A9B1D6\ec'
ExecStartPre=-/usr/bin/setfont -C /dev/tty2 Lat2-Terminus16
ExecStart=/usr/bin/ly
StandardInput=tty
TTYPath=/dev/tty2
TTYReset=yes
TTYVHangup=yes

[Install]
WantedBy=multi-user.target
LYEOF
    systemctl daemon-reload
    systemctl enable ly.service
    systemctl disable getty@tty2.service 2>/dev/null || true
    color_echo "green" "-> ly enabled (TUI DM on tty2, getty@tty2 disabled)"
else
    color_echo "yellow" "-> ly not installed, skipping ly.service enable"
fi

# Add user to lp group
usermod -aG lp "$ACTUAL_USER"
# Enable Printer service
systemctl enable --now cups

# === Enable COPR ===
COPR_REPOS=(
    "lihaohong/yazi"
    "imput/helium"
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

# === Personal Software ===
dnf makecache
dnf install -y firefox google-chrome-stable vlc yazi xournalpp helium-bin nemo kitty

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
    "com.github.flxzt.rnote"
)
# Install
su - "$ACTUAL_USER" -c "flatpak install --user -y flathub ${FLATPAK_APPS[*]}"
# Automatically fix potential flatpak permission tree issues
su - "$ACTUAL_USER" -c "flatpak repair --user" 2>/dev/null

echo ""
color_echo "green" "======================================================="
color_echo "green" "Setup complete."
color_echo "green" "======================================================="

# 询问重启
read -p "Reboot(y/n): " reboot_choice
if [[ $reboot_choice =~ ^[Yy]$ ]]; then
    color_echo "green" "Rebooting..."
    reboot
else
    color_echo "blue" "The restart has been postponed. Please remember to manually restart the system later."
fi
