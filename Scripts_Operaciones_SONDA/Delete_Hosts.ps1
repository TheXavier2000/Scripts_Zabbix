# ========== CONFIGURACIÓN ==========
$zabbixUrl = "http://10.161.115.127/zabbix/api_jsonrpc.php"
$authToken = "c72cf6e672eb4c4800c004902e70f798"
$hostsFile = "hosts_a_eliminar.txt"

# Encabezados para Bearer Token
$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $authToken"
}

# ========== FUNCIÓN PARA ELIMINAR HOST ==========
function Remove-ZabbixHost {
    param (
        [string]$hostname
    )

    Write-Host "→ Buscando host '$hostname'..."

    $getBody = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            output = @("hostid")
            filter = @{
                host = @($hostname)
            }
        }
        id   = 1
    } | ConvertTo-Json -Depth 4

    try {
        $getResponse = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $getBody -Headers $headers

        if (-not $getResponse.result -or $getResponse.result.Count -eq 0) {
            Write-Host "[ERROR] Host '$hostname' no encontrado." -ForegroundColor Red
            return
        }

        $hostId = $getResponse.result[0].hostid
        Write-Host "→ Eliminando host ID $hostId ($hostname)..."

        $deleteBody = @{
            jsonrpc = "2.0"
            method  = "host.delete"
            params  = @($hostId)
            id      = 2
        } | ConvertTo-Json -Depth 3

        $deleteResponse = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $deleteBody -Headers $headers

        if ($deleteResponse.result -contains $hostId) {
            Write-Host "[OK] Host '$hostname' eliminado exitosamente." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Falló la eliminación de '$hostname'." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[ERROR] Error eliminando '$hostname': $_" -ForegroundColor Red
    }
}

# ========== PROCESAR ARCHIVO ==========
if (Test-Path $hostsFile) {
    Get-Content $hostsFile | ForEach-Object {
        if ($_ -match "\S") {
            $line = $_.Trim()
            $parts = $line -split "\s+"

            if ($parts.Count -ge 2) {
                $ipRegex = '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$'
                $hostname = $parts | Where-Object { $_ -notmatch $ipRegex } | Select-Object -First 1

                if ($hostname) {
                    Remove-ZabbixHost -hostname $hostname
                } else {
                    Write-Host "[ERROR] No se encontró un hostname válido en línea: $line" -ForegroundColor Red
                }
            } elseif ($parts.Count -eq 1) {
                Remove-ZabbixHost -hostname $parts[0]
            }
        }
    }
} else {
    Write-Host "Archivo '$hostsFile' no encontrado." -ForegroundColor Red
}
