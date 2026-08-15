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
color_echo "blue" "[2/5] Setting the system hostname..."
while true; do
    echo -n "Please enter the hostname you want to set: "
    read new_hostname

    # Check if it is empty
    if [ -z "$new_hostname" ]; then
        color_echo "red" "Error: The hostname cannot be empty, please re-enter!"
        echo "--------------------------------"
        continue # End the current loop and let the user enter again
    fi

    # Check if it contains illegal characters 
    # Only letters, numbers, underscores, and hyphens are allowed
    if [[ ! "$new_hostname" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        color_echo "red" "Error: The hostname format is incorrect!"
        color_echo "yellow"  "Hint: Can only contain letters, numbers, underscores (_), or hyphens (-), and no spaces."
        echo "--------------------------------"
        continue
    fi

    # If all the checks pass, break the loop
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

    # dnf5 auto-selects the fastest mirror; only parallel downloads need tuning
    dnf config-manager setopt max_parallel_downloads=20
    dnf config-manager setopt minrate=2M
    dnf config-manager setopt timeout=10
    color_echo "green" "-> Complete (parallel download=20)"
else
    color_echo "red" "-> Error: /etc/dnf/dnf.conf configuration file not found!"
fi

# ---------------------------------------------------------------------
# 4. Enable RPM Fusion repository, Multimedia decoder, Nvidia driver detection
# ---------------------------------------------------------------------
color_echo "blue" "[4/5] Enabling RPM Fusion and completing system multimedia decoders..."
# Enable Fedora's OpenH264 repo (H.264 codec for Firefox)
dnf config-manager setopt fedora-cisco-openh264.enabled=1
# Use dynamic mirror source to ensure optimal routing.
dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
dnf install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf install -y 'rpmfusion-*-appstream-data'

# Replace Fedora's restricted ffmpeg-free package with the full FFmpeg package.
dnf swap ffmpeg-free ffmpeg --allowerasing -y
dnf install @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin -y


# ---------------------------------------------------------------------
# 5. Installation of core applications and tools
# ---------------------------------------------------------------------
color_echo "blue" "[5/5] Installing dnf packages..."
# WM
dnf install -y niri

# Flatpak & locale
dnf install -y flatpak glibc-langpack-zh glibc-langpack-en

# AppImage support
dnf install -y fuse fuse-libs

# Network CLI & Sync
dnf install -y git wget curl rsync thefuck

# Fastfetch, Vaapi, Sound, Printer&Scanner for Canon e400 series, Fcitx5
dnf install -y libva-intel-driver  pipewire wireplumber alsa-utils usbutils cups gutenprint gutenprint-cups sane-backends fcitx5 fcitx5-rime fcitx5-gtk fcitx5-qt

# Add user to lp group
usermod -aG lp "$ACTUAL_USER"
# Enable Printer service
systemctl enable --now cups

# === Enable COPR ===
dnf copr enable lihaohong/yazi -y
dnf copr enable imput/helium -y
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
dnf install -y firefox google-chrome-stable vlc yazi xournalpp helium-bin

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
