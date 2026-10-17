# Fedora DNF setup & optimization
# Extracted from install.sh
#   [3/5] Optimized DNF package manager
#   [4/5] Enable RPM Fusion
#   ----  Pin Fedora + RPM Fusion repos to a single fast mirror
#
# Order matters: RPM Fusion must be installed BEFORE the Fedora mirror is
# pinned. Pinning the mirror first breaks repo resolution for the RPM Fusion
# release packages, so `mirror` depends on `rpmfusion`.
#
# Both Fedora and RPM Fusion repos are re-pointed to the twds mirror:
#   - rpmfusion repos are pinned inside `rpmfusion` (right after install)
#   - fedora repos are pinned inside `mirror`

# Show available recipes
default:
    @just --list

# Enable RPM Fusion free / nonfree repos and pin them to the mirror
rpmfusion:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$EUID" -ne 0 ]; then
        echo -e "\033[0;31m Error: Please run this recipe with sudo!\033[0m"
        exit 1
    fi

    RPMFUSION_MIRROR="https://mirror.twds.com.tw/rpmfusion"
    # Enable Fedora's OpenH264 repo (H.264 codec for Firefox)
    # dnf config-manager setopt fedora-cisco-openh264.enabled=1
    dnf install -y "${RPMFUSION_MIRROR}/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
    dnf install -y "${RPMFUSION_MIRROR}/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
    dnf install -y 'rpmfusion-*-appstream-data'
    # Pin rpmfusion repos to the mirror (disable metalink/mirrorlist, enable baseurl)
    # NOTE: on dnf5-based Fedora the vendor repo files live in /usr/share/dnf5/repos.d,
    # while /etc/yum.repos.d only holds admin-added repos. Check both locations.
    shopt -s nullglob
    RPMFUSION_REPOS=(/etc/yum.repos.d/rpmfusion*.repo /usr/share/dnf5/repos.d/rpmfusion*.repo)
    if ((${#RPMFUSION_REPOS[@]} == 0)); then
        echo -e "\033[1;33m-> Warning: no rpmfusion repo files found, skipping pin\033[0m"
    else
        sed -e 's!^metalink=!#metalink=!g' \
            -e 's!^mirrorlist=!#mirrorlist=!g' \
            -e 's!^#baseurl=!baseurl=!g' \
            -e "s!http://download1.rpmfusion.org!${RPMFUSION_MIRROR}!g" \
            -e "s!https://download1.rpmfusion.org!${RPMFUSION_MIRROR}!g" \
            -i.bak "${RPMFUSION_REPOS[@]}"
        echo -e "\033[0;32m-> RPM Fusion repos pinned to $RPMFUSION_MIRROR\033[0m"
    fi

# Pin Fedora repos to a single fast mirror (run only after RPM Fusion install)
mirror: rpmfusion
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$EUID" -ne 0 ]; then
        echo -e "\033[0;31m Error: Please run this recipe with sudo!\033[0m"
        exit 1
    fi

    FEDORA_MIRROR="https://mirror.twds.com.tw/fedora/fedora/linux"
    # NOTE: same dual-location lookup as in `rpmfusion`. On Rawhide the active
    # repo is fedora-rawhide.repo (fedora.repo/updates are disabled there),
    # so it must be included or the pin is a no-op.
    FEDORA_REPOS=()
    for repo_dir in /etc/yum.repos.d /usr/share/dnf5/repos.d; do
        for repo_file in fedora.repo fedora-updates.repo fedora-rawhide.repo; do
            [ -f "$repo_dir/$repo_file" ] && FEDORA_REPOS+=("$repo_dir/$repo_file")
        done
    done
    if ((${#FEDORA_REPOS[@]} == 0)); then
        echo -e "\033[1;33m-> Warning: no Fedora repo files found, skipping pin\033[0m"
    else
        sed -e 's|^metalink=|#metalink=|g' \
            -e "s|^#baseurl=http://download.example/pub/fedora/linux|baseurl=${FEDORA_MIRROR}|g" \
            -i.bak "${FEDORA_REPOS[@]}"
        echo -e "\033[0;32m-> Fedora repos pinned to $FEDORA_MIRROR (metalink disabled)\033[0m"
    fi

# Install dnf5 plugins and apply DNF optimization settings (after RPM Fusion)
optimize: rpmfusion
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$EUID" -ne 0 ]; then
        echo -e "\033[0;31m Error: Please run this recipe with sudo!\033[0m"
        exit 1
    fi

    if [ -f /etc/dnf/dnf.conf ]; then
        # dnf5-plugins provides copr/config-manager for dnf5 (Fedora 41+)
        dnf install -y dnf5-plugins
        dnf config-manager setopt max_parallel_downloads=20 minrate=1M timeout=20
        echo -e "\033[0;32m-> Complete (parallel download=20)\033[0m"
    else
        echo -e "\033[0;31m-> Error: /etc/dnf/dnf.conf configuration file not found!\033[0m"
        exit 1
    fi

# Full flow: install RPM Fusion, pin the mirror, then optimize DNF
setup: rpmfusion mirror optimize
