<#
.SYNOPSIS
    Script de deteccao do Intune para o GLPI Agent.

.DESCRIPTION
    Considera "instalado" somente se:
      - GLPI Agent instalado com versao >= $RequiredVersion
      - Tarefa agendada existe
      - Marcador do Intune aponta para o servidor esperado
    Se o servidor ou a versao mudarem aqui, o Intune reexecuta a instalacao.

    Configuracao no Intune: "Use a custom detection script", executar em 64 bits = Sim.
    Regra do Intune: sucesso = codigo de saida 0 E alguma saida em STDOUT.
#>
$RequiredVersion   = '1.19'
$ExpectedServerUrl = 'http://SEU-SERVIDOR-GLPI/front/inventory.php'
$TaskName          = 'GLPI_Inventario_Forcado'

function ConvertTo-Version([string]$Text) {
    $parts = @((($Text -replace '[^0-9\.]', '').Trim('.')).Split('.') | Where-Object { $_ -ne '' })
    while ($parts.Count -lt 4) { $parts += '0' }
    [version]($parts[0..3] -join '.')
}

$agent = Get-ItemProperty -Path @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like 'GLPI Agent*' } | Select-Object -First 1

if (-not $agent) { exit 1 }
if ((ConvertTo-Version $agent.DisplayVersion) -lt (ConvertTo-Version $RequiredVersion)) { exit 1 }
if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) { exit 1 }

$svc = Get-Service -Name 'glpi-agent' -ErrorAction SilentlyContinue
if (-not $svc) { exit 1 }

$marker = Get-ItemProperty -Path 'HKLM:\SOFTWARE\GLPI-Agent-Intune' -ErrorAction SilentlyContinue
if (-not $marker -or $marker.ServerUrl -ne $ExpectedServerUrl) { exit 1 }

Write-Output "GLPI Agent $($agent.DisplayVersion) instalado, servico ativo e tarefa '$TaskName' presente"
exit 0
