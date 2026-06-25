# VM Project

Alpine Linux VM automation for VirtualBox on macOS.

## Architecture

- **`alpine-vm.sh`** — Bash script that provisions an Alpine Linux VM headlessly
- VirtualBox 7.2.10, macOS host, Alpine virt ISO 3.24.1

## Key Findings (June 2026)

### VirtualBox Serial Limitation
`tcpserver` mode accepts TCP connections but **does not forward guest output** to clients. Only `file` mode captures guest output. This makes bidirectional serial communication impossible via tcpserver on this VirtualBox version.

### Live ISO SSH Limitation
Alpine live ISO SSH accepts TCP connections (so `nc -z` returns success) but never sends an SSH banner. Use `ssh -o ConnectTimeout=5` instead of `nc -z` for SSH detection.

### Only Reliable Input: Keyboard
`VBoxManage controlvm keyboardputstring` + Enter scancode is the only reliable input path.

### Provisioning Flow (Working)
1. Boot VM headless, wait 35s for Alpine to reach login prompt
2. Keyboard: `root` + Enter (login), Enter (empty password)
3. Keyboard: `ip link set eth0 up`, `udhcpc -i eth0 -q`
4. Keyboard: `echo '...'` commands to write answerfile line-by-line
5. Keyboard: `yes | setup-alpine -ef /tmp/answers` (auto-answers prompts)
6. Wait 180s for installation
7. Phase 1: `nc -z` loop detecting port close (VM reboot)
8. Phase 2: `ssh -o ConnectTimeout=5` loop detecting working SSH

### Answerfile Format (setup-alpine)
Variables written line-by-line via `echo 'KEY=VAL' >> /tmp/answers`:
`KEYMAPOPTS`, `HOSTNAMEOPTS`, `TIMEZONEOPTS`, `INTERFACESOPTS` (multi-line with `"auto lo / iface lo inet loopback / auto eth0 / iface eth0 inet dhcp"`), `PROXYOPTS`, `NTPOPTS` (busybox), `APKREPOSOPTS` (URL), `USEROPTS`, `SSHDOPTS`, `ROOTSSHKEY`, `DISKOPTS`.

## Pending Review (too long)

| Wait | Current | Notes |
|------|---------|-------|
| `sleep 35` (boot) | 35s | Login prompt |
| `SETUP_TIMEOUT` (setup-alpine) | 180s | Can `yes` answer faster? |
| Phase 1 (nc port close) | 90 × 3s = 270s | VM reboots in ~30s |
| Phase 2 (SSH banner) | 40 × 10s = 400s | Installed SSH responds in ~5s |

## Commands

| Action | Command |
|--------|---------|
| Provision | `./alpine-vm.sh` |
| Verbose | `./alpine-vm.sh -v` |
| SSH in | `ssh -i <key> root@localhost -p 2222` |
