# ========== CONFIGURACIÓN ==========
$zabbixUrl = "http://10.1.0.66/zabbix/api_jsonrpc.php"
$authToken = "d34eef98f6d9445329497e003e7c59a2"
$hostsFile = "hosts_a_agregar.txt"  # formato: nombre[TAB]IP

# Lista global de hosts no encontrados
$noProvisionados = @()

# ========== FUNCIÓN PARA CONSULTAR HOST ==========
function Get-HostStatus {
    param (
        [string]$hostname,
        [string]$ip
    )

    Write-Host "`n→ Verificando host: $hostname con IP: $ip" -ForegroundColor Cyan

    $hostInfo = $null

    # Buscar por nombre
    $searchByName = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            output       = "extend"
            selectGroups = "extend"
            filter       = @{ host = @($hostname) }
        }
        auth   = $authToken
        id     = 1
    } | ConvertTo-Json -Depth 5

    try {
        $hostInfo = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $searchByName -ContentType "application/json"
    } catch {}

    # Si no encontró por nombre, busca por IP
    if (-not $hostInfo -or $hostInfo.result.Count -eq 0) {
        $searchByIP = @{
            jsonrpc = "2.0"
            method  = "host.get"
            params  = @{
                output       = "extend"
                selectGroups = "extend"
                filter       = @{ "ip" = @($ip) }
            }
            auth   = $authToken
            id     = 2
        } | ConvertTo-Json -Depth 5

        try {
            $hostInfo = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $searchByIP -ContentType "application/json"
        } catch {}
    }

    # Resultado final
    if ($hostInfo.result.Count -gt 0) {
        $foundHost = $hostInfo.result[0]
        $groups = $foundHost.groups | ForEach-Object { $_.name } | Sort-Object
        Write-Host "[SUCCESS] Host encontrado: $($foundHost.host)" -ForegroundColor Green
        Write-Host "     Grupos: $($groups -join ', ')" -ForegroundColor Gray
    } else {
        Write-Host "[FAIL] Host NO aprovisionado en Zabbix." -ForegroundColor Red
        $global:noProvisionados += "$hostname`t$ip"
    }
}

# ========== PROCESAR ARCHIVO ==========
if (Test-Path $hostsFile) {
    Get-Content $hostsFile | ForEach-Object {
        if ($_ -match "\S") {
            $parts = ($_ -split "[\t]+") | ForEach-Object { $_.Trim() }

            $ipRegex = '^(?:\d{1,3}\.){3}\d{1,3}$'
            $ip = $parts | Where-Object { $_ -match $ipRegex } | Select-Object -First 1
            $hostnameParts = $parts | Where-Object { $_ -notmatch $ipRegex }
            $hostname = ($hostnameParts -join "_").Trim()

            if ($ip -and $hostname) {
                Get-HostStatus -hostname $hostname -ip $ip
            } else {
                Write-Host "[ERROR] Línea inválida: $_" -ForegroundColor Red
            }
        }
    }

    # Mostrar hosts no aprovisionados al final
    if ($noProvisionados.Count -gt 0) {
        Write-Host "`n===== HOSTS NO APROVISIONADOS EN ZABBIX =====" -ForegroundColor Yellow
        $noProvisionados | ForEach-Object { Write-Host $_ -ForegroundColor White }
    } else {
        Write-Host "`nSUCCESS Todos los hosts del archivo están aprovisionados en Zabbix." -ForegroundColor Green
    }

} else {
    Write-Host "[ERROR] Archivo '$hostsFile' no encontrado." -ForegroundColor Red
}
