# infnet-provisioning

Generic first-boot setup script. The only environment-specific part is an optional step that trusts the INFINATIOUS root CA, described below.

## post-install.sh

Sets a colored shell prompt, installs base packages (git, curl, jq, htop, btop, vim, nfs, and so on), turns on automatic security updates, and sets up a status MOTD. Supports Ubuntu, Debian, AlmaLinux and Rocky.

It also tries to download the INFINATIOUS root CA from `http://certificates.infinatious.com/infinatious-root-ca.crt` and add it to the system trust store. The file is only installed if its SHA-256 fingerprint matches the one pinned in the script. If the host cannot be reached (for example off the lab network) or the fingerprint does not match, that step is skipped and the rest of the setup continues.

On a fresh install, as root:

```bash
curl -sSL https://raw.githubusercontent.com/infinatious/infnet-provisioning/refs/heads/main/post-install.sh | bash
```

As a normal user with sudo:

```bash
curl -sSL https://raw.githubusercontent.com/infinatious/infnet-provisioning/refs/heads/main/post-install.sh | sudo bash
```

To read it first:

```bash
curl -sSLO https://raw.githubusercontent.com/infinatious/infnet-provisioning/refs/heads/main/post-install.sh
less post-install.sh
sudo bash post-install.sh
```

The script is safe to re-run.
