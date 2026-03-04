# === CONFIGURACIÓN ===
$zabbixUrl = "http://10.1.0.66/zabbix/api_jsonrpc.php"
$authToken = "d34eef98f6d9445329497e003e7c59a2"
$hostsFile       = "hosts_a_agregar.txt"
$groupId         = 135
$templateSnmpId  = 10218
$communityString = "Acesco-RO"

# === Función para asegurar nombre único agregando sufijo si ya existe ===
function Get-UniqueHostname {
    param (
        [string]$baseName
    )
    $index = 2
    $name = $baseName
    do {
        # Buscar en Zabbix host con ese nombre exacto
        $body = @{
            jsonrpc = "2.0"
            method  = "host.get"
            params  = @{ filter = @{ host = @($name) }; output = @("hostid") }
            auth    = $authToken
            id      = 99
        } | ConvertTo-Json -Depth 3
        $resp = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $body -ContentType "application/json"
        if ($resp.result.Count -gt 0) {
            $name = "$baseName-$index"
            $index++
        } else {
            return $name
        }
    } while ($true)
}

# === Función para crear host SNMP ===
function CreateHost {
    param ([string]$ip, [string]$hostname)
    Write-Host "→ Creando host '$hostname' con IP $ip..."
    $interfaces = @(@{
        type    = 2
        main    = 1
        useip   = 1
        ip      = $ip
        dns     = ""
        port    = "161"
        details = @{ version = 2; community = $communityString }
    })
    $createBody = @{
        jsonrpc = "2.0"
        method  = "host.create"
        params  = @{
            host       = $hostname
            interfaces = $interfaces
            groups     = @(@{ groupid = $groupId })
            templates  = @(@{ templateid = $templateSnmpId })
        }
        auth = $authToken; id = 1
    } | ConvertTo-Json -Depth 6
    $res = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $createBody -ContentType "application/json"
    if ($res.result.hostids) {
        Write-Host "[OK] Host '$hostname' creado (ID: $($res.result.hostids[0]))" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] No se pudo crear '$hostname'." -ForegroundColor Red
        if ($res.error) { Write-Host "  → $($res.error.data)" -ForegroundColor Red }
    }
}

# === Función para actualizar o reprovisionar ===
function AddOrReprovisionHost {
    param ([string]$ip, [string]$hostname)
    Write-Host "→ Procesando host base '$hostname' con IP $ip..."

    # Asegurar hostname único
    $uniqueName = Get-UniqueHostname -baseName $hostname

    # Buscar por IP o nombre
    $getBody = @{
        jsonrpc = "2.0"; method = "host.get"
        params = @{
            output              = "extend"
            selectInterfaces    = "extend"
            selectGroups        = "extend"
            selectParentTemplates = "extend"
            filter = @{ host = @($uniqueName) }
        }
        auth = $authToken; id = 2
    } | ConvertTo-Json -Depth 6
    $resp = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $getBody -ContentType "application/json"

    if ($resp.result.Count -gt 0) {
        # Existe: verificar actualización
        $h = $resp.result[0]
        $hostId = $h.hostid
        $iface = $h.interfaces | Where-Object { $_.useip -eq 1 } | Select-Object -First 1
        $needsUpdate = $false
        $upd = @{ hostid = $hostId }

        if ($h.host -ne $uniqueName) {
            $upd.host = $uniqueName; $needsUpdate = $true
        }
        if ($iface.ip -ne $ip -or $iface.type -ne 2 -or $iface.details.community -ne $communityString) {
            $upd.interfaces = @(@{
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
        $currGroups = $h.groups | ForEach-Object { $_.groupid }
        if (-not ($currGroups -contains "$groupId")) {
            $upd.groups = @(@{ groupid = $groupId }); $needsUpdate = $true
        }
        $currTemp = $h.parentTemplates | ForEach-Object { $_.templateid }
        if (-not ($currTemp -contains "$templateSnmpId")) {
            $upd.templates = @(@{ templateid = $templateSnmpId }); $needsUpdate = $true
        }

        if ($needsUpdate) {
            Write-Host "→ Actualizando host '$uniqueName' (ID $hostId)..."
            $updateBody = @{ jsonrpc = "2.0"; method = "host.update"; params = $upd; auth = $authToken; id = 3 }
            $ur = $updateBody | ConvertTo-Json -Depth 6
            $urRes = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $ur -ContentType "application/json"
            if ($urRes.result.hostids) {
                Write-Host "[OK] Host '$uniqueName' actualizado." -ForegroundColor Green
            } else {
                Write-Host "[ERROR] No se pudo actualizar '$uniqueName'." -ForegroundColor Red
            }
        } else {
            Write-Host "→ Host '$uniqueName' ya completamente actualizado." -ForegroundColor Yellow
        }
    } else {
        # No existe: crear nuevo
        CreateHost -ip $ip -hostname $uniqueName
    }
}

# === Procesar archivo ===
if (Test-Path $hostsFile) {
    Get-Content $hostsFile | ForEach-Object {
        if ($_ -match "\S") {
            $parts = ($_ -split "\s+") | ForEach-Object { $_.Trim() }
            $ipRegex = '^(?:\d{1,3}\.){3}\d{1,3}$'
            $ip = $parts | Where-Object { $_ -match $ipRegex } | Select-Object -First 1
            $nameParts = $parts | Where-Object { $_ -notmatch $ipRegex }
            $hostname = ($nameParts -join " ").Trim()
            if ($ip -and $hostname) {
                AddOrReprovisionHost -ip $ip -hostname $hostname
            } else {
                Write-Host "[ERROR] Línea inválida: $_" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "Archivo '$hostsFile' no encontrado." -ForegroundColor Red
}
