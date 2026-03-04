# ========== CONFIGURACIÓN ==========
$zabbixUrl = "http://172.18.168.120/zabbix/api_jsonrpc.php"
$authToken = "d6bfe7c9275a4241438ae68ce2f2e253"
$hostsFile = "hosts_a_eliminar.txt"

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
        auth = $authToken
        id   = 1
    } | ConvertTo-Json -Depth 4

    try {
        $getResponse = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $getBody -ContentType "application/json"
        $hostId = $getResponse.result[0].hostid

        if (-not $hostId) {
            Write-Host "[ERROR] Host '$hostname' no encontrado." -ForegroundColor Red
            return
        }

        Write-Host "→ Eliminando host ID $hostId ($hostname)..."

        $deleteBody = @{
            jsonrpc = "2.0"
            method  = "host.delete"
            params  = @($hostId)
            auth    = $authToken
            id      = 2
        } | ConvertTo-Json -Depth 3

        $deleteResponse = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $deleteBody -ContentType "application/json"

        if ($deleteResponse.result -contains $hostId) {
            Write-Host "[OK] Host '$hostname' eliminado exitosamente." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Fallo la eliminación de '$hostname'." -ForegroundColor Red
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
                # Consideramos que el hostname puede estar en cualquier columna
                $ipRegex = '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$'
                $hostname = $parts | Where-Object { $_ -notmatch $ipRegex } | Select-Object -First 1

                if ($hostname) {
                    Remove-ZabbixHost -hostname $hostname
                } else {
                    Write-Host "[ERROR] No se encontró un hostname válido en línea: $line" -ForegroundColor Red
                }
            } elseif ($parts.Count -eq 1) {
                # Si solo hay un campo, asumimos que es el hostname directamente
                Remove-ZabbixHost -hostname $parts[0]
            }
        }
    }
} else {
    Write-Host "Archivo '$hostsFile' no encontrado." -ForegroundColor Red
}
