<#
.SYNOPSIS
    Monta o pacote .intunewin do GLPI Agent pronto para upload no Intune.

.DESCRIPTION
    1. Baixa o MSI x64 do GLPI Agent (ultima versao estavel ou a informada) e confere o
       SHA-256 publicado pelo GitHub para o asset da release (e a assinatura Authenticode, se houver)
    2. Copia Install/Detect/Uninstall para .\source, ja com ServerUrl e versao ajustados
    3. Baixa o Microsoft Win32 Content Prep Tool (IntuneWinAppUtil.exe) de uma tag fixa,
       confere a assinatura digital da Microsoft e gera o .intunewin

    Use sempre HTTPS na ServerUrl. -NoSslCheck desliga a validacao do certificado no agente
    (qualquer um no caminho pode se passar pelo servidor): prefira distribuir a CA/certificado
    do servidor para as maquinas (perfil de certificado confiavel do Intune).

.EXAMPLE
    .\Build-IntunePackage.ps1 -ServerUrl 'https://glpi.suaempresa.local/front/inventory.php'

.EXAMPLE
    .\Build-IntunePackage.ps1 -ServerUrl 'https://glpi.empresa.local/front/inventory.php' -AgentVersion 1.19 -IntervalMinutes 30
#>
param(
    [Parameter(Mandatory)] [string]$ServerUrl,
    [string]$AgentVersion    = '',    # vazio = ultima release estavel no GitHub
    [int]   $IntervalMinutes = 30,
    [string]$Tag             = '',
    [switch]$NoSslCheck,              # Desativa checagem estrita de SSL (evite; veja a descricao)
    [string]$ContentPrepToolTag = 'v1.8.7'   # tag do microsoft/Microsoft-Win32-Content-Prep-Tool
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

# SHA-256 conhecido do IntuneWinAppUtil.exe da tag padrao (conferido alem da assinatura)
$ContentPrepToolDefaultTag    = 'v1.8.7'
$ContentPrepToolDefaultSha256 = 'C1BA45B5CB939E84AF064BB7FF4B38FB3DFE33C8DC1078FD9B157672EAE671F6'

$Here   = $PSScriptRoot
$Source = Join-Path $Here 'source'
$Output = Join-Path $Here 'output'
New-Item -ItemType Directory -Path $Source, $Output -Force | Out-Null

$uri = $null
if (-not [uri]::TryCreate($ServerUrl, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin 'http', 'https') {
    throw "ServerUrl invalida: '$ServerUrl'"
}
if ($uri.Scheme -ne 'https') {
    Write-Warning 'ServerUrl usa HTTP: o inventario trafega sem criptografia. Recomenda-se HTTPS.'
}
if ($NoSslCheck) {
    Write-Warning '-NoSslCheck desliga a validacao do certificado do servidor no agente. Prefira distribuir a CA do servidor via Intune.'
}

# Texto para usar como SUBSTITUICAO em -replace: '$' precisa virar '$$'
function ConvertTo-ReplacementText([string]$Text) { $Text.Replace('$', '$$') }

function Test-Sha256([string]$Path, [string]$Expected, [string]$Label) {
    $got = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    if ($got -ne $Expected.ToUpperInvariant()) {
        Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue
        throw "$Label`: SHA-256 nao confere (esperado $Expected, obtido $got). Arquivo removido."
    }
    Write-Host "$Label`: SHA-256 conferido"
}

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

# Integridade do MSI (tambem para um MSI ja presente em .\source):
#  - SHA-256 publicado pelo GitHub para o asset (campo digest), obrigatorio quando existe
#  - assinatura Authenticode: se o MSI for assinado, precisa ser valida
$digest = "$($asset.digest)"
$msiSig = Get-AuthenticodeSignature -FilePath $msiPath
if ($msiSig.Status -notin 'Valid', 'NotSigned') {
    Remove-Item -Path $msiPath -Force -ErrorAction SilentlyContinue
    throw "Assinatura do MSI invalida ($($msiSig.Status)). Arquivo removido."
}
if ($digest -match '^sha256:([0-9a-fA-F]{64})$') {
    Test-Sha256 -Path $msiPath -Expected $Matches[1] -Label $asset.name
}
elseif ($msiSig.Status -eq 'Valid') {
    Write-Warning "O GitHub nao publicou o SHA-256 de $($asset.name); confiando apenas na assinatura digital."
}
else {
    Remove-Item -Path $msiPath -Force -ErrorAction SilentlyContinue
    throw "Nao foi possivel verificar $($asset.name): sem SHA-256 publicado e sem assinatura digital."
}
if ($msiSig.Status -eq 'Valid') { Write-Host "MSI assinado por: $($msiSig.SignerCertificate.Subject)" }
Write-Host "MSI: $($asset.name) (versao $version)"

# ------------------------------------------------------ Scripts parametrizados
# Valores entre aspas simples no script gerado: ' vira ''. Na substituicao do -replace: $ vira $$.
$esc    = ConvertTo-ReplacementText $ServerUrl.Replace("'", "''")
$escTag = ConvertTo-ReplacementText $Tag.Replace("'", "''")

$install = Get-Content (Join-Path $Here 'Install-GLPIAgent.ps1') -Raw
$install = $install -replace "(\[string\]\`$ServerUrl\s*=\s*)'[^']*'", ('${1}''' + $esc + '''')
$install = $install -replace "(\[int\]\s*\`$IntervalMinutes\s*=\s*)\d+", ('${1}' + $IntervalMinutes)
$install = $install -replace "(\[string\]\`$Tag\s*=\s*)'[^']*'", ('${1}''' + $escTag + '''')
if ($NoSslCheck) {
    $install = $install -replace '\[switch\]\$NoSslCheck', '[switch]$$NoSslCheck = $$true'
}
Set-Content -Path (Join-Path $Source 'Install-GLPIAgent.ps1') -Value $install -Encoding UTF8

$detect = Get-Content (Join-Path $Here 'Detect-GLPIAgent.ps1') -Raw
$detect = $detect -replace "(\`$RequiredVersion\s*=\s*)'[^']*'", ('${1}''' + (ConvertTo-ReplacementText $version) + '''')
$detect = $detect -replace "(\`$ExpectedServerUrl\s*=\s*)'[^']*'", ('${1}''' + $esc + '''')
Set-Content -Path (Join-Path $Output 'Detect-GLPIAgent.ps1') -Value $detect -Encoding UTF8

Copy-Item (Join-Path $Here 'Uninstall-GLPIAgent.ps1') $Source -Force

# ------------------------------------------------------ IntuneWinAppUtil
# Tag fixa (nunca a branch master) + assinatura Authenticode valida da Microsoft,
# conferida a cada execucao (inclusive para um .exe ja baixado).
$tool = Join-Path $Here 'IntuneWinAppUtil.exe'
if (-not (Test-Path $tool)) {
    Write-Host "Baixando IntuneWinAppUtil.exe ($ContentPrepToolTag)..."
    Invoke-WebRequest -UseBasicParsing -OutFile $tool `
        -Uri "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/$ContentPrepToolTag/IntuneWinAppUtil.exe"
}
$toolSig = Get-AuthenticodeSignature -FilePath $tool
if ($toolSig.Status -ne 'Valid' -or $toolSig.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') {
    Remove-Item -Path $tool -Force -ErrorAction SilentlyContinue
    throw "IntuneWinAppUtil.exe sem assinatura valida da Microsoft ($($toolSig.Status): $($toolSig.SignerCertificate.Subject)). Arquivo removido."
}
if ($ContentPrepToolTag -eq $ContentPrepToolDefaultTag) {
    Test-Sha256 -Path $tool -Expected $ContentPrepToolDefaultSha256 -Label 'IntuneWinAppUtil.exe'
}
Write-Host "IntuneWinAppUtil.exe assinado por: $($toolSig.SignerCertificate.Subject)"

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
