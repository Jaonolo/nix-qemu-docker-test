Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

function Get-ScoopCommandPath {
  $cmd = Get-Command scoop -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Path }
  $candidates = @(
    (Join-Path $env:USERPROFILE 'scoop\shims\scoop.ps1'),
    (Join-Path $env:USERPROFILE 'scoop\shims\scoop.cmd')
  )
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  return $null
}

function Ensure-Scoop {
  $scoopPath = Get-ScoopCommandPath
  if ($scoopPath) {
    Write-Log INFO "Scoop already present."
    return
  }

  # Minimal prerequisites for Scoop: PowerShell, TLS 1.2, and ability to run scripts in-process.
  Write-Log INFO "Scoop not found; installing for current user."

  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  } catch {
    # ignore (newer PS uses SslProtocols)
  }

  $isAdmin = Test-IsAdmin
  if ($isAdmin) {
    Write-Log WARN "Running as admin. Scoop is typically installed per-user; continuing anyway."
  }

  $installCmd = @(
    "Set-ExecutionPolicy -Scope Process Bypass -Force;",
    "iwr -useb get.scoop.sh | iex"
  ) -join ' '

  try {
    & powershell -NoProfile -Command $installCmd | Out-Host
  } catch {
    throw "Failed to install Scoop. If your environment blocks script downloads, manually install Scoop and re-run. Details: $($_.Exception.Message)"
  }

  $scoopPath = Get-ScoopCommandPath
  if (-not $scoopPath) {
    throw "Scoop install completed but 'scoop' is still not on PATH. Try opening a new PowerShell session and re-run."
  }
}

function Ensure-ScoopPackages {
  param([Parameter(Mandatory)] [string[]] $Packages)

  Ensure-Scoop
  $scoop = Get-ScoopCommandPath
  if (-not $scoop) { throw "Scoop not found after installation attempt." }

  foreach ($pkg in $Packages) {
    $installed = $false
    try {
      & scoop which $pkg *> $null
      if ($LASTEXITCODE -eq 0) { $installed = $true }
    } catch { $installed = $false }

    if ($installed) {
      Write-Log INFO "Scoop package present: $pkg"
      continue
    }

    Write-Log INFO "Installing Scoop package: $pkg"
    try {
      & scoop install $pkg | Out-Host
    } catch {
      throw "Failed to install Scoop package '$pkg'. Details: $($_.Exception.Message)"
    }
  }
}

