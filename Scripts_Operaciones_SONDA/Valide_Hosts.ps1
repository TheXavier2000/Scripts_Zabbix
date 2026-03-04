# ========== CONFIGURACIÓN ==========
$zabbixUrl = "http://10.161.115.127/zabbix/api_jsonrpc.php"
$authToken = "c72cf6e672eb4c4800c004902e70f798"
$hostsFile = "hosts_a_agregar.txt"  # Formato: nombre[TAB]IP

$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $authToken"
}

# Lista para hosts no encontrados
$noProvisionados = @()

# ========== FUNCIONES ==========

function Get-HostByIP {
    param ([string]$ip)

    $body = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            output           = @("hostid", "host")
            selectInterfaces = "extend"
        }
        id = 1
    }

    $jsonBody = $body | ConvertTo-Json -Depth 4

    try {
        $response = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Headers $headers -Body $jsonBody
        foreach ($hostzbx in $response.result) {
            foreach ($iface in $hostzbx.interfaces) {
                if ($iface.useip -eq 1 -and $iface.ip -eq $ip) {
                    return $hostzbx
                }
            }
        }
    } catch {
        Write-Host "[ERROR] Fallo en la consulta: $_" -ForegroundColor Red
    }

    return $null
}

# ========== PROCESAR ARCHIVO ==========

if (Test-Path $hostsFile) {
    Get-Content $hostsFile | ForEach-Object {
        if ($_ -match "\S") {
            $parts = ($_ -split "\s+") | ForEach-Object { $_.Trim() }

            $ipRegex = '^(?:\d{1,3}\.){3}\d{1,3}$'
            $ip = $parts | Where-Object { $_ -match $ipRegex } | Select-Object -First 1
            $hostnameParts = $parts | Where-Object { $_ -notmatch $ipRegex }
            $hostname = ($hostnameParts -join "_").Trim()

            if ($ip -and $hostname) {
                Write-Host "`n→ Validando host: $hostname / IP: $ip" -ForegroundColor Cyan

                $hostzbx = Get-HostByIP -ip $ip

                if ($hostzbx) {
                    Write-Host "[OK] Host ya está aprovisionado en Zabbix (ID: $($hostzbx.hostid), Host: $($hostzbx.host))" -ForegroundColor Green
                } else {
                    Write-Host "[NO ENCONTRADO] Host NO está en Zabbix." -ForegroundColor Red
                    $noProvisionados += "$hostname`t$ip"
                }
            } else {
                Write-Host "[ERROR] Línea inválida en el archivo: $_" -ForegroundColor Red
            }
        }
    }

    # Mostrar hosts no aprovisionados
    if ($noProvisionados.Count -gt 0) {
        Write-Host "`n===== HOSTS NO PROVISIONADOS EN ZABBIX =====" -ForegroundColor Yellow
        $noProvisionados | ForEach-Object { Write-Host $_ -ForegroundColor White }

        # Guardar en archivo
        $noProvisionados | Set-Content -Path "hosts_no_provisionados.txt"
        Write-Host "`nArchivo 'hosts_no_provisionados.txt' generado con los equipos no aprovisionados." -ForegroundColor Gray
    } else {
        Write-Host "`nSUCCESS Todos los hosts del archivo están aprovisionados en Zabbix." -ForegroundColor Green
    }

} else {
    Write-Host "[ERROR] Archivo '$hostsFile' no encontrado." -ForegroundColor Red
}
