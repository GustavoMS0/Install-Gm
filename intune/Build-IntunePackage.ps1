<#
.SYNOPSIS
    Monta o pacote .intunewin do GLPI Agent pronto para upload no Intune.

.DESCRIPTION
    1. Baixa o MSI x64 do GLPI Agent (ultima versao estavel ou a informada)
    2. Copia Install/Detect/Uninstall para .\source, ja com ServerUrl e versao ajustados
    3. Baixa o Microsoft Win32 Content Prep Tool (IntuneWinAppUtil.exe) e gera o .intunewin

.EXAMPLE
    .\Build-IntunePackage.ps1 -ServerUrl 'http://glpi.suaempresa.local/front/inventory.php'

.EXAMPLE
    .\Build-IntunePackage.ps1 -ServerUrl 'http://glpi.empresa.local/front/inventory.php' -AgentVersion 1.19 -IntervalMinutes 30
#>
param(
    [Parameter(Mandatory)] [string]$ServerUrl,
    [string]$AgentVersion    = '',    # vazio = ultima release estavel no GitHub
    [int]   $IntervalMinutes = 30,
    [string]$Tag             = '',
    [switch]$NoSslCheck               # Desativa checagem estrita de SSL
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$Here   = $PSScriptRoot
$Source = Join-Path $Here 'source'
$Output = Join-Path $Here 'output'
New-Item -ItemType Directory -Path $Source, $Output -Force | Out-Null

# ------------------------------------------------------------------ MSI
$api = if ($AgentVersion) { "https://api.github.com/repos/glpi-project/glpi-agent/releases/tags/$AgentVersion" }
       else { 'https://api.github.com/repos/glpi-project/glpi-agent/releases/latest' }
Write-Host "Consultando $api"
$rel   = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'glpi-intune-build' }
$asset = $rel.assets | Where-Object { $_.name -match '^GLPI-Agent-[\d\.]+-x64\.msi$' } | Select-Object -First 1
if (-not $asset) { throw "MSI x64 nao encontrado na release $($rel.tag_name)" }
$version = $asset.name -replace '^GLPI-Agent-([\d\.]+)-x64\.msi$', '$1'

Get-ChildItem -Path $Source -Filter 'GLPI-Agent-*.msi' | Where-Object Name -ne $asset.name | Remove-Item -Force
$msiPath = Join-Path $Source $asset.name
if (-not (Test-Path $msiPath)) {
    Write-Host "Baixando $($asset.name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msiPath -UseBasicParsing
}
Write-Host "MSI: $($asset.name) (versao $version)"

# ------------------------------------------------------ Scripts parametrizados
$esc = $ServerUrl.Replace("'", "''")

$install = Get-Content (Join-Path $Here 'Install-GLPIAgent.ps1') -Raw
$install = $install -replace "(\[string\]\`$ServerUrl\s*=\s*)'[^']*'", "`$1'$esc'"
$install = $install -replace "(\[int\]\s*\`$IntervalMinutes\s*=\s*)\d+", "`${1}$IntervalMinutes"
$install = $install -replace "(\[string\]\`$Tag\s*=\s*)'[^']*'", "`$1'$($Tag.Replace("'", "''"))'"
if ($NoSslCheck) {
    $install = $install -replace '\[switch\]\$NoSslCheck', '[switch]$NoSslCheck = $true'
}
Set-Content -Path (Join-Path $Source 'Install-GLPIAgent.ps1') -Value $install -Encoding UTF8

$detect = Get-Content (Join-Path $Here 'Detect-GLPIAgent.ps1') -Raw
$detect = $detect -replace "(\`$RequiredVersion\s*=\s*)'[^']*'", "`$1'$version'"
$detect = $detect -replace "(\`$ExpectedServerUrl\s*=\s*)'[^']*'", "`$1'$esc'"
Set-Content -Path (Join-Path $Output 'Detect-GLPIAgent.ps1') -Value $detect -Encoding UTF8

Copy-Item (Join-Path $Here 'Uninstall-GLPIAgent.ps1') $Source -Force

# ------------------------------------------------------ IntuneWinAppUtil
$tool = Join-Path $Here 'IntuneWinAppUtil.exe'
if (-not (Test-Path $tool)) {
    Write-Host 'Baixando IntuneWinAppUtil.exe...'
    Invoke-WebRequest -UseBasicParsing -OutFile $tool `
        -Uri 'https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe'
}

Get-ChildItem $Output -Filter '*.intunewin' | Remove-Item -Force
& $tool -c $Source -s 'Install-GLPIAgent.ps1' -o $Output -q
if ($LASTEXITCODE -ne 0) { throw "IntuneWinAppUtil falhou ($LASTEXITCODE)" }

$final = Join-Path $Output "GLPI-Agent-$version-Intune.intunewin"
Move-Item (Join-Path $Output 'Install-GLPIAgent.intunewin') $final -Force

Write-Host ''
Write-Host '================= PACOTE PRONTO =================' -ForegroundColor Green
Write-Host "Arquivo ...........: $final"
Write-Host "Script de deteccao : $(Join-Path $Output 'Detect-GLPIAgent.ps1')"
Write-Host 'Instalar ..........: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-GLPIAgent.ps1'
Write-Host 'Desinstalar .......: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-GLPIAgent.ps1'
Write-Host 'Comportamento .....: Sistema | Reinicio: determinado pelo codigo de retorno (3010 = soft reboot)'
