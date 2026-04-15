Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

function Get-DockerContextsJson {
  Assert-Command docker
  $r = Invoke-External -FilePath (Get-Command docker).Path -Arguments @('context','ls','--format','{{json .}}')
  $lines = $r.Stdout -split "`r?`n" | Where-Object { $_ -and $_.Trim().Length -gt 0 }
  $objs = @()
  foreach ($ln in $lines) {
    try { $objs += ($ln | ConvertFrom-Json) } catch {}
  }
  return $objs
}

function Ensure-DockerContextSsh {
  param(
    [Parameter(Mandatory)] [string] $ContextName,
    [Parameter(Mandatory)] [string] $SshUser,
    [Parameter(Mandatory)] [int] $SshPort,
    [Parameter(Mandatory)] [string] $Description
  )

  $existing = (Get-DockerContextsJson | Where-Object { $_.Name -eq $ContextName })
  if ($existing) {
    Write-Log INFO "Docker context already exists: $ContextName"
    return
  }

  $host = "ssh://$SshUser@localhost:$SshPort"
  Write-Log INFO "Creating Docker context '$ContextName' -> $host"
  Invoke-External -FilePath (Get-Command docker).Path -Arguments @(
    'context','create',$ContextName,
    '--description', ('"' + $Description.Replace('"','\"') + '"'),
    '--docker', ('"host=' + $host + '"')
  ) | Out-Null
}

function Set-DockerContextCurrent {
  param([Parameter(Mandatory)] [string] $ContextName)
  Write-Log INFO "Switching current Docker context to: $ContextName"
  Invoke-External -FilePath (Get-Command docker).Path -Arguments @('context','use',$ContextName) | Out-Null
}

