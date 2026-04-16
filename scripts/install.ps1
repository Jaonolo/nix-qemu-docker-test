Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
. (Join-Path $PSScriptRoot 'lib\Scoop.ps1')
. (Join-Path $PSScriptRoot 'lib\DockerContext.ps1')
. (Join-Path $PSScriptRoot 'lib\GitHubRelease.ps1')

try {
  $RepoRoot = Resolve-RepoRoot
  # =========================
  # Config (edit as desired)
  # =========================
  $Config = [ordered]@{
    VmName           = 'nix-docker-vm'
    VmMemoryMb       = 2048
    VmCores          = 2
    DockerDataSizeGb = 60
    HostSshPort      = 2222
    GuestSshUser     = 'dockervm'
    DockerContext    = 'nix-docker-vm'
    AutoUseContext   = $true

    # GitHub repo that publishes qcow2 releases (this repo).
    ImageOwner       = 'Jaonolo'
    ImageRepo        = 'nix-qemu-docker-test'
    # Version pinning:
    # - '' => latest release
    # - 'qcow2-YYYYMMDD-HHMMSS-<sha7>' => specific tag
    ImageTag         = ''

    ArtifactsDir     = (Join-Path $RepoRoot 'artifacts')
    StateDir         = (Join-Path $RepoRoot 'state')
    LogsDir          = (Join-Path $RepoRoot 'state\logs')

    BaseOsImagePath  = (Join-Path $RepoRoot 'artifacts\nix-docker-vm.qcow2')
    BaseOsZstPath    = (Join-Path $RepoRoot 'artifacts\nix-docker-vm.qcow2.zst')
    BaseOsZstShaPath = (Join-Path $RepoRoot 'artifacts\nix-docker-vm.qcow2.zst.sha256')
    OsOverlayPath    = (Join-Path $RepoRoot 'state\os-overlay.qcow2')
    DockerDataPath   = (Join-Path $RepoRoot 'state\docker-data.qcow2')
    CloudInitDir     = (Join-Path $RepoRoot 'state\cloud-init')
    CloudInitIsoPath = (Join-Path $RepoRoot 'state\cloud-init\seed.iso')
    KnownHostsPath   = (Join-Path $RepoRoot 'state\known_hosts')
    SshKeyPath       = (Join-Path $RepoRoot 'state\ssh\id_ed25519')
  }

  Write-Log INFO "Repo root: $RepoRoot"
  Ensure-Directory $Config.ArtifactsDir
  Ensure-Directory $Config.StateDir
  Ensure-Directory $Config.LogsDir
  Ensure-Directory (Split-Path -Parent $Config.SshKeyPath)

  # =========================
  # Host dependencies
  # =========================
  Ensure-Scoop
  Ensure-ScoopPackages -Packages @(
    'git',
    'qemu',
    'docker',
    'openssh',
    'cdrtools',
    'zstd'
  )

  Assert-Command git
  Assert-Command qemu-system-x86_64
  Assert-Command qemu-img
  Assert-Command docker
  Assert-Command ssh
  Assert-Command ssh-keygen

  Assert-Command mkisofs

  # =========================
  # Generate SSH keypair
  # =========================
  if (-not (Test-Path -LiteralPath $Config.SshKeyPath)) {
    Write-Log INFO "Generating SSH keypair for this setup..."

    $cmd = 'ssh-keygen -q -t ed25519 -N "" -f "{0}"' -f $Config.SshKeyPath
    cmd /c $cmd | Out-Null
  } else {
    Write-Log INFO "SSH key already present."
  }
  if (-not (Test-Path -LiteralPath ($Config.SshKeyPath + '.pub'))) {
    throw "SSH public key missing: $($Config.SshKeyPath).pub"
  }

  # Best-effort permissions hardening on private key (works without admin).
  try {
    & icacls $Config.SshKeyPath /inheritance:r | Out-Null
    & icacls $Config.SshKeyPath /grant:r "$($env:USERNAME):(R,W)" | Out-Null
  } catch {
    Write-Log WARN "Could not harden ACL on SSH private key (continuing)."
  }

  # =========================
  # Cloud-init seed (NoCloud) to set authorized SSH key
  # =========================
  $pub = (Get-Content -LiteralPath ($Config.SshKeyPath + '.pub') -Raw).Trim()
  if (-not $pub) { throw "SSH public key is empty." }

  Ensure-Directory $Config.CloudInitDir
  $userDataPath = Join-Path $Config.CloudInitDir 'user-data'
  $metaDataPath = Join-Path $Config.CloudInitDir 'meta-data'

  $userData = @"
#cloud-config
users:
  - name: $($Config.GuestSshUser)
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [ docker ]
    shell: /run/current-system/sw/bin/bash
    ssh_authorized_keys:
      - $pub
ssh_pwauth: false
disable_root: true
package_update: false
package_upgrade: false
"@
  Set-Content -LiteralPath $userDataPath -Value $userData -Encoding UTF8
  Set-Content -LiteralPath $metaDataPath -Value "instance-id: $($Config.VmName)`nlocal-hostname: $($Config.VmName)`n" -Encoding UTF8

  Write-Log INFO "Creating cloud-init seed ISO..."
  if (Test-Path -LiteralPath $Config.CloudInitIsoPath) { Remove-Item -LiteralPath $Config.CloudInitIsoPath -Force }
  Push-Location $Config.CloudInitDir
  try {
    # NoCloud expects files named exactly "user-data" and "meta-data" at the ISO root.
    & mkisofs -quiet -output $Config.CloudInitIsoPath -volid cidata -rock 'user-data' 'meta-data' | Out-Null
  } finally {
    Pop-Location
  }

  # # =========================
  # # Download qcow2 (release) + verify checksum
  # # =========================
  # if ($Config.ImageOwner -eq 'REPLACE_ME' -or $Config.ImageRepo -eq 'REPLACE_ME') {
  #   throw "Set Config.ImageOwner and Config.ImageRepo in scripts/install.ps1 to your GitHub repo (owner/name) that publishes qcow2 releases."
  # }

  # $release = if ([string]::IsNullOrWhiteSpace($Config.ImageTag)) {
  #   Write-Log INFO "Resolving latest GitHub Release for $($Config.ImageOwner)/$($Config.ImageRepo)..."
  #   Get-LatestRelease -Owner $Config.ImageOwner -Repo $Config.ImageRepo
  # } else {
  #   Write-Log INFO "Resolving GitHub Release tag '$($Config.ImageTag)' for $($Config.ImageOwner)/$($Config.ImageRepo)..."
  #   Get-ReleaseByTag -Owner $Config.ImageOwner -Repo $Config.ImageRepo -Tag $Config.ImageTag
  # }

  # $zstUrl = Get-AssetUrlByName -ReleaseJson $release -AssetName 'nix-docker-vm.qcow2.zst'
  # $shaUrl = Get-AssetUrlByName -ReleaseJson $release -AssetName 'nix-docker-vm.qcow2.zst.sha256'
  # if (-not $zstUrl -or -not $shaUrl) {
  #   throw "Release does not contain expected assets: nix-docker-vm.qcow2.zst and nix-docker-vm.qcow2.zst.sha256"
  # }

  # Write-Log INFO "Downloading sha256 checksum..."
  # Download-Asset -Url $shaUrl -OutFile $Config.BaseOsZstShaPath

  # if (-not (Test-Path -LiteralPath $Config.BaseOsZstPath)) {
  #   Write-Log INFO "Downloading compressed base OS image (qcow2.zst)..."
  #   Download-Asset -Url $zstUrl -OutFile $Config.BaseOsZstPath
  # } else {
  #   Write-Log INFO "Compressed base OS image already present."
  # }

  # $expected = (Get-Content -LiteralPath $Config.BaseOsZstShaPath -Raw).Trim().Split(' ')[0]
  # if (-not $expected -or $expected.Length -lt 32) { throw "Checksum file looks invalid: $($Config.BaseOsZstShaPath)" }
  # $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Config.BaseOsZstPath).Hash.ToLowerInvariant()
  # if ($actual -ne $expected.ToLowerInvariant()) {
  #   throw "qcow2.zst checksum mismatch.`nExpected: $expected`nActual:   $actual"
  # }
  # Write-Log INFO "qcow2.zst checksum verified."

  # if (-not (Test-Path -LiteralPath $Config.BaseOsImagePath)) {
  #   Write-Log INFO "Decompressing qcow2.zst -> qcow2..."
  #   Assert-Command zstd
  #   & zstd -d -f -o $Config.BaseOsImagePath $Config.BaseOsZstPath | Out-Null
  # } else {
  #   Write-Log INFO "Decompressed base OS image already present."
  # }

  # =========================
  # Create OS overlay (immutable-style base) + docker data disk
  # =========================
  if (-not (Test-Path -LiteralPath $Config.OsOverlayPath)) {
    Write-Log INFO "Creating OS overlay qcow2 (backing = base image)..."
    & qemu-img create -f qcow2 -F qcow2 -b $Config.BaseOsImagePath $Config.OsOverlayPath | Out-Null
  } else {
    Write-Log INFO "OS overlay already present."
  }

  if (-not (Test-Path -LiteralPath $Config.DockerDataPath)) {
    Write-Log INFO "Creating Docker data disk qcow2 $($Config.DockerDataSizeGb)GB..."
    & qemu-img create -f qcow2 $Config.DockerDataPath ("{0}G" -f $Config.DockerDataSizeGb) | Out-Null
  } else {
    Write-Log INFO "Docker data disk already present."
  }

  # # =========================
  # # Create Docker context (SSH)
  # # =========================
  # Ensure-DockerContextSsh -ContextName $Config.DockerContext -SshUser $Config.GuestSshUser -SshPort $Config.HostSshPort `
  #   -Description "Docker Engine inside NixOS VM via SSH (QEMU on Windows, local-only)."

  # if ($Config.AutoUseContext) {
  #   Set-DockerContextCurrent -ContextName $Config.DockerContext
  # }

  Write-Log INFO "Install complete."
  Write-Host ""
  Write-Host "Summary"
  Write-Host "  VM name:         $($Config.VmName)"
  Write-Host "  Base OS image:   $($Config.BaseOsImagePath)"
  Write-Host "  OS overlay:      $($Config.OsOverlayPath)"
  Write-Host "  Docker data:     $($Config.DockerDataPath)"
  Write-Host "  SSH user:        $($Config.GuestSshUser)"
  Write-Host "  SSH port:        127.0.0.1:$($Config.HostSshPort) -> guest:22"
  Write-Host "  Docker context:  $($Config.DockerContext)"
  Write-Host ""
  Write-Host "Next:"
  Write-Host "  Start VM:        .\scripts\start.ps1"
  Write-Host "  Test Docker:     docker --context $($Config.DockerContext) info"
} catch {
  Write-Log ERROR $_.Exception.Message
  throw
}

