# vps-by-medu

A lightweight QEMU-based VPS dashboard. Spin up a disposable Ubuntu 22.04 virtual machine, get a shareable SSH terminal link, and tear it down whenever you're done — all from one interactive bash script.

Built and maintained by **medu**.

## Features

- Choose between **Ubuntu 22.04 LTS** or **Debian 12 (bookworm)** as the guest OS, each with its own cached image and correct checksum algorithm (SHA256 for Ubuntu, SHA512 for Debian)
- Create and boot a fresh cloud VM with custom RAM, CPU, disk, username, and password
- Choose Intel, AMD, or host-passthrough CPU emulation (auto-detects your host vendor)
- KVM acceleration when `/dev/kvm` is available, with automatic fallback to software emulation
- Resource caps enforced at input time: **max 32GB RAM, 8 cores, 128GB disk**
- virtio-net networking with working DNS/internet access inside the guest (not just SSH forwarding)
- SHA256 checksum verification on the downloaded Ubuntu cloud image before it's ever booted
- Optional SSH public key login alongside password auth
- PID-tracked VM state — the dashboard knows if a VM is already running and won't let you double-boot, restart over a live instance, or clean up while it's running
- Disk is only resized once per image, not re-applied on every create run
- Plaintext cloud-init password file is securely deleted (`shred`) immediately after the seed image is built
- "Show current config / status" menu option — see resource settings, running state, and disk usage at a glance
- Restart your existing VM without reconfiguring
- Edit TCP port-forwarding rules (host port → guest SSH port), with a warning if the running VM needs a restart to pick up the change
- Clean up all VM files, disk images, and cached config in one step
- Live shareable terminal link via [sshx.io](https://sshx.io), plus a standard local SSH command
- Colorful interactive menu, no flags or arguments to memorize

## Requirements

- Linux host with `sudo` access
- Internet access (to fetch the Ubuntu cloud image and install dependencies)
- ~10GB+ free disk space for the base image plus whatever extra you allocate
- For best performance, hardware virtualization enabled and `/dev/kvm` available (Intel VT-x / AMD-V). The script falls back to slower software emulation automatically if KVM isn't present.

The script installs its own dependencies (`qemu-system-x86`, `qemu-utils`, `cloud-image-utils`, `wget`, `curl`, `coreutils`) on first run via `apt-get`.

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

You'll get an interactive menu that also shows live VM status at the top:

```
[1] Create & boot a new Ubuntu VPS instance
[2] Restart existing VPS instance
[3] Configure TCP port forward rules
[4] Clean up VPS files / cache
[5] Show current config / status
[6] Exit
```

### 1. Create a VPS

You'll be prompted for:

| Setting   | Default     | Max    |
|-----------|-------------|--------|
| OS        | Ubuntu 22.04 LTS | — (or Debian 12 bookworm) |
| RAM       | 4 GB        | 32 GB  |
| CPU cores | 2           | 8      |
| Disk add  | 10 GB       | 128 GB |
| CPU type  | host passthrough (auto-falls back to Intel/AMD emulation without KVM) | — |
| Username  | `ubuntu` (or `debian` if Debian is chosen) | — |
| Password  | *required — no insecure default, you must set and confirm one* | — |
| SSH key   | optional, reads a public key file and adds it alongside password auth | — |

Inputs outside the allowed range are rejected and re-prompted. If a VM is already running, creation is blocked until you stop it or use restart instead.

OS options:
- **Ubuntu 22.04 LTS (jammy)** — downloads `jammy-server-cloudimg-amd64.img`, verified with SHA256
- **Debian 12 (bookworm)** — downloads `debian-12-generic-amd64.qcow2`, verified with SHA512

Each OS gets its own cached image file (`ubuntu.qcow2` / `debian.qcow2`) and its own disk-resize tracking flag, so switching between them doesn't interfere with a previously created instance of the other.

CPU type options:
- **Intel** — emulated Nehalem feature set
- **AMD** — emulated EPYC feature set
- **host passthrough** — passes your real CPU's instruction set through, fastest option, requires KVM (`/dev/kvm`)

What happens under the hood:
1. Dependencies are installed via `apt-get` (with failure checks).
2. The chosen OS's cloud image is downloaded once and cached at `/home/medu-vps/<os>.qcow2`.
3. The image's checksum is verified against the distro's published manifest before continuing — if it doesn't match, the image is deleted and the run aborts.
4. A cloud-init seed image is built from your username, password, and (if provided) SSH key. The plaintext config file is shredded immediately after.
5. The disk is resized by your chosen amount — only on the very first create per OS, not on every subsequent run.
6. QEMU boots the VM with `virtio-net-pci` networking (real internet access, working DNS) and, when available, KVM acceleration.

Once booted, you'll see:
- A live `sshx.io` link you can open in any browser for an instant terminal
- A standard SSH command: `ssh <username>@localhost -p <host_port>`

### 2. Restart

Reboots the existing VM using your saved config. Blocked if a VM is already running (checked via PID file), so you won't end up with two instances fighting over the same port.

### 3. Configure TCP forwarding

Change which host port maps to the guest's SSH port (default `2222 → 22`). If a VM is currently running, you'll be warned that a restart is needed for the change to apply.

### 4. Clean up

Deletes the disk image, cloud-init seed, saved config (`.vps_env`), the resize-tracking flag, and the PID file. Blocked while a VM is running. Use this for a full reset before creating a new VM from scratch.

### 5. Show current config / status

Displays your saved username, RAM, cores, CPU type, port rule, whether SSH key auth is configured, whether the VM is currently running (with PID), and the on-disk size of the VM image.

## Files this script creates

All files live under `/home/medu-vps/`:

| File                  | Purpose                                          |
|-----------------------|---------------------------------------------------|
| `ubuntu.qcow2`        | Cached Ubuntu disk image (checksum-verified), if used |
| `debian.qcow2`        | Cached Debian disk image (checksum-verified), if used |
| `seed.img`            | Cloud-init seed disk                              |
| `user-data`           | Cloud-init config — shredded immediately after use, should not persist |
| `.vps_env`            | Saved VM settings, including which OS is active   |
| `.vps.pid`            | QEMU process ID, used to detect a running VM      |
| `.disk_resized_ubuntu`| Marker so the Ubuntu disk is only resized once    |
| `.disk_resized_debian`| Marker so the Debian disk is only resized once    |

## Security notes

- No default password — you must set and confirm one for every new VM.
- The cloud image is checksum-verified before first boot (SHA256 for Ubuntu, SHA512 for Debian), protecting against a corrupted or tampered download.
- The plaintext cloud-init file containing your password is shredded the moment the seed image is built, rather than left sitting on disk.
- Optional SSH key auth lets you skip password login entirely for the guest if you prefer.
- The `sshx.io` tunnel works by piping `curl https://sshx.io/get | sh` — that's how sshx itself recommends installing, but be aware it runs a remote script on your machine. If you'd rather skip the public tunnel, just use the local SSH command shown after boot instead.
- `.vps_env` and the disk image are stored with restrictive permissions (`600`), but treat them as sensitive and don't commit them to version control.
- This is meant for quick, disposable dev/test VMs — not hardened for production hosting.

## Known limitations

- No flag-based/non-interactive mode yet — every run goes through the prompt wizard. Scripted/repeatable provisioning isn't currently supported.
- The VM is bound to the local host's network namespace via QEMU user networking; it isn't exposed beyond the configured TCP forward and the sshx tunnel.

## Credits

Built by **medu**.
