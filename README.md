# Alpine Linux VM · Headless Provisioner

One-shot script to create and provision an Alpine Linux VM in VirtualBox on macOS — no serial port, no VNC, purely keyboard-driven input.

## Quickstart

```bash
./alpine-vm.sh
```

Wait ~8 minutes. SSH in:

```bash
ssh root@localhost -p 2222
```

The root password is printed at the end of the script.

## Requirements

- VirtualBox 7.2+
- Alpine virt ISO at `./vmimages/alpine-virt-3.24.1-x86_64.iso`
- Commands on PATH: `VBoxManage`, `ssh-keygen`, `ssh`, `nc`

## How It Works

The Alpine live ISO has two broken features that rule out the obvious approaches:

- **Serial (UART)**: `tcpserver` mode accepts TCP connections but silently drops guest-to-host output. `file` mode works for capture only — no input path.
- **SSH on live ISO**: TCP connects succeed (`nc -z` reports open) but the SSH daemon never sends a banner. Real SSH connections hang indefinitely.

The only reliable mechanism is keyboard input via `VBoxManage controlvm keyboardputstring` + scancode for Enter.

### Provisioning Flow

1. Boot VM headless, wait for kernel + CD-ROM init (log-based detection)
2. Keyboard: login as root (no password), bring up `eth0` via DHCP
3. Keyboard: write answerfile `/tmp/answers` line-by-line with `echo`
4. Keyboard: `yes | setup-alpine -ef /tmp/answers` — `yes` auto-answers the disk-erase and reboot prompts
5. Wait 180s for installation
6. Detect reboot: `nc -z` loop watches for port 22 to close
7. Detect SSH: `ssh -o ConnectTimeout=5` loop (avoids the broken live ISO SSH)
8. Eject ISO, print success

## Answerfile Variables

| Variable | Purpose |
|----------|---------|
| `KEYMAPOPTS` | Keyboard layout (e.g. `us us`) |
| `HOSTNAMEOPTS` | Hostname (`-n <name>`) |
| `TIMEZONEOPTS` | Timezone (`-z <zone>`) |
| `INTERFACESOPTS` | Multi-line network config |
| `PROXYOPTS` | HTTP proxy (`none` for none) |
| `NTPOPTS` | NTP client (`busybox` is built-in) |
| `APKREPOSOPTS` | APK repository URL |
| `USEROPTS` | Create user (`none` to skip) |
| `SSHDOPTS` | SSH server package (`openssh` or `dropbear`) |
| `ROOTSSHKEY` | Authorized SSH public key |
| `DISKOPTS` | Disk setup (`-m sys /dev/sda`) |

## Options

| Flag | Effect |
|------|--------|
| `-v` / `--verbose` | Show each VBoxManage command |
| `--dry-run` | Print commands without executing |
| `-h` / `--help` | Full help text |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VM_DIR` | `/Volumes/EXT1TB/VMS` | VM storage directory |
| `VM_NAME` | `alpine` | VM name |
| `ISO_PATH` | `$VM_DIR/vmimages/...` | Alpine ISO path |
| `ROOT_PASSWORD` | *(auto-generated)* | Root password |
| `VM_MEMORY` | 16384 | RAM in MB |
| `VM_CPUS` | 2 | CPU count |
| `VM_DISK_SIZE` | 20480 | Disk size in MB |
| `SSH_PORT` | 2222 | Host SSH port forward |
| `SETUP_TIMEOUT` | 180 | Seconds to wait for `setup-alpine` |

## Timing (needs tuning)

| Wait | Current | Likely enough |
|------|---------|--------------|
| Boot (`sleep 35`) | 35s | 20-25s |
| `setup-alpine` (`SETUP_TIMEOUT`) | 180s | 90-120s |
| Phase 1 (port close) | 90×3s = 270s | 30-60s |
| Phase 2 (SSH banner) | 40×10s = 400s | 30-60s |

These are conservative. `yes` bypasses interactive prompts so setup-alpine completes much faster than 180s.

## Files

- `alpine-vm.sh` — The provisioner
- `AGENTS.md` — Technical findings for this project
