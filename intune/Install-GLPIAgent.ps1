<#
.SYNOPSIS
    Instala/atualiza o GLPI Agent e cria a tarefa agendada de inventario (Intune Win32 App).

.DESCRIPTION
    1. Localiza o MSI do GLPI Agent (GLPI-Agent-x.y-x64.msi) na mesma pasta do script
    2. Instala, atualiza ou apenas reconfigura o servidor, conforme o necessario
    3. Cria um script de execucao em C:\ProgramData\GLPI-Agent-Intune que:
         - testa se o servidor GLPI responde (TCP na porta da URL)
         - executa "glpi-agent --force" e registra log
    4. Registra a tarefa agendada "GLPI_Inventario_Forcado" como SYSTEM
       a cada N minutos (padrao 240 / 4h) e na inicializacao
    5. Grava marcador em HKLM:\SOFTWARE\GLPI-Agent-Intune usado pela deteccao

    Comando de instalacao no Intune:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-GLPIAgent.ps1

    Parametros podem ser passados no comando, ex.:
      ... -File .\Install-GLPIAgent.ps1 -ServerUrl "https://glpi.empresa.local/front/inventory.php" -Tag "Matriz"

.NOTES
    Codigos de saida: 0 = sucesso, 3010 = sucesso com reinicio pendente, 1 = falha.
#>
[CmdletBinding()]
param(
    [string]$ServerUrl       = 'https://SEU-SERVIDOR-GLPI/front/inventory.php',
    [string]$HttpdTrust      = '',   # vazio = IP/host extraido da ServerUrl
    [int]   $IntervalMinutes = 240,
    [string]$Tag             = '',   # TAG opcional do inventario (ex.: filial)
    [string]$TaskName        = 'GLPI_Inventario_Forcado',
    [switch]$NoSslCheck              # Desativa a validacao do certificado (evite: prefira distribuir a CA do servidor via Intune)
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.1.0'
$WorkDir       = Join-Path $env:ProgramData 'GLPI-Agent-Intune'
$MarkerKey     = 'HKLM:\SOFTWARE\GLPI-Agent-Intune'
$RunnerPath    = Join-Path $WorkDir 'Invoke-GLPIInventory.ps1'

# --- Garante execucao em PowerShell 64 bits (o IME pode chamar em 32 bits) ---
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:WINDIR 'sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [System.Management.Automation.SwitchParameter]) {
            # Switch: so o nome, e apenas quando ligado (-NoSslCheck "True" quebraria o -File)
            if ($kv.Value.IsPresent) { $argList += "-$($kv.Key)" }
        }
        else {
            $argList += "-$($kv.Key)"; $argList += "`"$($kv.Value)`""
        }
    }
    $p = Start-Process -FilePath $ps64 -ArgumentList $argList -Wait -PassThru -NoNewWindow
    exit $p.ExitCode
}

# Pasta de trabalho com ACL protegida: o script dela roda como SYSTEM pela tarefa agendada,
# entao usuarios comuns nao podem criar nem alterar nada aqui (evita elevacao de privilegio).
# Heranca desligada; apenas SYSTEM e Administradores com controle total; dono = Administradores.
$SidSystem = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
$SidAdmins = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')

function New-ProtectedDirectorySecurity {
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetOwner($SidAdmins)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($SidSystem, $SidAdmins)) {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($sid, 'FullControl',
            'ContainerInherit, ObjectInherit', 'None', 'Allow')))
    }
    return $acl
}

function Initialize-ProtectedDirectory([string]$Path) {
    # Pasta preexistente so e reaproveitada se ja estiver protegida por este script (dono
    # SYSTEM/Administradores e heranca desligada). Senao (criada por usuario, versao antiga do
    # script, link/junction...) e apagada sem seguir links e recriada.
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        $trusted = $false
        if ($item.PSIsContainer -and -not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            $cur = Get-Acl -LiteralPath $Path
            $owner = $cur.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
            $trusted = $cur.AreAccessRulesProtected -and ($owner -in @($SidSystem.Value, $SidAdmins.Value))
        }
        if (-not $trusted) {
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                [System.IO.Directory]::Delete($Path, $false)          # remove so o link
            }
            elseif ($item.PSIsContainer) {
                & cmd.exe /d /c "rmdir /s /q `"$Path`"" | Out-Null   # rmdir nao segue junctions
            }
            else {
                Remove-Item -LiteralPath $Path -Force
            }
            if (Test-Path -LiteralPath $Path) { throw "Nao foi possivel recriar com seguranca a pasta $Path" }
        }
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Set-Acl -LiteralPath $Path -AclObject (New-ProtectedDirectorySecurity)
        # Algo criado na janela entre a criacao e a ACL nao e confiavel
        if (Get-ChildItem -LiteralPath $Path -Force) { throw "Conteudo inesperado em $Path recem-criada; abortando." }
    }
    else {
        Set-Acl -LiteralPath $Path -AclObject (New-ProtectedDirectorySecurity)
    }
}

Initialize-ProtectedDirectory -Path $WorkDir
$LogFile = Join-Path $WorkDir 'install.log'
if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 2MB) { Move-Item $LogFile "$LogFile.old" -Force }

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Output $line
}

function ConvertTo-Version {
    param([string]$Text)
    $clean = ($Text -replace '[^0-9\.]', '').Trim('.')
    $parts = @($clean.Split('.') | Where-Object { $_ -ne '' })
    while ($parts.Count -lt 4) { $parts += '0' }
    return [version]($parts[0..3] -join '.')
}

function Get-InstalledAgent {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'GLPI Agent*' } |
        Select-Object -First 1
}

function Get-AgentBat {
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base) {
            $p = Join-Path $base 'GLPI-Agent\glpi-agent.bat'
            if (Test-Path $p) { return $p }
        }
    }
    return $null
}

try {
    Write-Log "===== Inicio da instalacao (script v$ScriptVersion) em $env:COMPUTERNAME ====="
    Write-Log "ServerUrl=$ServerUrl | Intervalo=$IntervalMinutes min | Tag=$Tag"

    if ($ServerUrl -match 'SEU-SERVIDOR-GLPI') {
        throw 'ServerUrl nao configurada. Gere o pacote com Build-IntunePackage.ps1 -ServerUrl ... ou passe -ServerUrl no comando.'
    }
    $uri = $null
    if (-not [uri]::TryCreate($ServerUrl, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin 'http', 'https') {
        throw "ServerUrl invalida: '$ServerUrl' (ex.: https://glpi.suaempresa.local/front/inventory.php)"
    }
    if (-not $HttpdTrust) { $HttpdTrust = $uri.Host }
    if ($uri.Scheme -ne 'https') { Write-Log 'ServerUrl em HTTP: inventario sem criptografia. Recomenda-se HTTPS.' 'WARN' }
    if ($NoSslCheck) { Write-Log 'NoSslCheck ativo: o certificado do servidor NAO e validado. Prefira distribuir a CA via Intune.' 'WARN' }

    # ---------------------------------------------------------------- MSI
    $msi = Get-ChildItem -Path $PSScriptRoot -Filter 'GLPI-Agent-*-x64.msi' -File |
        Sort-Object { ConvertTo-Version ($_.Name -replace '^GLPI-Agent-([\d\.]+)-.*$', '$1') } -Descending |
        Select-Object -First 1
    if (-not $msi) { throw "MSI 'GLPI-Agent-*-x64.msi' nao encontrado em $PSScriptRoot" }
    $msiVersion = ConvertTo-Version ($msi.Name -replace '^GLPI-Agent-([\d\.]+)-.*$', '$1')
    Write-Log "Pacote encontrado: $($msi.Name) (versao $msiVersion)"

    $installed = Get-InstalledAgent
    $exitCode  = 0

    if ($installed) {
        $instVersion = ConvertTo-Version $installed.DisplayVersion
        Write-Log "GLPI Agent instalado: versao $instVersion"
    }

    if (-not $installed -or $instVersion -lt $msiVersion) {
        # Copia local (evita problemas com caminho de rede/cache do IME)
        $localMsi = Join-Path $WorkDir $msi.Name
        Copy-Item -Path $msi.FullName -Destination $localMsi -Force

        $msiLog = Join-Path $WorkDir 'msiexec.log'
        $msiArgs = @(
            '/i', "`"$localMsi`"", '/quiet', '/norestart',
            "SERVER=`"$ServerUrl`"",
            'RUNNOW=1',
            'ADDLOCAL=ALL',
            'EXECMODE=1',
            'SCAN_HOMEDIRS=0',
            'ADD_FIREWALL_EXCEPTION=0',
            "HTTPD_TRUST=`"$HttpdTrust`"",
            '/L*V', "`"$msiLog`""
        )
        if ($Tag) { $msiArgs += "TAG=`"$Tag`"" }
        if ($NoSslCheck) { $msiArgs += 'NO_SSL_CHECK=1' }

        Write-Log ("Executando: msiexec.exe " + ($msiArgs -join ' '))
        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
        $exitCode = $proc.ExitCode
        Remove-Item -Path $localMsi -Force -ErrorAction SilentlyContinue

        if ($exitCode -notin 0, 1641, 3010) { throw "msiexec retornou $exitCode (ver $msiLog)" }
        Write-Log "msiexec concluido com codigo $exitCode"
    }
    else {
        # Ja esta na versao correta: garante que aponta para o servidor certo e mantem configs assertivas
        $agentReg = 'HKLM:\SOFTWARE\GLPI-Agent'
        if (Test-Path $agentReg) {
            $changed = $false
            $current = (Get-ItemProperty -Path $agentReg -ErrorAction SilentlyContinue).server
            if ($current -ne $ServerUrl) {
                Write-Log "Atualizando servidor do agente: '$current' -> '$ServerUrl'"
                Set-ItemProperty -Path $agentReg -Name 'server' -Value $ServerUrl
                $changed = $true
            }
            Set-ItemProperty -Path $agentReg -Name 'httpd-trust' -Value $HttpdTrust
            Set-ItemProperty -Path $agentReg -Name 'scan-homedirs' -Value '0'
            if ($Tag) { Set-ItemProperty -Path $agentReg -Name 'tag' -Value $Tag }
            Set-ItemProperty -Path $agentReg -Name 'no-ssl-check' -Value $(if ($NoSslCheck) { '1' } else { '0' })
            if ($changed) {
                Restart-Service -Name 'glpi-agent' -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $agentBat = Get-AgentBat
    if (-not $agentBat) { throw 'glpi-agent.bat nao encontrado apos a instalacao.' }
    Write-Log "Agente em: $agentBat"

    $svc = Get-Service -Name 'glpi-agent' -ErrorAction SilentlyContinue
    if ($svc) {
        Set-Service -Name 'glpi-agent' -StartupType Automatic
        # Configura DelayedAutoStart para nao sobrecarregar o boot da maquina
        & sc.exe config glpi-agent start= delayed-auto | Out-Null
        if ($svc.Status -ne 'Running') { Start-Service -Name 'glpi-agent' -ErrorAction SilentlyContinue }
        Write-Log "Servico glpi-agent: $((Get-Service glpi-agent).Status) (inicio automatico postergado)"
    }

    # ------------------------------------------------- Script da tarefa agendada
    $runner = @'
# Gerado por Install-GLPIAgent.ps1 - executado pela tarefa agendada como SYSTEM
$ServerUrl = '__SERVER_URL__'
$NoSsl     = '__NO_SSL_CHECK__'
$LogFile   = Join-Path $env:ProgramData 'GLPI-Agent-Intune\inventory.log'
if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 1MB) { Move-Item $LogFile "$LogFile.old" -Force }
function Write-Log([string]$m) { Add-Content -Path $LogFile -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }

$uri = [uri]$ServerUrl
$ok  = $false

# Conectividade com ate 3 tentativas (resiliente a retomada de sleep/VPN)
for ($attempt = 1; $attempt -le 3; $attempt++) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $port = if ($uri.Port -gt 0) { $uri.Port } elseif ($uri.Scheme -eq 'https') { 443 } else { 80 }
        $connectTask = $tcp.ConnectAsync($uri.Host, $port)
        if ($connectTask.Wait(4000) -and $tcp.Connected) {
            $ok = $true
            break
        }
    } catch {
        $ok = $false
    } finally {
        $tcp.Close()
        $tcp.Dispose()
    }
    if ($attempt -lt 3) { Start-Sleep -Seconds 2 }
}

if (-not $ok) {
    Write-Log "FALHA: servidor $($uri.Host) inacessivel apos 3 tentativas"
    exit 1
}

$agent = $null
foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if ($base -and (Test-Path (Join-Path $base 'GLPI-Agent\glpi-agent.bat'))) { $agent = Join-Path $base 'GLPI-Agent\glpi-agent.bat'; break }
}
if (-not $agent) { Write-Log 'FALHA: glpi-agent.bat nao encontrado'; exit 2 }

Write-Log "Servidor $($uri.Host) acessivel - executando inventario forcado"
$extraArgs = @('--force')
if ($NoSsl -eq '1') { $extraArgs += '--no-ssl-check' }

$out = & $agent @extraArgs 2>&1
$rc  = $LASTEXITCODE
$out | Select-Object -Last 5 | ForEach-Object { Write-Log "  $_" }

if ($rc -eq 0) {
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\GLPI-Agent-Intune' -Name 'LastInventorySuccess' -Value (Get-Date -Format 's') -ErrorAction SilentlyContinue
    Write-Log "Inventario finalizado com sucesso"
} else {
    Write-Log "Inventario finalizado (codigo $rc)"
}
exit $rc
'@
    $runner = $runner.Replace('__SERVER_URL__', $ServerUrl.Replace("'", "''"))
    $runner = $runner.Replace('__NO_SSL_CHECK__', $(if ($NoSslCheck) { '1' } else { '0' }))
    # Arquivo preexistente (pode ter sido plantado antes da ACL) e removido e recriado
    if (Test-Path -LiteralPath $RunnerPath) { Remove-Item -LiteralPath $RunnerPath -Force }
    Set-Content -Path $RunnerPath -Value $runner -Encoding UTF8 -Force
    Write-Log "Script da tarefa criado: $RunnerPath"

    # ------------------------------------------------------ Tarefa agendada
    $action = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$RunnerPath`""

    $tRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) `
        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
        -RandomDelay (New-TimeSpan -Minutes ([Math]::Min(10, [Math]::Max(1, [int]($IntervalMinutes / 3)))))
    $tBoot = New-ScheduledTaskTrigger -AtStartup
    $tBoot.Delay = 'PT5M'

    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1) -RunOnlyIfNetworkAvailable

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($tRepeat, $tBoot) `
        -Principal $principal -Settings $settings `
        -Description "Forca inventario GLPI a cada $IntervalMinutes minutos (Intune)" -Force | Out-Null
    Write-Log "Tarefa '$TaskName' registrada (a cada $IntervalMinutes min + inicializacao)"

    # ------------------------------------------------------ Marcador p/ deteccao
    New-Item -Path $MarkerKey -Force | Out-Null
    Set-ItemProperty -Path $MarkerKey -Name 'ScriptVersion'   -Value $ScriptVersion
    Set-ItemProperty -Path $MarkerKey -Name 'AgentVersion'    -Value $msiVersion.ToString()
    Set-ItemProperty -Path $MarkerKey -Name 'ServerUrl'       -Value $ServerUrl
    Set-ItemProperty -Path $MarkerKey -Name 'IntervalMinutes' -Value $IntervalMinutes
    Set-ItemProperty -Path $MarkerKey -Name 'InstalledOn'     -Value (Get-Date -Format 's')

    # Primeiro inventario imediato (nao bloqueia a instalacao)
    Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    Write-Log "===== Instalacao concluida (codigo $exitCode) ====="
    if ($exitCode -in 1641, 3010) { exit 3010 }
    exit 0
}
catch {
    Write-Log "ERRO: $($_.Exception.Message)" 'ERROR'
    exit 1
}
