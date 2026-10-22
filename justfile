# Show available recipes
[private]
default:
    @just --list

# Enroll the akmods Secure Boot MOK key - run in sudo
key:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$EUID" -ne 0 ]; then
        echo -e "\033[0;31m Error: Please run this recipe with sudo!\033[0m"
        exit 1
    fi

    CERT=/etc/pki/akmods/certs/public_key.der

    # Tools required by the RPM Fusion howto
    dnf install -y kmodtool akmods mokutil openssl

    # Generate the keypair only if the cert is missing
    # (akmods-keygen creates it automatically on the first akmods build)
    if [ ! -f "${CERT}" ]; then
        kmodgenca -a
        echo -e "\033[0;32m-> Generated keypair in /etc/pki/akmods\033[0m"
    fi

    # Queue the key for MOK enrollment, it gets applied on the next boot
    mokutil --import "${CERT}"

    echo "Remember the password you just set. On the next boot MOK Management will"
    echo "ask for it: Enroll MOK -> Continue -> Yes -> password (QWERTY keyboard!)."
    echo ""
    echo -e "\033[0;33m-> Reboot to enroll: systemctl reboot\033[0m"
    echo "After reboot verify with:"
    echo "  sudo mokutil --test-key ${CERT}"
    echo "  modinfo -F signer nvidia   # signer should be this machine's key"

# Installation for MSI GE60 2PL
msi:
    sudo ./install-msige602pl

# Normal Installation
install:
    sudo ./install
