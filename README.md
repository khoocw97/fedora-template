# fedora-template

Fresh-install setup script for Fedora (`install.sh`, must run as root). Hardware-aware: GPU sections activate only when `lspci` finds matching hardware.\
Use at your own risk.

## Usage

```bash
sudo ./install.sh
```

## Stages

1. **System upgrade** — `dnf up -y`

2. **Hostname** — interactive, `[a-zA-Z0-9_-]` only

3. **DNF tuning** — installs `dnf5-plugins`, `max_parallel_downloads=20 minrate=1M timeout=20`

4. **RPM Fusion + GPU drivers + Codec**
   - RPM Fusion free/nonfree + appstream data
   - **NVIDIA from negativo17's repo** (if detected): 
   > - choose `580 LTS` for Maxwell/Pascal or `latest` 
   > - Installs `nvidia-driver nvidia-settings nvidia-driver-cuda akmod-nvidia nvidia-driver-libs.i686` + `libva-nvidia-driver`
   - **AMD from rpmfusion-free** (if detected):
   > - Installs `mesa-vulkan-drivers{,-freeworld} mesa-vulkan-drivers{,-freeworld}.i686`
   > - Swap `mesa-vulkan-drivers{,-freeworld} mesa-vulkan-drivers{,-freeworld}.i686` 
   - **Intel from rpmfusion-nonfree** (if detected): 
   > - choose `libva-intel-driver{,.i686}` → 1st–4th Gen  or `libva-intel-media-driver{,.i686}` → 5th Gen+/Core Ultra/Arc 
   - 32-bit (`i686`) drivers included for Steam
   - Replace ffmpeg-free package with the full FFmpeg package 
   
5. **Apps & desktop**
   - Repo & COPR: `lihaohong/yazi`, `imput/helium`, `khoocw97/software`; Google Chrome repo; MegaCMD
   
   - Base tools, keyring, themes, Flatpak, locales, AppImage (`fuse`), PipeWire, printing (Canon e400), fcitx5+rime, fonts (`maple-mono`, `lxgw`, `bibata`)
   
    - **Display manager**: `sddm`

   - **Compositor**: 
   > - `niri` + `noctalia` + `xwayland-satellite` (excludes `alacritty/waybar/mako/swaylock`; writes `niri-portals.conf` with GTK file chooser for `nemo`) 
   > - `umbriel` + `noctalia` + `xwayland-satellite`

   - Personal RPMs: 
   > - `firefox google-chrome-stable vlc yazi xournalpp helium-bin nemo kitty`
   - Optional DVD support (`libdvdcss`, tainted repo)
   - Flatpak (per-user Flathub): 
   > - `OnlyOffice, OBS (+Gstreamer/VAAPI plugins), Flatseal, Gearlever, pdfarranger, LocalSend, Loupe, Cine, Rnote, Bazaar, Warehouse, MissionCenter, ProtonVPN`
