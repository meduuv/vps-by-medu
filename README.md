# vps-by-medu

A lightweight QEMU-based VPS dashboard. Spin up a disposable Ubuntu 22.04 virtual machine, get a shareable SSH terminal link, and tear it down whenever you're done — all from one interactive bash script.

Built and maintained by **medu**.

## Features

- Create and boot a fresh Ubuntu 22.04 cloud VM with custom RAM, CPU, disk, username, and password
- Restart your existing VM without reconfiguring
- Edit TCP port-forwarding rules (host port → guest SSH port)
- Clean up all VM files, disk images, and cached config in one step
- Live shareable terminal link via [sshx.io](https://sshx.io), plus a standard local SSH command
- Colorful interactive menu, no flags or arguments to memorize

## Requirements

- Linux host with `sudo` access
- Internet access (to fetch the Ubuntu cloud image and install dependencies)
- ~10GB+ free disk space for the base image plus whatever extra you allocate

The script installs its own dependencies (`qemu-system-x86`, `qemu-utils`, `cloud-image-utils`, `wget`, `curl`) on first run via `apt-get`.

## Quick start

Run directly from GitHub:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/meduuv/vps-by-medu/refs/heads/main/install.sh)
```

Or clone and run locally:

```bash
git clone https://github.com/meduuv/vps-by-medu.git
cd vps-by-medu
chmod +x install.sh
./install.sh
```

## Usage

You'll get an interactive menu:

```
[1] Create & boot a new Ubuntu VPS instance
[2] Restart existing VPS instance
[3] Configure TCP port forward rules
[4] Clean up VPS files / cache
[5] Exit
```

### 1. Create a VPS

You'll be prompted for:

| Setting   | Default     |
|-----------|-------------|
| RAM       | 4 GB        |
| CPU cores | 2           |
| Disk add  | 10 GB       |
| Username  | `ubuntu`    |
| Password  | *required — no insecure default, you must set and confirm one* |

The script downloads the Ubuntu 22.04 cloud image (cached after first run), builds a cloud-init seed, resizes the disk, and boots the VM with QEMU.

Once booted, you'll see:
- A live `sshx.io` link you can open in any browser for an instant terminal
- A standard SSH command: `ssh <username>@localhost -p <host_port>`

### 2. Restart

Reboots the existing VM using your saved config — no need to re-enter settings.

### 3. Configure TCP forwarding

Change which host port maps to the guest's SSH port (default `2222 → 22`).

### 4. Clean up

Deletes the disk image, cloud-init seed, and saved config (`.vps_env`). Use this to fully reset before creating a new VM.

## Files this script creates

| File                              | Purpose                          |
|------------------------------------|-----------------------------------|
| `/home/medu-vps/ubuntu22.qcow2`    | Base Ubuntu disk image (cached)  |
| `seed.img`                         | Cloud-init seed disk             |
| `user-data`                        | Cloud-init config (deleted after use) |
| `.vps_env`                         | Saved VM settings                |

## Notes & caveats

- The `sshx.io` tunnel works by piping `curl https://sshx.io/get | sh` — that's how sshx itself recommends installing, but be aware it runs a remote script on your machine. If you'd rather skip the public tunnel, just use the local SSH command shown after boot.
- VM credentials are stored in `.vps_env` and the cloud-init disk; treat these files as sensitive and don't commit them.
- This is meant for quick, disposable dev/test VMs — not hardened for production hosting.

## Credits

Built by **medu**.
