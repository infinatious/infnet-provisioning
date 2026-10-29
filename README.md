# infnet-provisioning

Generic first-boot setup script. Nothing in it is specific to one environment.

## post-install.sh

Sets a colored shell prompt, installs base packages (git, curl, jq, htop, btop, vim, nfs, and so on), turns on automatic security updates, and sets up a status MOTD. Supports Ubuntu, Debian, AlmaLinux and Rocky.

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
