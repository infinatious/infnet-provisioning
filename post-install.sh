#!/usr/bin/env bash
set -euo pipefail

PS1_VALUE='\[\e[38;5;140m\][\[\e[38;5;206m\]\t\[\e[0m\] \[\e[38;5;76m\]\u@\[\e[38;5;36;1m\]\h\[\e[0m\] \[\e[38;5;39m\]\w\[\e[38;5;141m\]]\[\e[0m\] '

if [[ -d /home/kauffpc ]]; then
  BASHRC_FILE="/home/kauffpc/.bashrc"
  PROFILE_FILE="/home/kauffpc/.profile"
  if ! grep -q 'INFNET_CUSTOM_PS1' "${BASHRC_FILE}" 2>/dev/null; then
    cat <<'EOF' >> "${BASHRC_FILE}"
# INFNET_CUSTOM_PS1
PS1='\[\e[38;5;140m\][\[\e[38;5;206m\]\t\[\e[0m\] \[\e[38;5;76m\]\u@\[\e[38;5;36;1m\]\h\[\e[0m\] \[\e[38;5;39m\]\w\[\e[38;5;141m\]]\[\e[0m\] '
EOF
  fi
  if ! grep -q 'INFNET_CUSTOM_PS1' "${PROFILE_FILE}" 2>/dev/null; then
    printf '%s\n' '# INFNET_CUSTOM_PS1' "PS1='${PS1_VALUE}'" >> "${PROFILE_FILE}"
  fi
  chown kauffpc:kauffpc "${BASHRC_FILE}" "${PROFILE_FILE}"
fi

if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo 'Error: unable to detect OS release.' >&2
  exit 1
fi

case "${ID,,}" in
  almalinux|rocky|centos)
    echo 'fastestmirror=true' >> /etc/dnf/dnf.conf
    echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf
    echo 'defaultyes=True' >> /etc/dnf/dnf.conf
    dnf update -y
    dnf install epel-release -y
    dnf install open-vm-tools -y
    dnf install nfs-utils -y
    dnf install htop -y
    dnf install btop -y
    dnf install vim-enhanced -y
    dnf install git -y
    dnf install wget -y
    dnf install make -y
    dnf install gcc -y
    dnf install links -y
    dnf install curl -y
    dnf install jq -y
    dnf install dnf-automatic -y
    sed -i 's/^apply_updates =.*/apply_updates = yes/' /etc/dnf/automatic.conf
    sed -i 's/^download_updates =.*/download_updates = yes/' /etc/dnf/automatic.conf
    sed -i 's/^upgrade_type =.*/upgrade_type = security/' /etc/dnf/automatic.conf
    systemctl enable --now dnf-automatic.timer
    ;;
  ubuntu|debian)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get upgrade -y
    apt-get install -y open-vm-tools nfs-common htop btop vim git wget make gcc links curl jq unattended-upgrades apt-listchanges
    cat <<'EOF' > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
    cat <<'EOF' > /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Allowed-Origins {
  "${distro_id}:${distro_codename}-security";
  "${distro_id}:${distro_codename}-updates";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
    systemctl enable --now unattended-upgrades
    ;;
  *)
    echo "Unsupported OS: ${ID}" >&2
    exit 1
    ;;
esac

install_infnet_root_ca() {
  local url='http://certificates.infinatious.com/infinatious-root-ca.crt'
  local want='5F:92:DF:75:78:38:1C:BF:AA:00:E3:66:98:8C:18:06:88:CE:EC:C2:89:5B:05:A7:64:42:AE:DC:E7:03:A0:65'
  local tmp got

  command -v openssl >/dev/null 2>&1 || { echo 'INFNET root CA: openssl not found, skipping.' >&2; return 0; }

  tmp="$(mktemp)"
  if ! curl -fsS --connect-timeout 5 --max-time 15 -o "${tmp}" "${url}" 2>/dev/null; then
    echo 'INFNET root CA: certificates.infinatious.com not reachable, skipping.' >&2
    rm -f "${tmp}"
    return 0
  fi

  got="$(openssl x509 -in "${tmp}" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || true)"
  if [[ "${got}" != "${want}" ]]; then
    echo "INFNET root CA: fingerprint mismatch (got '${got:-none}'), skipping." >&2
    rm -f "${tmp}"
    return 0
  fi

  case "${ID,,}" in
    almalinux|rocky|centos)
      install -m 0644 "${tmp}" /etc/pki/ca-trust/source/anchors/infinatious-root-ca.crt && update-ca-trust \
        || echo 'INFNET root CA: install failed, skipping.' >&2
      ;;
    ubuntu|debian)
      if command -v update-ca-certificates >/dev/null 2>&1; then
        install -m 0644 "${tmp}" /usr/local/share/ca-certificates/infinatious-root-ca.crt && update-ca-certificates \
          || echo 'INFNET root CA: install failed, skipping.' >&2
      else
        echo 'INFNET root CA: update-ca-certificates not found, skipping.' >&2
      fi
      ;;
  esac
  rm -f "${tmp}"
}
install_infnet_root_ca || true

# Installs and enrolls the Wazuh agent (INFNET manager). Best effort: skipped
# when the manager's enrollment port is not reachable (off the lab network) or
# an agent is already running. The package is held back and the Wazuh repo
# disabled afterwards, so system updates never move the agent past the manager;
# the manager upgrades its agents itself (daily remote upgrade to its own
# version), so the version below only sets the starting point.
# Group: "container" inside a container, else "vm" (both exist on the manager).
install_wazuh_agent() {
  local manager='inf-10045.phxaz.infinatio.us' version='4.14.8' group

  # The manager's own project cannot reach its public address (hairpin NAT).
  if ip -4 -o addr 2>/dev/null | grep -q ' 10\.125\.31\.'; then
    manager='10.125.31.3'
  fi

  if systemctl is-active --quiet wazuh-agent 2>/dev/null; then
    echo 'Wazuh agent: already running, skipping.'
    return 0
  fi
  if ! timeout 5 bash -c "exec 3<>/dev/tcp/${manager}/1515" 2>/dev/null; then
    echo "Wazuh agent: ${manager}:1515 not reachable, skipping." >&2
    return 0
  fi

  if systemd-detect-virt -cq 2>/dev/null; then group=container; else group=vm; fi
  export WAZUH_MANAGER="${manager}" WAZUH_REGISTRATION_SERVER="${manager}" WAZUH_AGENT_GROUP="${group}"

  case "${ID,,}" in
    almalinux|rocky|centos)
      rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH || return 1
      cat > /etc/yum.repos.d/wazuh.repo <<'REPO'
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
REPO
      dnf install -y -q "wazuh-agent-${version}" || return 1
      grep -q '^exclude=wazuh-agent' /etc/dnf/dnf.conf || echo 'exclude=wazuh-agent' >> /etc/dnf/dnf.conf
      sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/wazuh.repo
      ;;
    ubuntu|debian)
      curl -fsS https://packages.wazuh.com/key/GPG-KEY-WAZUH \
        | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import 2>/dev/null || return 1
      chmod 644 /usr/share/keyrings/wazuh.gpg
      echo 'deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main' > /etc/apt/sources.list.d/wazuh.list
      apt-get update -qq
      apt-get install -y -qq "wazuh-agent=${version}-1" || return 1
      apt-mark hold wazuh-agent >/dev/null
      sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/wazuh.list
      ;;
    *) return 0 ;;
  esac

  systemctl daemon-reload
  systemctl enable --now wazuh-agent
  echo "Wazuh agent ${version} installed (manager ${manager}, group ${group})."
}
install_wazuh_agent || echo 'Wazuh agent: install failed, continuing.' >&2

if command -v updatedb >/dev/null 2>&1; then
  updatedb || true
fi

cat <<'EOF' > /etc/profile.d/motd-refresh.sh
#!/usr/bin/env bash
if [[ "${-}" != *i* ]]; then
  return 0
fi

if [[ -f /etc/os-release ]]; then
  . /etc/os-release
fi

OS_NAME="${NAME:-${ID:-unknown}}"
OS_VERSION="${VERSION:-${VERSION_ID:-unknown}}"
HOSTNAME_TEXT="$(hostname)"
CPU_USAGE=$(top -bn1 2>/dev/null | awk '/^%Cpu/ {usage = $2 + $4 + $6; printf "%.0f", usage; exit}')
CPU_CAPACITY=$(nproc 2>/dev/null || echo 'unknown')
RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')
RAM_USED=$(free -m 2>/dev/null | awk '/^Mem:/ {print $3}')
RAM_TOTAL_GB=$(awk -v total="${RAM_TOTAL}" 'BEGIN {printf "%.1f", total / 1024}')
RAM_USED_GB=$(awk -v used="${RAM_USED}" 'BEGIN {printf "%.1f", used / 1024}')
PRIMARY_IPV4="$(hostname -I 2>/dev/null | awk '{print $1}')"
DISK_LINES="$(for path in / /home; do
  info="$(df -hP "${path}" 2>/dev/null | tail -n 1)"
  [[ -n "${info}" ]] || continue
  usage_pct="$(printf '%s\n' "${info}" | awk '{print $5}')"
  mount_point="$(printf '%s\n' "${info}" | awk '{print $6}')"
  printf '%-20s %5s used\n' "${mount_point}" "${usage_pct}"
done | awk '!seen[$0]++')"

MOTD_TMP="$(mktemp)"
{
  echo -e '\e[38;5;140m##################################################\e[0m'
  printf '\e[38;5;206m%s\e[0m\n' "${HOSTNAME_TEXT}"
  echo
  printf '\e[38;5;76m%s %s\e[0m\n' "${OS_NAME}" "${OS_VERSION}"
  printf '\e[38;5;39mCPU %s%% of %s cores\e[0m\n' "${CPU_USAGE:-0}" "${CPU_CAPACITY}"
  printf '\e[38;5;141mRAM %sGB/%sGB\e[0m\n' "${RAM_USED_GB:-0}" "${RAM_TOTAL_GB:-0}"
  printf '\e[38;5;36mIPv4 %s\e[0m\n' "${PRIMARY_IPV4:-unknown}"
  echo
  printf '\e[38;5;140mDisk usage:\e[0m\n'
  printf '%s\n' "${DISK_LINES}"
  echo -e '\e[38;5;140m##################################################\e[0m'
} > "${MOTD_TMP}"

if command -v sudo >/dev/null 2>&1; then
  sudo install -m 0644 "${MOTD_TMP}" /etc/motd
  sudo install -m 0644 "${MOTD_TMP}" /run/motd.dynamic
else
  install -m 0644 "${MOTD_TMP}" /etc/motd
  install -m 0644 "${MOTD_TMP}" /run/motd.dynamic
fi
rm -f "${MOTD_TMP}"
EOF
chmod 755 /etc/profile.d/motd-refresh.sh

cat <<'EOF' > /etc/update-motd.d/99-infnet-motd
#!/usr/bin/env bash
if [[ -f /etc/profile.d/motd-refresh.sh ]]; then
  . /etc/profile.d/motd-refresh.sh
fi
EOF
chmod 755 /etc/update-motd.d/99-infnet-motd

if [[ -f /etc/profile ]]; then
  grep -q 'motd-refresh.sh' /etc/profile || echo '. /etc/profile.d/motd-refresh.sh' >> /etc/profile
fi

if [[ -f /etc/bash.bashrc ]]; then
  grep -q 'motd-refresh.sh' /etc/bash.bashrc || echo '. /etc/profile.d/motd-refresh.sh' >> /etc/bash.bashrc
fi

if [[ -f /usr/bin/update-motd ]]; then
  /usr/bin/update-motd || true
fi

if [[ -f /etc/profile.d/motd-refresh.sh ]]; then
  . /etc/profile.d/motd-refresh.sh
fi

echo 'Post-install setup complete.'
