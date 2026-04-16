Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
. (Join-Path $PSScriptRoot 'lib\DockerContext.ps1')

try {
  $RepoRoot = Resolve-RepoRoot

  # =========================
  # Config (edit as desired)
  # =========================
  $Config = [ordered]@{
    VmName        = 'nix-docker-vm'
    VmMemoryMb    = 2048
    VmCores       = 2
    HostSshPort   = 2224
    GuestSshUser  = 'dockervm'
    DockerContext = 'nix-docker-vm'

    StateDir      = (Join-Path $RepoRoot 'state')
    LogsDir       = (Join-Path $RepoRoot 'state\logs')
    OsOverlayPath = (Join-Path $RepoRoot 'state\os-overlay.qcow2')
    DockerDataPath= (Join-Path $RepoRoot 'state\docker-data.qcow2')
    CloudInitIso  = (Join-Path $RepoRoot 'state\cloud-init\seed.iso')
    PidFile       = (Join-Path $RepoRoot 'state\vm.pid')
    SerialLog     = (Join-Path $RepoRoot 'state\logs\vm-serial.log')
    KnownHosts    = (Join-Path $RepoRoot 'state\known_hosts')
    SshKeyPath    = (Join-Path $RepoRoot 'state\ssh\id_ed25519')
  }

  Ensure-Directory $Config.StateDir
  Ensure-Directory $Config.LogsDir

  Assert-Command qemu-system-x86_64
  Assert-Command docker
  Assert-Command ssh
  Assert-Command ssh-keygen

  foreach ($p in @($Config.OsOverlayPath,$Config.DockerDataPath,$Config.CloudInitIso)) {
    if (-not (Test-Path -LiteralPath $p)) {
      throw "Required VM artifact not found at $p. Run .\scripts\install.ps1 first."
    }
  }

  # =========================
  # Detect already-running VM
  # =========================
  if (Test-Path -LiteralPath $Config.PidFile) {
    $pid = (Get-Content -LiteralPath $Config.PidFile -Raw).Trim()
    if ($pid -match '^\d+$') {
      $proc = Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue
      if ($proc) {
        Write-Log INFO "VM appears to already be running (PID $pid). Skipping launch."
        goto WaitForSsh
      }
    }
    Remove-Item -LiteralPath $Config.PidFile -Force -ErrorAction SilentlyContinue
  }

  # =========================
  # Choose acceleration (WHPX if available)
  # =========================
  $accel = 'tcg'
  try {
    $r = Invoke-External -FilePath (Get-Command qemu-system-x86_64).Path -Arguments @('-accel','help')
    if ($r.Stdout -match '(?im)\bwhpx\b') { $accel = 'whpx' }
  } catch {
    # ignore and default to tcg
  }

  $accelArg = if ($accel -eq 'whpx') { 'whpx' } else { 'tcg' }
  Write-Log INFO "Using QEMU accel: $accelArg"

  # =========================
  # Start QEMU
  # =========================
  if (Test-Path -LiteralPath $Config.SerialLog) { Remove-Item -LiteralPath $Config.SerialLog -Force }

  $osArg = "file=$($Config.OsOverlayPath),if=virtio,format=qcow2,cache=writeback"
  $dataArg = "file=$($Config.DockerDataPath),if=virtio,format=qcow2,cache=writeback"
  $qemuArgs = @(
    '-name', $Config.VmName,
    '-m', "$($Config.VmMemoryMb)",
    '-smp', "$($Config.VmCores)",
    '-display', 'none',
    '-serial', ("file:$($Config.SerialLog)"),
    '-accel', $accelArg,
    '-drive', $osArg,
    '-drive', $dataArg,
    '-drive', ("file=$($Config.CloudInitIso),media=cdrom,readonly=on"),
    '-netdev', ("user,id=net0,hostfwd=tcp:127.0.0.1:$($Config.HostSshPort)-:22"),
    '-device', 'virtio-net-pci,netdev=net0'
  )

  Write-Log INFO "Starting VM..."
  $p = Start-Process -FilePath (Get-Command qemu-system-x86_64).Path -ArgumentList $qemuArgs -PassThru -WindowStyle Hidden
  Set-Content -LiteralPath $Config.PidFile -Value $p.Id -Encoding ASCII

  :WaitForSsh
  # =========================
  # Wait for SSH and validate Docker connectivity
  # =========================
  if (-not (Test-Path -LiteralPath $Config.SshKeyPath)) {
    throw "SSH key not found at $($Config.SshKeyPath). Run .\scripts\install.ps1 first."
  }

  # Isolate known_hosts for this repo so we don't modify global user state.
  if (-not (Test-Path -LiteralPath $Config.KnownHosts)) {
    New-Item -ItemType File -Path $Config.KnownHosts | Out-Null
  }
  try {
    & ssh-keygen -R ("[localhost]:$($Config.HostSshPort)") -f $Config.KnownHosts | Out-Null
  } catch {}

  $sshArgs = @(
    '-i', $Config.SshKeyPath,
    '-p', "$($Config.HostSshPort)",
    '-o', 'BatchMode=yes',
    '-o', 'IdentitiesOnly=yes',
    '-o', 'StrictHostKeyChecking=accept-new',
    '-o', ("UserKnownHostsFile=$($Config.KnownHosts)"),
    ("$($Config.GuestSshUser)@localhost"),
    'true'
  )

  Write-Log INFO "Waiting for SSH to become reachable on 127.0.0.1:$($Config.HostSshPort)..."
  Wait-Until -TimeoutSeconds 180 -DelayMilliseconds 1000 -TimeoutMessage "Timed out waiting for SSH. Check $($Config.SerialLog)." -Condition {
    & ssh @sshArgs *> $null
    return ($LASTEXITCODE -eq 0)
  }
  Write-Log INFO "SSH is reachable."

  Write-Log INFO "Validating Docker via context '$($Config.DockerContext)'..."
  Invoke-External -FilePath (Get-Command docker).Path -Arguments @('--context', $Config.DockerContext, 'info') | Out-Null

  $ctx = Invoke-External -FilePath (Get-Command docker).Path -Arguments @('context','show')

  Write-Host ""
  Write-Host "Success"
  Write-Host "  VM:             $($Config.VmName)"
  Write-Host "  SSH:            127.0.0.1:$($Config.HostSshPort)"
  Write-Host "  Docker context: $($Config.DockerContext)"
  Write-Host "  Current context:$($ctx.Stdout.Trim())"
} catch {
  Write-Log ERROR $_.Exception.Message
  throw
}

