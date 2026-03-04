# === CONFIGURACIÓN ===
$zabbixUrl        = "http://10.161.115.127/zabbix/api_jsonrpc.php"
$authToken        = "4b8ffbdb5bdbbfde79c9fd78a54109c0"
$hostsFile        = "hosts_a_agregar.txt"
$templateSnmpId   = 10768

# === HEADERS ===
$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $authToken"
}

# === Función para actualizar solo el template de hosts existentes ===
function UpdateHostTemplateOnly {
    param (
        [string]$ip,
        [string]$hostname
    )

    Write-Host "→ Verificando host '$hostname' con IP $ip..."

    # Buscar host por nombre exacto
    $getBody = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            output                = "extend"
            selectInterfaces      = "extend"
            selectGroups          = "extend"
            selectParentTemplates = "extend"
            filter = @{ host = @($hostname) }
        }
        id = 1
    } | ConvertTo-Json -Depth 5

    $resp = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Headers $headers -Body $getBody

    if ($resp.result.Count -eq 0) {
        Write-Host "[INFO] Host '$hostname' no existe en Zabbix. No se realizará ninguna acción." -ForegroundColor Yellow
        return
    }

    # Host encontrado
    $zabbixHost = $resp.result[0]
    $hostId     = $zabbixHost.hostid

    # --- Preparar update solo de templates ---
    # Aquí reemplazamos TODOS los templates existentes por el nuevo
    $updateParams = @{
        hostid = $hostId
        templates = @(@{ templateid = "$templateSnmpId" })
    }

    Write-Host "→ Actualizando template del host '$hostname' (ID $hostId)..."

    $updateBody = @{
        jsonrpc = "2.0"
        method  = "host.update"
        params  = $updateParams
        id      = 2
    } | ConvertTo-Json -Depth 6

    $updateResponse = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Headers $headers -Body $updateBody

    if ($updateResponse.result.hostids) {
        Write-Host "[OK] Template actualizado correctamente." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] No se pudo actualizar el template del host '$hostname'." -ForegroundColor Red
    }
}

# === Procesar archivo ===
if (Test-Path $hostsFile) {
    Get-Content $hostsFile | ForEach-Object {
        if ($_ -match "\S") {
            $parts = ($_ -split "\s+") | ForEach-Object { $_.Trim() }
            $ipRegex = '^(?:\d{1,3}\.){3}\d{1,3}$'
            $ip = $parts | Where-Object { $_ -match $ipRegex } | Select-Object -First 1
            $hostnameParts = $parts | Where-Object { $_ -notmatch $ipRegex }
            $hostname = ($hostnameParts -join " ").Trim()
            if ($ip -and $hostname) {
                UpdateHostTemplateOnly -ip $ip -hostname $hostname
            } else {
                Write-Host "[ERROR] Línea inválida: $_" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "Archivo '$hostsFile' no encontrado." -ForegroundColor Red
}
