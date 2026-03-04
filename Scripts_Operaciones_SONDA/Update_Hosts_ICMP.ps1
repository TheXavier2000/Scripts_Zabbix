# === CONFIGURACIÓN ===
$zabbixUrl        = "http://10.161.115.127/zabbix/api_jsonrpc.php"
$authToken        = "c72cf6e672eb4c4800c004902e70f798"
$hostsFile        = "hosts_a_agregar.txt"
$groupId          = 28
$templateIcmpId   = 11550  # Cambiar por el template ICMP que desees

# === HEADERS ===
$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $authToken"
}

# === Función para buscar host por nombre o IP ===
function Get-HostByNameOrIp {
    param (
        [string]$hostname,
        [string]$ip
    )

    # 1. Buscar por nombre
    $bodyByName = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            output = "extend"
            selectInterfaces = "extend"
            selectGroups = "extend"
            selectParentTemplates = "extend"
            filter = @{ host = @($hostname) }
        }
        id = 1
    } | ConvertTo-Json -Depth 5

    $resp = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Headers $headers -Body $bodyByName
    if ($resp.result.Count -gt 0) {
        return $resp.result[0]
    }

    # 2. Buscar por IP
    $bodyByIp = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            output = "extend"
            selectInterfaces = "extend"
            selectGroups = "extend"
            selectParentTemplates = "extend"
            filter = @{ }
        }
        id = 2
    } | ConvertTo-Json -Depth 5

    $resp = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Headers $headers -Body $bodyByIp

    foreach ($zbxhost in $resp.result) {
        foreach ($iface in $zbxhost.interfaces) {
            if ($iface.useip -eq 1 -and $iface.ip -eq $ip) {
                return $zbxhost
            }
        }
    }

    return $null
}

# === Función para actualizar host ===
function UpdateHostIfNeeded {
    param (
        [string]$ip,
        [string]$hostname
    )

    Write-Host "→ Buscando host con nombre '$hostname' o IP '$ip'..."

    $zabbixHost = Get-HostByNameOrIp -hostname $hostname -ip $ip

    if (-not $zabbixHost) {
        Write-Host "[INFO] Host no encontrado en Zabbix: $hostname / $ip" -ForegroundColor Yellow
        return
    }

    $hostId = $zabbixHost.hostid
    $iface = $zabbixHost.interfaces | Where-Object { $_.useip -eq 1 } | Select-Object -First 1
    $needsUpdate = $false
    $updateParams = @{ hostid = $hostId }

    # Cambiar nombre si es distinto
    if ($zabbixHost.host -ne $hostname) {
        Write-Host "→ Cambio de nombre: '$($zabbixHost.host)' → '$hostname'" -ForegroundColor Cyan
        $updateParams.host = $hostname
        $needsUpdate = $true
    }

    # Cambiar IP o tipo de interfaz si es necesario
    if ($iface.ip -ne $ip -or $iface.type -ne 1) {
        Write-Host "→ Cambio de IP o tipo de interfaz: IP '$($iface.ip)' → '$ip'" -ForegroundColor Cyan
        $updateParams.interfaces = @(@{
            interfaceid = $iface.interfaceid
            type        = 1  # ICMP
            main        = 1
            useip       = 1
            ip          = $ip
            dns         = ""
            port        = ""
        })
        $needsUpdate = $true
    }

    # Verificar grupo
    $currGroups = $zabbixHost.groups | ForEach-Object { $_.groupid }
    if (-not ($currGroups -contains "$groupId")) {
        Write-Host "→ Grupo no coincide. Se actualizará al grupo ID $groupId." -ForegroundColor Cyan
        $updateParams.groups = @(@{ groupid = "$groupId" })
        $needsUpdate = $true
    }

    # Verificar plantilla
    $currTemplates = $zabbixHost.parentTemplates | ForEach-Object { $_.templateid }
    if (-not ($currTemplates -contains "$templateIcmpId")) {
        Write-Host "→ Template será reemplazado con ID $templateIcmpId" -ForegroundColor Cyan
        $updateParams.templates = @(@{ templateid = "$templateIcmpId" })
        $needsUpdate = $true
    }

    if ($needsUpdate) {
        $updateBody = @{
            jsonrpc = "2.0"
            method  = "host.update"
            params  = $updateParams
            id      = 3
        } | ConvertTo-Json -Depth 6

        $updateResp = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Headers $headers -Body $updateBody

        if ($updateResp.result.hostids) {
            Write-Host "[OK] Host '$hostname' actualizado con éxito." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Falló la actualización de '$hostname'." -ForegroundColor Red
        }
    } else {
        Write-Host "→ Host '$hostname' ya está actualizado." -ForegroundColor Gray
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
                UpdateHostIfNeeded -ip $ip -hostname $hostname
            } else {
                Write-Host "[ERROR] Línea inválida en el archivo: $_" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "Archivo '$hostsFile' no encontrado." -ForegroundColor Red
}
