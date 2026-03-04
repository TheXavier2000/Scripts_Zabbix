# ========== CONFIGURACIÓN ==========
$zabbixUrl = "http://10.1.0.66/zabbix/api_jsonrpc.php"
$authToken = "d34eef98f6d9445329497e003e7c59a2"
$groupId = 45  # ID del hostgroup a revisar

# ========== FUNCIONES ==========

function Get-HostsInGroup {
    param ([int]$groupId)

    $body = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            output = "extend"
            groupids = @($groupId)
            selectInterfaces = "extend"
        }
        auth = $authToken
        id    = 1
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $body -ContentType "application/json"
        return $response.result
    } catch {
        Write-Host "[ERROR] No se pudo obtener hosts del grupo $groupId" -ForegroundColor Red
        return @()
    }
}

function Test-Duplicates {
    param (
        [array]$hosts
    )

    $nameMap = @{}
    $ipMap = @{}

    foreach ($zbxhost in $hosts) {
        $name = $zbxhost.host
        $hostid = $zbxhost.hostid

        # Usamos el primer valor IP válido
        foreach ($iface in $zbxhost.interfaces) {
            $ip = $iface.ip
            if ($ip -and $ip -ne "127.0.0.1") {
                # Mapear IP
                if (-not $ipMap.ContainsKey($ip)) {
                    $ipMap[$ip] = @()
                }
                $ipMap[$ip] += [PSCustomObject]@{
                    HostID = $hostid
                    Host   = $name
                    IP     = $ip
                }
            }
        }

        # Mapear nombre
        if (-not $nameMap.ContainsKey($name)) {
            $nameMap[$name] = @()
        }

        foreach ($iface in $zbxhost.interfaces) {
            $ip = $iface.ip
            if ($ip -and $ip -ne "127.0.0.1") {
                $nameMap[$name] += [PSCustomObject]@{
                    HostID = $hostid
                    Host   = $name
                    IP     = $ip
                }
                break
            }
        }
    }

    return @{
        DuplicateNames = $nameMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        DuplicateIPs   = $ipMap.GetEnumerator()  | Where-Object { $_.Value.Count -gt 1 }
    }
}

# ========== EJECUCIÓN PRINCIPAL ==========

Write-Host "Obteniendo hosts del grupo con ID $groupId..." -ForegroundColor Cyan
$hosts = Get-HostsInGroup -groupId $groupId

if ($hosts.Count -eq 0) {
    Write-Host "[INFO] No se encontraron hosts en el grupo $groupId" -ForegroundColor Yellow
    return
}

Write-Host "Analizando duplicados..." -ForegroundColor Cyan
$duplicates = Test-Duplicates -hosts $hosts

# Mostrar nombres duplicados
if ($duplicates.DuplicateNames.Count -gt 0) {
    Write-Host "`n=== NOMBRES DE HOST DUPLICADOS ===" -ForegroundColor Red
    foreach ($entry in $duplicates.DuplicateNames) {
        Write-Host "`nNombre duplicado: $($entry.Key)" -ForegroundColor Magenta
        foreach ($hostInfo in $entry.Value) {
            Write-Host " → HostID: $($hostInfo.HostID) | Host: $($hostInfo.Host) | IP: $($hostInfo.IP)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "`nNo se encontraron nombres de host duplicados." -ForegroundColor Green
}

# Mostrar IPs duplicadas
if ($duplicates.DuplicateIPs.Count -gt 0) {
    Write-Host "`n=== IPs DUPLICADAS ===" -ForegroundColor Red
    foreach ($entry in $duplicates.DuplicateIPs) {
        Write-Host "`nIP duplicada: $($entry.Key)" -ForegroundColor Magenta
        foreach ($hostInfo in $entry.Value) {
            Write-Host " → HostID: $($hostInfo.HostID) | Host: $($hostInfo.Host) | IP: $($hostInfo.IP)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "`nNo se encontraron IPs duplicadas." -ForegroundColor Green
}
