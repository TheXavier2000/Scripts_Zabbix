# ========== CONFIGURACIÓN ==========
$zabbixUrl = "http://10.161.115.127/zabbix/api_jsonrpc.php"
$authToken = "4b8ffbdb5bdbbfde79c9fd78a54109c0"
$hostsFile = "hosts_a_agregar.txt"
$newGroupId = 67  # ID del nuevo grupo a agregar

# ========== HEADERS ==========
$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $authToken"
}

# ========== OBTENER HOSTID POR IP ==========
function Get-HostIdByIP {
    param ([string]$ip)

    $body = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            output = @("hostid", "host")
            filter = @{ ip = @($ip) }
        }
        id = 1
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Headers $headers -Body $body
        if ($response.result.Count -gt 0) {
            return $response.result[0].hostid
        }
    } catch {
        Write-Host "[ERROR] Al obtener hostid por IP $ip : $($_.Exception.Message)" -ForegroundColor Red
    }
    return $null
}

# ========== OBTENER GRUPOS ACTUALES DEL HOST ==========
function Get-CurrentGroupsByHostId {
    param ([string]$hostId)

    $body = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            hostids          = @($hostId)
            output           = @("hostid", "host", "name")
            selectHostGroups = "extend"
        }
        id = 2
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Headers $headers -Body $body

        if ($response.result.Count -gt 0 -and $response.result[0].hostgroups) {
            $groups = $response.result[0].hostgroups | ForEach-Object {
                [int]$_.groupid
            }
            return $groups
        } else {
            Write-Host "[AVISO] No se encontraron grupos válidos para host $hostId." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[ERROR] Al obtener grupos actuales para hostid $hostId : $($_.Exception.Message)" -ForegroundColor Red
    }
    return @()
}

# ========== AGREGAR NUEVO GRUPO SIN ELIMINAR LOS EXISTENTES ==========
function Add-HostToNewGroup {
    param (
        [string]$hostId,
        [int[]]$currentGroups
    )

    if ($currentGroups -contains $newGroupId) {
        Write-Host "El host $hostId ya pertenece al grupo $newGroupId" -ForegroundColor Cyan
        return
    }

    $updatedGroups = $currentGroups + $newGroupId | Sort-Object -Unique
    $groupsArray = @()
    foreach ($group in $updatedGroups) {
        $groupsArray += @{ groupid = $group }
    }

    Write-Host "Grupos a enviar para host $hostId :" -ForegroundColor Cyan
    $groupsArray | ForEach-Object { Write-Host $_.groupid }

    $updateBody = @{
        jsonrpc = "2.0"
        method  = "host.update"
        params  = @{
            hostid = $hostId
            groups = $groupsArray
        }
        id = 4
    } | ConvertTo-Json -Depth 10

    Write-Host "JSON para actualizar host :" -ForegroundColor DarkYellow
    Write-Host $updateBody

    try {
        $updateResponse = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Headers $headers -Body $updateBody
        if ($updateResponse.result -and $updateResponse.result.hostids) {
            Write-Host "[OK] Host actualizado con el nuevo grupo $newGroupId." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] No se pudo actualizar el host." -ForegroundColor Red
        }
    } catch {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ========== NUEVA: FUNCIÓN PARA PROCESAR IP Y HOSTNAME ==========
function Add-HostToNewGroupByIP {
    param (
        [string]$ip,
        [string]$hostname
    )

    Write-Host "`nProcesando host: $hostname (IP: $ip)" -ForegroundColor Cyan

    $hostId = Get-HostIdByIP -ip $ip
    if (-not $hostId) {
        Write-Host "[ERROR] No se pudo obtener el hostid para $hostname ($ip)" -ForegroundColor Red
        return
    }

    $currentGroups = Get-CurrentGroupsByHostId -hostId $hostId
    if (-not $currentGroups) {
        Write-Host "[ERROR] No se pudieron obtener los grupos actuales para el host $hostId" -ForegroundColor Red
        return
    }

    Add-HostToNewGroup -hostId $hostId -currentGroups $currentGroups
}

# ========== PROCESAR ARCHIVO ==========
if (Test-Path $hostsFile) {
    $ipRegex = '^(?:\d{1,3}\.){3}\d{1,3}$'

    Get-Content $hostsFile | ForEach-Object {
        if ($_ -match "\S") {
            $parts = ($_ -split "[\t ]+") | ForEach-Object { $_.Trim() }
            $ip = $parts | Where-Object { $_ -match $ipRegex } | Select-Object -First 1
            $hostnameParts = $parts | Where-Object { $_ -notmatch $ipRegex }
            $hostname = ($hostnameParts -join "_").Trim()

            if ($ip -and $hostname) {
                Add-HostToNewGroupByIP -ip $ip -hostname $hostname
            } else {
                Write-Host "[ERROR] Línea inválida : $_" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "[ERROR] Archivo '$hostsFile' no encontrado." -ForegroundColor Red
}
