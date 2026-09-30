<#
.SYNOPSIS
    Remove a tarefa agendada, o GLPI Agent e os arquivos criados pelo pacote Intune.

    Comando de desinstalacao no Intune:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-GLPIAgent.ps1
#>
param([string]$TaskName = 'GLPI_Inventario_Forcado')

$WorkDir = Join-Path $env:ProgramData 'GLPI-Agent-Intune'
$LogFile = Join-Path $env:TEMP 'GLPI-Agent-Uninstall.log'
function Write-Log([string]$m) { Add-Content -Path $LogFile -Value ('{0} {1}' -f (Get-Date -Format 's'), $m) }

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Log "Tarefa '$TaskName' removida"

    $apps = Get-ItemProperty -Path @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        ) -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'GLPI Agent*' }

    $rc = 0
    foreach ($app in $apps) {
        $code = $app.PSChildName
        if ($code -match '^\{[0-9A-Fa-f\-]+\}$') {
            Write-Log "Desinstalando $($app.DisplayName) $code"
            $p = Start-Process msiexec.exe -ArgumentList "/x $code /quiet /norestart" -Wait -PassThru
            if ($p.ExitCode -notin 0, 1605, 1641, 3010) { $rc = $p.ExitCode }
            if ($p.ExitCode -in 1641, 3010 -and $rc -eq 0) { $rc = 3010 }
        }
    }

    Remove-Item -Path 'HKLM:\SOFTWARE\GLPI-Agent-Intune' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Concluido (codigo $rc)"
    exit $rc
}
catch {
    Write-Log "ERRO: $($_.Exception.Message)"
    exit 1
}
