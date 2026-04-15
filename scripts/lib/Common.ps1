Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
  param(
    [Parameter(Mandatory)] [ValidateSet('INFO','WARN','ERROR','DEBUG')] [string] $Level,
    [Parameter(Mandatory)] [string] $Message
  )
  $ts = (Get-Date).ToString('s')
  Write-Host "[$ts] [$Level] $Message"
}

function Assert-Command {
  param([Parameter(Mandatory)] [string] $Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Required command not found in PATH: '$Name'."
  }
}

function Ensure-Directory {
  param([Parameter(Mandatory)] [string] $Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Resolve-RepoRoot {
  # Resolve relative to this script location; robust to invocation cwd.
  $here = Split-Path -Parent $PSCommandPath
  return (Resolve-Path (Join-Path $here '..\..')).Path
}

function Test-IsAdmin {
  try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch {
    return $false
  }
}

function Invoke-External {
  param(
    [Parameter(Mandatory)] [string] $FilePath,
    [Parameter(Mandatory)] [string[]] $Arguments,
    [string] $WorkingDirectory,
    [int] $TimeoutSeconds = 0,
    [string] $StdoutPath,
    [string] $StderrPath
  )

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FilePath
  $psi.Arguments = ($Arguments -join ' ')
  if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  if (-not $p.Start()) { throw "Failed to start process: $FilePath" }

  if ($TimeoutSeconds -gt 0) {
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
      try { $p.Kill() } catch {}
      throw "Process timed out after ${TimeoutSeconds}s: $FilePath $($psi.Arguments)"
    }
  } else {
    $p.WaitForExit() | Out-Null
  }

  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()

  if ($StdoutPath) { [IO.File]::WriteAllText($StdoutPath, $stdout, [Text.Encoding]::UTF8) }
  if ($StderrPath) { [IO.File]::WriteAllText($StderrPath, $stderr, [Text.Encoding]::UTF8) }

  if ($p.ExitCode -ne 0) {
    $msg = "Command failed ($($p.ExitCode)): $FilePath $($psi.Arguments)"
    if ($stderr) { $msg += "`n--- stderr ---`n$stderr" }
    throw $msg
  }

  return @{
    Stdout = $stdout
    Stderr = $stderr
    ExitCode = $p.ExitCode
  }
}

function Get-FreeTcpPort {
  # Best-effort helper (racey by nature). Prefer explicit ports in config.
  $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
  $listener.Start()
  $port = ($listener.LocalEndpoint).Port
  $listener.Stop()
  return $port
}

function Wait-Until {
  param(
    [Parameter(Mandatory)] [scriptblock] $Condition,
    [int] $TimeoutSeconds = 120,
    [int] $DelayMilliseconds = 1000,
    [string] $TimeoutMessage = 'Timed out waiting for condition.'
  )
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
    try {
      if (& $Condition) { return }
    } catch {
      # ignore transient errors
    }
    Start-Sleep -Milliseconds $DelayMilliseconds
  }
  throw $TimeoutMessage
}

function Read-TextFileTail {
  param(
    [Parameter(Mandatory)] [string] $Path,
    [int] $MaxChars = 20000
  )
  if (-not (Test-Path -LiteralPath $Path)) { return '' }
  $bytes = [IO.File]::ReadAllBytes($Path)
  $count = [Math]::Min($bytes.Length, $MaxChars)
  $slice = New-Object byte[] $count
  [Array]::Copy($bytes, $bytes.Length - $count, $slice, 0, $count)
  return [Text.Encoding]::UTF8.GetString($slice)
}

