Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Common.ps1')

try {
  $RepoRoot = Resolve-RepoRoot
  $pidFile = Join-Path $RepoRoot 'state\vm.pid'

  if (-not (Test-Path -LiteralPath $pidFile)) {
    Write-Log INFO "No PID file found. VM may not be running."
    exit 0
  }

  $pid = (Get-Content -LiteralPath $pidFile -Raw).Trim()
  if (-not ($pid -match '^\d+$')) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    throw "Invalid PID file contents: $pid"
  }

  $proc = Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue
  if (-not $proc) {
    Write-Log INFO "Process $pid not running; removing PID file."
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    exit 0
  }

  Write-Log INFO "Stopping VM process $pid..."
  try {
    Stop-Process -Id ([int]$pid) -Force
  } catch {
    throw "Failed to stop VM PID $pid: $($_.Exception.Message)"
  }

  Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
  Write-Log INFO "Stopped."
} catch {
  Write-Log ERROR $_.Exception.Message
  throw
}

