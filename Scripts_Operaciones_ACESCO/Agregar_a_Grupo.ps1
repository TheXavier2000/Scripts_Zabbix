# ========== CONFIGURACIÓN ==========
$zabbixUrl = "http://10.1.0.66/zabbix/api_jsonrpc.php"
$authToken = "d7fdc470ab1b9dca77273be54c7d7030"
$hostsFile = "hosts_a_agregar.txt"
$newGroupId = 85
  # ID del nuevo grupof

# ========== VALIDAR EXISTENCIA DE GRUPO ==========
function Test-GroupExists {
    param ([int]$groupId)
    $body = @{
        jsonrpc = "2.0"
        method  = "hostgroup.get"
        params  = @{ groupids = @($groupId); output = "extend" }
        auth    = $authToken
        id      = 1
    } | ConvertTo-Json -Depth 4

    try {
        $response = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $body -ContentType "application/json"
        return ($response.result.Count -gt 0)
    } catch {
        return $false
    }
}

# ========== FUNCION PARA AGREGAR HOST A NUEVO GRUPO ==========
function Add-HostToNewGroup {
    param (
        [string]$hostId,
        [int]$newGroupId
    )

    # Primero obtenemos los grupos actuales del host
    $getGroupsBody = @{
        jsonrpc = "2.0"
        method = "host.get"
        params = @{
            output = "extend"
            selectGroups = "extend"
            hostids = @($hostId)
        }
        auth = $authToken
        id = 1
    } | ConvertTo-Json -Depth 5

    try {
        $getGroupsResponse = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $getGroupsBody -ContentType "application/json"

        if ($getGroupsResponse.result.Count -eq 0) {
            Write-Host "[ERROR] No se encontró host con ID $hostId" -ForegroundColor Red
            return
        }

        # Extraemos los groupids actuales
        $currentGroups = $getGroupsResponse.result[0].groups | ForEach-Object { $_.groupid }
        Write-Host "Grupos actuales del host: $($currentGroups -join ', ')" -ForegroundColor Yellow

        # Agregamos el nuevo grupo si no está presente
        if ($currentGroups -contains "$newGroupId") {
            Write-Host "El host ya pertenece al grupo $newGroupId" -ForegroundColor Cyan
            return
        }

        # Concatenamos los grupos actuales con el nuevo y eliminamos duplicados
        $allGroups = @($currentGroups) + $newGroupId | Sort-Object -Unique

        
        # Construimos un array de objetos para JSON correctamente
        $groupsArray = @()
        foreach ($group in $allGroups) {
            $groupsArray += @{ groupid = "$group" }
        }

        Write-Host "Grupos a enviar:" -ForegroundColor Cyan
        $groupsArray | ForEach-Object { Write-Host $_.groupid }

        # Preparamos el cuerpo para host.update
        $updateBody = @{
            jsonrpc = "2.0"
            method = "host.update"
            params = @{
                hostid = $hostId
                groups = $groupsArray
            }
            auth = $authToken
            id = 2
        } | ConvertTo-Json -Depth 10

        Write-Host "JSON para actualizar host:" -ForegroundColor DarkYellow
        Write-Host $updateBody

        try {
            $updateResponse = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $updateBody -ContentType "application/json"

            Write-Host "Respuesta del servidor:" -ForegroundColor Yellow
            $updateResponse | ConvertTo-Json -Depth 10 | Write-Host

            if ($updateResponse.result -and $updateResponse.result.hostids) {
                Write-Host "[OK] Host actualizado con el nuevo grupo $newGroupId." -ForegroundColor Green
            } else {
                Write-Host "[ERROR] No se pudo actualizar el host." -ForegroundColor Red
            }
        } catch {
            Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
            if ($_.Exception.Response) {
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $responseBody = $reader.ReadToEnd()

                    Write-Host "Respuesta cruda del servidor: $responseBody" -ForegroundColor Red

                    $errorJson = $null
                    try {
                        $errorJson = $responseBody | ConvertFrom-Json
                    } catch {
                        Write-Host "Respuesta del servidor (no JSON): $responseBody" -ForegroundColor Red
                    }

                    if ($errorJson -and $errorJson.error) {
                        Write-Host "Código de error: $($errorJson.error.code)" -ForegroundColor Red
                        Write-Host "Mensaje: $($errorJson.error.message)" -ForegroundColor Red
                        Write-Host "Datos: $($errorJson.error.data)" -ForegroundColor Red
                    }
                } catch {
                    Write-Host "[ERROR] No se pudo leer la respuesta del servidor." -ForegroundColor Red
                }
            }
        }

    } catch {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ========== FUNCIÓN PARA OBTENER HOSTID Y AGREGAR NUEVO GRUPO ==========
function Add-HostByNameOrIP {
    param (
        [string]$ip,
        [string]$hostname
    )

    Write-Host "→ Procesando host '$hostname' con IP $ip..."

    # Primero buscamos host por nombre
    $bodyByName = @{
        jsonrpc = "2.0"
        method = "host.get"
        params = @{
            output = "extend"
            selectGroups = "extend"
            filter = @{ host = @($hostname) }
        }
        auth = $authToken
        id = 2
    } | ConvertTo-Json -Depth 5

    $response = $null
    try {
        $response = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $bodyByName -ContentType "application/json"
    } catch {}

    # Si no hay resultado, buscamos por IP
    if (-not $response -or $response.result.Count -eq 0) {
        $bodyByIP = @{
            jsonrpc = "2.0"
            method = "host.get"
            params = @{
                output = "extend"
                selectGroups = "extend"
                filter = @{ ip = @($ip) }
            }
            auth = $authToken
            id = 3
        } | ConvertTo-Json -Depth 5

        try {
            $response = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $bodyByIP -ContentType "application/json"
        } catch {}
    }

    if (-not $response -or $response.result.Count -eq 0) {
        Write-Host "[AVISO] No se encontró el host '$hostname' ni por IP '$ip'." -ForegroundColor Yellow
        return
    }

    $hostId = $response.result[0].hostid
    Add-HostToNewGroup -hostId $hostId -newGroupId $newGroupId
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
                Add-HostByNameOrIP -ip $ip -hostname $hostname
            } else {
                Write-Host "[ERROR] Línea inválida: $_" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "[ERROR] Archivo '$hostsFile' no encontrado." -ForegroundColor Red
}
