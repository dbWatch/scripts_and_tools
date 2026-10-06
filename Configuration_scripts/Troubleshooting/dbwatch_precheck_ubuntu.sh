#!/bin/bash

# Purpose:
# This script verifies and configures requirements for running
# dbWatch Control Center Server on Debian/Ubuntu systems.
#
# Developed for dbWatch AS.
#
# Current dbWatch Linux package layout:
# - Server binary:
#     /opt/dbwatch-controlcenter/dbwatch_server
# - Vendor systemd service:
#     /usr/lib/systemd/system/dbwatch-controlcenter.service
# - Working directory:
#     /var/dbwatch-controlcenter
#
# X11 requirement:
# Some server-side report generation may require an X11 display.
# This script uses Xvfb, a virtual framebuffer X server, on display :99.
# It does not modify the vendor service file. Instead, it creates a
# systemd override under:
#     /etc/systemd/system/dbwatch-controlcenter.service.d/
#
# Run as root:
#     sudo ./dbwatch_precheck_ubuntu26.sh

set -u

DBWATCH_PACKAGE="dbwatch-controlcenter"
DBWATCH_SERVICE="dbwatch-controlcenter"
DBWATCH_BINARY="/opt/dbwatch-controlcenter/dbwatch_server"
DBWATCH_WORK="/var/dbwatch-controlcenter"
# Optional: used by dbWatch features that require the file upload directory.
UPLOAD_DIR="/opt/dbwatch-controlcenter/file-uploads"

XVFB_PACKAGE="xvfb"
XVFB_SERVICE="dbwatch-xvfb"
XVFB_SERVICE_FILE="/etc/systemd/system/${XVFB_SERVICE}.service"
XVFB_DISPLAY=":99"
XVFB_SCREEN="1920x1080x24"

DBWATCH_OVERRIDE_DIR="/etc/systemd/system/${DBWATCH_SERVICE}.service.d"
DBWATCH_OVERRIDE_FILE="${DBWATCH_OVERRIDE_DIR}/x11-display.conf"

# Check if running as root
if [ "${EUID}" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Check supported distribution/version
if [ ! -r /etc/os-release ]; then
    echo "Unable to determine operating system."
    exit 1
fi

. /etc/os-release

if [ "${ID:-}" != "ubuntu" ]; then
    echo "This script is intended for Ubuntu."
    echo "Detected: ${PRETTY_NAME:-unknown}"
    exit 1
fi

case "${VERSION_ID:-}" in
    24.04|26.04)
        echo "Supported Ubuntu version detected: ${PRETTY_NAME:-Ubuntu ${VERSION_ID}}"
        ;;
    *)
        echo "WARNING: Ubuntu ${VERSION_ID:-unknown} has not been explicitly tested."
        if ! prompt_yes_no "Continue anyway?"; then
            exit 1
        fi
        ;;
esac

check_package() {
    dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null \
        | grep -qx "install ok installed"
}

prompt_yes_no() {
    local prompt="$1"
    local choice

    read -r -p "${prompt} [yes/No]: " choice
    case "${choice}" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

install_package() {
    local package="$1"

    if check_package "${package}"; then
        echo "${package} is installed."
        return 0
    fi

    echo "${package} is not installed."
    if prompt_yes_no "Install ${package}?"; then
        apt-get update
        apt-get install -y "${package}"
    else
        echo "Skipping installation of ${package}."
        return 1
    fi
}

configure_xvfb() {
    if ! check_package "${XVFB_PACKAGE}"; then
        echo "Xvfb cannot be configured because ${XVFB_PACKAGE} is not installed."
        return 1
    fi

    echo "Writing ${XVFB_SERVICE_FILE}..."
    cat > "${XVFB_SERVICE_FILE}" <<EOF
[Unit]
Description=Virtual X11 display for dbWatch Control Center
After=network.target
Before=${DBWATCH_SERVICE}.service

[Service]
Type=simple
User=dbwatch
Group=dbwatch
ExecStart=/usr/bin/Xvfb ${XVFB_DISPLAY} -screen 0 ${XVFB_SCREEN} -nolisten tcp -noreset
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    mkdir -p "${DBWATCH_OVERRIDE_DIR}"

    echo "Writing ${DBWATCH_OVERRIDE_FILE}..."
    cat > "${DBWATCH_OVERRIDE_FILE}" <<EOF
[Unit]
Requires=${XVFB_SERVICE}.service
After=${XVFB_SERVICE}.service

[Service]
Environment=DISPLAY=${XVFB_DISPLAY}
EOF

    systemctl daemon-reload
    systemctl enable --now "${XVFB_SERVICE}"

    if systemctl is-active --quiet "${XVFB_SERVICE}"; then
        echo "${XVFB_SERVICE} is running on display ${XVFB_DISPLAY}."
    else
        echo "${XVFB_SERVICE} failed to start."
        echo "Check: journalctl -u ${XVFB_SERVICE} --no-pager"
        return 1
    fi
}

check_dbwatch_installation() {
    if ! check_package "${DBWATCH_PACKAGE}"; then
        echo "${DBWATCH_PACKAGE} is not installed."
        echo
        echo "Configure the dbWatch package repository using its current"
        echo "signed-by/keyring instructions, then install with:"
        echo "  apt-get update"
        echo "  apt-get install ${DBWATCH_PACKAGE}"
        return 1
    fi

    echo "${DBWATCH_PACKAGE} is installed."

    if [ -x "${DBWATCH_BINARY}" ]; then
        echo "Server binary found: ${DBWATCH_BINARY}"
    else
        echo "WARNING: Expected server binary was not found or is not executable:"
        echo "  ${DBWATCH_BINARY}"
    fi

    if systemctl cat "${DBWATCH_SERVICE}" >/dev/null 2>&1; then
        echo "Systemd service found: ${DBWATCH_SERVICE}.service"
    else
        echo "WARNING: Systemd service ${DBWATCH_SERVICE}.service was not found."
    fi

    if [ -d "${DBWATCH_WORK}" ]; then
        echo "Working directory found: ${DBWATCH_WORK}"
    else
        echo "WARNING: Working directory does not exist: ${DBWATCH_WORK}"
    fi
}

configure_upload_directory() {
    if [ ! -d "${UPLOAD_DIR}" ]; then
        echo "Creating ${UPLOAD_DIR}..."
        mkdir -p "${UPLOAD_DIR}"
    else
        echo "Upload directory already exists: ${UPLOAD_DIR}"
    fi

    chown dbwatch:dbwatch "${UPLOAD_DIR}"
    chmod 0750 "${UPLOAD_DIR}"

    echo "Upload directory ownership and permissions:"
    stat -c '  %U:%G %a %n' "${UPLOAD_DIR}"
}

check_for_dbwatch_upgrade() {
    if ! check_package "${DBWATCH_PACKAGE}"; then
        return 0
    fi

    apt-get update

    local installed_candidate
    installed_candidate="$(apt-cache policy "${DBWATCH_PACKAGE}" \
        | awk '/Installed:|Candidate:/ {print $1, $2}')"

    echo "${installed_candidate}"

    local installed
    local candidate
    installed="$(apt-cache policy "${DBWATCH_PACKAGE}" | awk '/Installed:/ {print $2}')"
    candidate="$(apt-cache policy "${DBWATCH_PACKAGE}" | awk '/Candidate:/ {print $2}')"

    if [ -n "${installed}" ] && [ -n "${candidate}" ] \
        && [ "${installed}" != "(none)" ] \
        && [ "${candidate}" != "(none)" ] \
        && dpkg --compare-versions "${candidate}" gt "${installed}"; then

        echo "A newer version of ${DBWATCH_PACKAGE} is available."

        if prompt_yes_no "Upgrade ${DBWATCH_PACKAGE} from ${installed} to ${candidate}?"; then
            systemctl stop "${DBWATCH_SERVICE}" 2>/dev/null || true
            apt-get install --only-upgrade -y "${DBWATCH_PACKAGE}"
            systemctl daemon-reload
            systemctl restart "${XVFB_SERVICE}"
            systemctl restart "${DBWATCH_SERVICE}"
        else
            echo "Skipping upgrade."
        fi
    else
        echo "${DBWATCH_PACKAGE} is up to date."
    fi
}

verify_services() {
    echo
    echo "Service status:"

    if systemctl is-active --quiet "${XVFB_SERVICE}"; then
        echo "  ${XVFB_SERVICE}: active"
    else
        echo "  ${XVFB_SERVICE}: inactive"
    fi

    if systemctl is-active --quiet "${DBWATCH_SERVICE}"; then
        echo "  ${DBWATCH_SERVICE}: active"
    else
        echo "  ${DBWATCH_SERVICE}: inactive"
    fi

    echo
    echo "Effective DISPLAY setting:"
    systemctl show "${DBWATCH_SERVICE}" -p Environment --no-pager \
        | tr ' ' '\n' \
        | grep '^DISPLAY=' \
        || echo "  DISPLAY is not currently present in the effective service environment."
}

echo "=== dbWatch Control Center precheck ==="

if ! id dbwatch >/dev/null 2>&1; then
    echo "WARNING: The dbwatch user does not currently exist."
    echo "Install ${DBWATCH_PACKAGE} before configuring Xvfb as the dbwatch user."
fi

install_package "${XVFB_PACKAGE}" || true

if id dbwatch >/dev/null 2>&1 && check_package "${XVFB_PACKAGE}"; then
    if [ -f "${XVFB_SERVICE_FILE}" ] && [ -f "${DBWATCH_OVERRIDE_FILE}" ]; then
        echo "Existing Xvfb and dbWatch systemd configuration found."
        if prompt_yes_no "Rewrite and restart the Xvfb configuration?"; then
            configure_xvfb
        else
            systemctl daemon-reload
            systemctl enable --now "${XVFB_SERVICE}" 2>/dev/null || true
        fi
    else
        if prompt_yes_no "Configure Xvfb display ${XVFB_DISPLAY} for dbWatch?"; then
            configure_xvfb
        else
            echo "Skipping Xvfb configuration."
        fi
    fi
fi

if check_dbwatch_installation; then
    echo
    if prompt_yes_no "Configure/check the optional dbWatch upload directory (${UPLOAD_DIR})?"; then
        configure_upload_directory
    else
        echo "Skipping upload directory configuration."
    fi

    check_for_dbwatch_upgrade

    # Restart to apply the DISPLAY override when Xvfb is configured.
    if [ -f "${DBWATCH_OVERRIDE_FILE}" ] \
        && systemctl is-active --quiet "${XVFB_SERVICE}"; then
        systemctl restart "${DBWATCH_SERVICE}"
    fi
fi

verify_services

echo
echo "Precheck completed."
echo "Useful diagnostics:"
echo "  systemctl status ${XVFB_SERVICE} ${DBWATCH_SERVICE}"
echo "  journalctl -u ${XVFB_SERVICE} -u ${DBWATCH_SERVICE} --since today"
echo "  systemctl show ${DBWATCH_SERVICE} -p Environment"
