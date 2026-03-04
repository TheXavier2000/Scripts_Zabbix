# ========== CONFIGURACIÓN ==========
$zabbixUrl = "http://10.161.115.127/zabbix/api_jsonrpc.php"
$authToken = "4b8ffbdb5bdbbfde79c9fd78a54109c0"
$hostsFile = "hosts_a_agregar.txt"
$groupId = 68
$templateId = 10766

# ========== FUNCIÓN PARA AGREGAR HOST ==========
function Add-OrUpdate-ZabbixHost {
    param (
        [string]$ip,
        [string]$hostname
    )

    Write-Host "→ Procesando host '$hostname' con IP $ip..."

    $headers = @{
        "Content-Type"  = "application/json"
        "Authorization" = "Bearer $authToken"
    }

    # Primero buscamos si el host ya existe por nombre o IP
    $getBody = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            output = "extend"
            selectInterfaces = "extend"
            selectGroups = "extend"
            selectParentTemplates = "extend"
            filter = @{
                host = @($hostname)
            }
        }
        id = 1
    } | ConvertTo-Json -Depth 5

    try {
        $getResponse = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $getBody -Headers $headers

        if ($getResponse.result.Count -gt 0) {
            # Ya existe, actualizamos si es necesario
            $existingHost = $getResponse.result[0]
            $hostId = $existingHost.hostid
            $currentInterface = $existingHost.interfaces[0]
            $currentIp = $currentInterface.ip
            $currentType = $currentInterface.type
            $currentGroupIds = $existingHost.groups | ForEach-Object { $_.groupid }
            $currentTemplates = $existingHost.parentTemplates | ForEach-Object { $_.templateid }

            Write-Host "→ Templates actuales: $($currentTemplates -join ', ')" -ForegroundColor Cyan

            $needsUpdate = $false
            $updateParams = @{ hostid = $hostId }

            if ($existingHost.host -ne $hostname) {
                $updateParams.host = $hostname
                $needsUpdate = $true
            }

            if ($currentIp -ne $ip -or $currentType -ne 3) {
                $updateParams.interfaces = @(@{
                    interfaceid = $currentInterface.interfaceid
                    type = 1
                    main = 1
                    useip = 1
                    ip = $ip
                    dns = ""
                    port = "10050"
                })
                $needsUpdate = $true
            }

            if (-not ($currentGroupIds -contains "$groupId")) {
                $updateParams.groups = @(@{ groupid = "$groupId" })
                $needsUpdate = $true
            }

            # Reemplazar todos los templates actuales por el nuevo
            $updateParams.templates = @(@{ templateid = "$templateId" })
            $needsUpdate = $true

            if ($needsUpdate) {
                $updateBody = @{
                    jsonrpc = "2.0"
                    method = "host.update"
                    params = $updateParams
                    id = 2
                } | ConvertTo-Json -Depth 6

                $updateResponse = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $updateBody -Headers $headers
                if ($updateResponse.result.hostids) {
                    Write-Host "[OK] Host '$hostname' actualizado correctamente." -ForegroundColor Green
                } else {
                    Write-Host "[ERROR] No se pudo actualizar el host '$hostname'." -ForegroundColor Red
                }
            } else {
                Write-Host "→ Host '$hostname' ya está actualizado." -ForegroundColor Yellow
            }

        } else {
            # No existe, se crea
            Write-Host "→ Host '$hostname' no existe. Creándolo..."

            $createBody = @{
                jsonrpc = "2.0"
                method  = "host.create"
                params  = @{
                    host = $hostname
                    interfaces = @(@{
                        type = 1
                        main = 1
                        useip = 1
                        ip = $ip
                        dns = ""
                        port = "10050"
                    })
                    groups = @(@{ groupid = "$groupId" })
                    templates = @(@{ templateid = "$templateId" })
                }
                id = 3
            } | ConvertTo-Json -Depth 5

            $createResponse = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $createBody -Headers $headers
            if ($createResponse.result.hostids) {
                Write-Host "[OK] Host '$hostname' agregado exitosamente." -ForegroundColor Green
            } else {
                Write-Host "[ERROR] No se pudo agregar el host '$hostname'." -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "[ERROR] Error procesando '$hostname': $_" -ForegroundColor Red
    }
}

# ========== PROCESAR ARCHIVO ==========
if (Test-Path $hostsFile) {
    Get-Content $hostsFile | ForEach-Object {
        if ($_ -match "\S") {
            $parts = ($_ -split "\s{1,}") | ForEach-Object { $_.Trim() }

            $ipRegex = '^(?:\d{1,3}\.){3}\d{1,3}$'
            $ip = $parts | Where-Object { $_ -match $ipRegex } | Select-Object -First 1
            $hostnameParts = $parts | Where-Object { $_ -notmatch $ipRegex }
            $hostname = ($hostnameParts -join " ").Trim()

            if ($ip -and $hostname) {
                Add-OrUpdate-ZabbixHost -ip $ip -hostname $hostname
            } else {
                Write-Host "[ERROR] Línea inválida (no se detectó IP y hostname): $_" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "Archivo '$hostsFile' no encontrado." -ForegroundColor Red
}
