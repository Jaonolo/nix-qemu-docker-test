# NixOS Docker VM (no Docker Desktop, no WSL)

This repo provides a **local, production-minded Docker Engine** running inside a **minimal NixOS VM** on **Windows** using **QEMU**, with the **Windows Docker CLI** connecting via a **Docker context over SSH**.

Key properties:
- **No Docker Desktop**
- **No WSL required**
- **Docker over SSH** (no unauthenticated TCP)
- **Local-only** (SSH forwarded to `127.0.0.1`)
- **Idempotent scripts** with strict PowerShell settings and logs

## Layout
- `scripts/install.ps1`: bootstrap host deps (Scoop), download & verify **CI-built qcow2**, create OS overlay + docker data disk + cloud-init seed ISO, create Docker context.
- `scripts/start.ps1`: start the VM from the overlay + data disk, wait for SSH, validate Docker via the context.
- `scripts/stop.ps1`: stop the VM (optional helper).
- `scripts/lib/*.ps1`: shared PowerShell helpers.
- `nixos/image.nix`: NixOS module used by CI to build the qcow2 image (Docker + SSH + qemu-guest-agent + cloud-init).
- `nixos/flake.nix`: flake used by CI to build the qcow2 via `nixos-generators`.
- `state/`: generated runtime state (keys, disk image, logs, PID files, generated Nix config).
- `artifacts/`: downloaded artifacts (qcow2 + checksum).

## Quickstart

### First-time install (bootstrap + build VM + docker context)
From repo root in PowerShell 7:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install.ps1
```

### Start the VM

```powershell
.\scripts\start.ps1
```

### Test Docker

```powershell
docker --context nix-docker-vm info
docker --context nix-docker-vm run --rm hello-world
```

## Assumptions / caveats
- Requires internet access to download Scoop packages and the released qcow2 image.
- Uses **QEMU user-mode networking** with port-forwarded SSH (`127.0.0.1:<HostSshPort> -> guest:22`). No bridged networking required.
- Uses **cloud-init NoCloud** (seed ISO generated locally) to inject your SSH public key at boot without rebuilding the OS image.
- The OS qcow2 is treated as an **immutable base**; the VM boots from a local **overlay qcow2**. Docker data lives on a separate persistent qcow2 disk.

