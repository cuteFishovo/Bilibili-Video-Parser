$ErrorActionPreference = 'Stop'
$AppDir = Split-Path -Parent $PSScriptRoot
Set-Location $AppDir

function Invoke-Checked([string]$Command, [string[]]$Arguments) {
  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Command failed with exit code $LASTEXITCODE" }
}

try {
  Write-Host "Application directory: $AppDir"
  $NodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($NodeCommand) {
    $NodeMajor = [int]((& $NodeCommand.Source --version).TrimStart('v').Split('.')[0])
  } else {
    $NodeMajor = 0
  }
  if ($NodeMajor -lt 18) {
    Write-Host 'Downloading portable Node.js 24 (official Windows x64 build)...'
    $RuntimeDir = Join-Path $AppDir '.runtime\node'
    New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
    $PortableDir = Get-ChildItem -Path $RuntimeDir -Directory -Filter 'node-v24.*-win-x64' | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $PortableDir) {
      $Index = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
      $Release = $Index | Where-Object { $_.version -match '^v24\.' } | Select-Object -First 1
      if (-not $Release) { throw 'Could not find a Node.js 24 release at nodejs.org.' }
      $ArchiveName = "node-$($Release.version)-win-x64.zip"
      $ArchivePath = Join-Path $env:TEMP $ArchiveName
      $DownloadUrl = "https://nodejs.org/dist/$($Release.version)/$ArchiveName"
      Invoke-WebRequest -Uri $DownloadUrl -OutFile $ArchivePath
      Expand-Archive -LiteralPath $ArchivePath -DestinationPath $RuntimeDir -Force
      Remove-Item -LiteralPath $ArchivePath -Force
      $PortableDir = Join-Path $RuntimeDir "node-$($Release.version)-win-x64"
    }
    $env:PATH = "$PortableDir;$env:PATH"
    $env:NODE_HOME = $PortableDir
  } else {
    $env:NODE_HOME = Split-Path -Parent $NodeCommand.Source
  }
  $NodeExe = Join-Path $env:NODE_HOME 'node.exe'
  $NpmCmd = Join-Path $env:NODE_HOME 'npm.cmd'
  if (-not (Test-Path -LiteralPath $NpmCmd)) { throw 'npm.cmd was not found beside node.exe.' }

  foreach ($Tool in @('yt-dlp.exe', 'ffmpeg.exe')) {
    $ToolPath = Join-Path $AppDir "bin\$Tool"
    if (-not (Test-Path -LiteralPath $ToolPath -PathType Leaf)) {
      throw "Missing $ToolPath. Copy the Windows executable into bin first."
    }
  }
  Invoke-Checked (Join-Path $AppDir 'bin\yt-dlp.exe') @('--version')
  Invoke-Checked (Join-Path $AppDir 'bin\ffmpeg.exe') @('-version')

  Write-Host 'Installing project dependencies...'
  Invoke-Checked $NpmCmd @('install')
  if (-not (Get-Command pm2.cmd -ErrorAction SilentlyContinue)) {
    Invoke-Checked $NpmCmd @('install', '--global', 'pm2')
  }
  $Pm2 = Get-Command pm2.cmd -ErrorAction SilentlyContinue
  if (-not $Pm2) {
    $Prefix = & npm.cmd prefix --global
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve npm global directory.' }
    $Pm2Path = Join-Path (($Prefix | Select-Object -Last 1).Trim()) 'pm2.cmd'
    if (-not (Test-Path -LiteralPath $Pm2Path)) { throw 'pm2.cmd was not found after installation.' }
  } else {
    $Pm2Path = $Pm2.Source
  }

  Write-Host 'Starting or updating PM2 service...'
  Invoke-Checked $Pm2Path @('startOrRestart', (Join-Path $AppDir 'ecosystem.config.js'), '--only', 'media-parser-site', '--update-env')
  Invoke-Checked $Pm2Path @('save')
  Invoke-Checked $Pm2Path @('status')
  Write-Host 'Complete. Open http://127.0.0.1:2570/'
  exit 0
} catch {
  Write-Host $_.Exception.Message -ForegroundColor Red
  exit 1
}
