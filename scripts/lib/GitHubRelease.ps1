Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

function Get-LatestRelease {
  param(
    [Parameter(Mandatory)] [string] $Owner,
    [Parameter(Mandatory)] [string] $Repo
  )
  $uri = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
  $headers = @{ 'User-Agent' = 'nix-docker-vm-bootstrap' }
  return Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
}

function Get-ReleaseByTag {
  param(
    [Parameter(Mandatory)] [string] $Owner,
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Tag
  )
  $uri = "https://api.github.com/repos/$Owner/$Repo/releases/tags/$Tag"
  $headers = @{ 'User-Agent' = 'nix-docker-vm-bootstrap' }
  return Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
}

function Download-Asset {
  param(
    [Parameter(Mandatory)] [string] $Url,
    [Parameter(Mandatory)] [string] $OutFile
  )
  $headers = @{ 'User-Agent' = 'nix-docker-vm-bootstrap' }
  Invoke-WebRequest -Uri $Url -OutFile $OutFile -Headers $headers -UseBasicParsing
}

function Get-AssetUrlByName {
  param(
    [Parameter(Mandatory)] $ReleaseJson,
    [Parameter(Mandatory)] [string] $AssetName
  )
  foreach ($a in $ReleaseJson.assets) {
    if ($a.name -eq $AssetName) { return $a.browser_download_url }
  }
  return $null
}

