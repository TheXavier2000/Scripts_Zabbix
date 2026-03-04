# === CONFIGURACIÓN ===
$zabbixUrl        = "http://10.161.115.127/zabbix/api_jsonrpc.php"
$authToken        = "4b8ffbdb5bdbbfde79c9fd78a54109c0"
$hostsFile        = "hosts_a_agregar.txt"
$groupId          = 24
$templateSnmpId   = 10769
$communityString  = "Or10nS0c"

# === HEADERS ===s
$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $authToken"
}

# === Función para actualizar hosts existentes ===
function UpdateExistingHost {
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
            output               = "extend"
            selectInterfaces     = "extend"
            selectGroups         = "extend"
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

    # Host encontrado, se verifica y actualiza
    $zabbixHost = $resp.result[0]
    $hostId     = $zabbixHost.hostid
    $iface      = $zabbixHost.interfaces | Where-Object { $_.useip -eq 1 } | Select-Object -First 1
    $needsUpdate = $false
    $updateParams = @{ hostid = $hostId }

    # Actualizar interfaz si es necesario
    if ($iface.ip -ne $ip -or $iface.type -ne 2 -or $iface.details.community -ne $communityString) {
        $updateParams.interfaces = @(@{
            interfaceid = $iface.interfaceid
            type        = 2
            main        = 1
            useip       = 1
            ip          = $ip
            dns         = ""
            port        = "161"
            details     = @{ version = 2; community = $communityString }
        })
        $needsUpdate = $true
    }

    # Asegurar que esté en el grupo deseado
    $currGroups = $zabbixHost.groups | ForEach-Object { $_.groupid }
    if (-not ($currGroups -contains "$groupId")) {
        $updateParams.groups = @(@{ groupid = "$groupId" })
        $needsUpdate = $true
    }

    # Reemplazar TODOS los templates por el nuevo
    $updateParams.templates = @(@{ templateid = "$templateSnmpId" })
    $needsUpdate = $true  # Forzamos actualización por cambio de template

    if ($needsUpdate) {
        Write-Host "→ Actualizando host '$hostname' (ID $hostId)..."
        $updateBody = @{
            jsonrpc = "2.0"
            method  = "host.update"
            params  = $updateParams
            id      = 2
        } | ConvertTo-Json -Depth 6

        $updateResponse = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Headers $headers -Body $updateBody

        if ($updateResponse.result.hostids) {
            Write-Host "[OK] Host '$hostname' actualizado correctamente." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] No se pudo actualizar el host '$hostname'." -ForegroundColor Red
        }
    } else {
        Write-Host "→ Host '$hostname' ya está actualizado." -ForegroundColor Cyan
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
                UpdateExistingHost -ip $ip -hostname $hostname
            } else {
                Write-Host "[ERROR] Línea inválida: $_" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "Archivo '$hostsFile' no encontrado." -ForegroundColor Red
}
