# === CONFIGURACIÓN ===
$zabbixUrl  = "http://10.1.0.66/zabbix/api_jsonrpc.php"
$authToken  = "a908c986c0bd640289f76acb933e6385"
$outputFile = "Informe_Zabbix.xlsx"

Import-Module ImportExcel -ErrorAction Stop

function Invoke-Zabbix {
    param($body)
    $json = $body | ConvertTo-Json -Depth 12 -Compress
    try {
        return Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $json -ContentType "application/json"
    } catch {
        Write-Host "ERROR en la API: $($_.Exception.Message)"
        return $null
    }
}

function Convert-ToTimestamp($dateString) {
    return [int][double]::Parse((Get-Date $dateString -UFormat %s))
}

function Format-Duration {
    param([TimeSpan]$span)
    if ($span.TotalSeconds -lt 60) {
        return ("{0:N0} seg" -f $span.TotalSeconds)
    } elseif ($span.TotalMinutes -lt 60) {
        return ("{0:N0} min, {1:N0} seg" -f $span.Minutes, $span.Seconds)
    } elseif ($span.TotalHours -lt 24) {
        return ("{0:N0} h, {1:N0} min" -f $span.Hours, $span.Minutes)
    } elseif ($span.TotalDays -lt 30) {
        return ("{0:N0} d, {1:N0} h" -f $span.Days, $span.Hours)
    } else {
        $months = [math]::Floor($span.TotalDays / 30)
        $days = $span.Days % 30
        return ("{0} mes(es), {1} d" -f $months, $days)
    }
}

# === Mostrar grupos disponibles ===
$groupRes = Invoke-Zabbix @{
    jsonrpc = "2.0"
    method  = "hostgroup.get"
    params  = @{ output = "extend" }
    auth    = $authToken
    id      = 1
}

if (-not $groupRes.result) {
    Write-Host "No se encontraron grupos."
    exit
}

Write-Host "`n================ LISTA DE GRUPOS DISPONIBLES ================"
Write-Host "| GroupID | Nombre                                        |"
Write-Host "------------------------------------------------------------"
foreach ($g in $groupRes.result) {
    Write-Host ("| {0,-7} | {1,-44} |" -f $g.groupid, $g.name)
}
Write-Host "============================================================"

# === Selección de grupos ===
$selectedIds = Read-Host "Ingrese los IDs de los grupos separados por coma"
$groupIds = $selectedIds -split "," | ForEach-Object { $_.Trim() }

# === Tipo de informe ===
Write-Host "`n================== OPCIONES DE INFORME =================="
Write-Host "| [1] Informe de Disponibilidad                           |"
Write-Host "| [0] Informe de Problemas                                |"
Write-Host "=========================================================="
$tipoInput = Read-Host "Seleccione tipo de informe (1 = Disponibilidad, 0 = Problemas)"
$tipoInforme = if ($tipoInput -eq "1") { "disponibilidad" } else { "problemas" }

# === Rango de fechas ===
$fechaInicio = Read-Host "Ingrese la fecha inicial (YYYY-MM-DD HH:MM:SS)"
if (-not $fechaInicio) { $fechaInicio = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd 00:00:00") }
$fechaFin = Read-Host "Ingrese la fecha final (YYYY-MM-DD HH:MM:SS)"
if (-not $fechaFin) { $fechaFin = (Get-Date).ToString("yyyy-MM-dd 23:59:59") }

$timeFrom = Convert-ToTimestamp $fechaInicio
$timeTill = Convert-ToTimestamp $fechaFin

# Eliminar archivo existente
if (Test-Path $outputFile) { Remove-Item $outputFile }

$resumenProblemas = @()
$detalleProblemas = @()

# === Calcular total de hosts para progreso global ===
$totalHosts = 0
foreach ($groupId in $groupIds) {
    $hostsRes = Invoke-Zabbix @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            output = @("hostid")
            groupids = $groupId
        }
        auth = $authToken
        id   = 99
    }
    $totalHosts += $hostsRes.result.Count
}
$globalIndex = 0

foreach ($groupId in $groupIds) {
    $groupName = ($groupRes.result | Where-Object { $_.groupid -eq $groupId }).name
    if (-not $groupName) {
        Write-Host "AVISO: Grupo con ID $groupId no encontrado, se omite."
        continue
    }

    Write-Host "`nProcesando grupo: $groupName (ID: $groupId)"

    # === Obtener hosts del grupo ===
    $hostsRes = Invoke-Zabbix @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            output = @("hostid","host","name")
            selectInterfaces = @("ip")
            selectGroups     = @("name")
            groupids         = $groupId
        }
        auth = $authToken
        id   = 2
    }

    $hosts = $hostsRes.result
    if (-not $hosts) {
        Write-Host "AVISO: No se encontraron hosts en el grupo $groupName"
        continue
    }

    $reportData = @()

    if ($tipoInforme -eq "disponibilidad") {
        # === Disponibilidad ===
        $allHostIds = $hosts.hostid
        $itemRes = Invoke-Zabbix @{
            jsonrpc = "2.0"
            method  = "item.get"
            params  = @{
                output = @("itemid","hostid","key_")
                hostids = $allHostIds
                filter  = @{ key_ = "icmpping" }
            }
            auth = $authToken
            id   = 3
        }

        $itemsByHost = @{}
        foreach ($item in $itemRes.result) {
            $itemsByHost[$item.hostid] = $item.itemid
        }

        $historyRes = Invoke-Zabbix @{
            jsonrpc = "2.0"
            method  = "history.get"
            params  = @{
                output   = "extend"
                history  = 3
                itemids  = $itemsByHost.Values
                sortfield = "clock"
                sortorder = "DESC"
                limit    = 1
            }
            auth = $authToken
            id   = 4
        }

        $statusByItem = @{}
        foreach ($h in $historyRes.result) {
            $statusByItem[$h.itemid] = $h.value
        }

        foreach ($zbxHost in $hosts) {
            $globalIndex++
            Write-Progress -Activity "Analizando hosts" `
                           -Status ("Grupo: {0} | Equipo {1}/{2} ({3})" -f $groupName, $globalIndex, $totalHosts, $zbxHost.name) `
                           -PercentComplete ([int](($globalIndex / $totalHosts) * 100))

            $ip = if ($zbxHost.interfaces) { '="' + $zbxHost.interfaces[0].ip + '"' } else { "" }
            $itemid = $itemsByHost[$zbxHost.hostid]
            $status = if ($statusByItem[$itemid] -eq "1") { "Disponible" } else { "No disponible" }

            $reportData += [PSCustomObject]@{
                Nombre         = $zbxHost.name
                IP             = $ip
                Grupo          = ($zbxHost.groups | ForEach-Object { $_.name }) -join " | "
                Disponibilidad = $status
            }
        }
    }
    elseif ($tipoInforme -eq "problemas") {
        # === Problemas ===
        $hostIds = $hosts.hostid
        $eventRes = Invoke-Zabbix @{
            jsonrpc = "2.0"
            method  = "event.get"
            params  = @{
                output = "extend"
                selectHosts = "extend"
                selectRelatedObject = "extend"
                time_from = $timeFrom
                time_till = $timeTill
                hostids = $hostIds
                value = 1
                sortfield = "clock"
                sortorder = "DESC"
                limit = 10000
            }
            auth = $authToken
            id = 5
        }

        if ($eventRes.result.Count -gt 0) {
            $triggerIds = ($eventRes.result | Select-Object -ExpandProperty objectid | Sort-Object -Unique)
            $triggerRes = Invoke-Zabbix @{
                jsonrpc = "2.0"
                method  = "trigger.get"
                params  = @{
                    output     = @("triggerid","description","value","lastchange")
                    triggerids = $triggerIds
                }
                auth = $authToken
                id = 6
            }

            $triggerMap = @{}
            foreach ($t in $triggerRes.result) {
                $triggerMap[$t.triggerid] = $t
            }

            foreach ($zbxHost in $hosts) {
                $globalIndex++
                Write-Progress -Activity "Analizando hosts" `
                               -Status ("Grupo: {0} | Equipo {1}/{2} ({3})" -f $groupName, $globalIndex, $totalHosts, $zbxHost.name) `
                               -PercentComplete ([int](($globalIndex / $totalHosts) * 100))

                $hostEvents = $eventRes.result | Where-Object { $_.hosts[0].hostid -eq $zbxHost.hostid }
                $countProblemas = 0
                foreach ($ev in $hostEvents) {
                    $countProblemas++
                    $start = (Get-Date ([System.DateTimeOffset]::FromUnixTimeSeconds([int]$ev.clock)).LocalDateTime)
                    $trigger = $triggerMap[$ev.objectid]
                    if ($trigger.value -eq "0") {
                        $resolved = (Get-Date ([System.DateTimeOffset]::FromUnixTimeSeconds([int]$trigger.lastchange)).LocalDateTime)
                        $duracion = Format-Duration (New-TimeSpan -Start $start -End $resolved)
                        $estado = "Resuelto"
                    } else {
                        $resolved = "Activo"
                        $duracion = Format-Duration (New-TimeSpan -Start $start -End (Get-Date))
                        $estado = "Activo"
                    }

                    $detalleProblemas += [PSCustomObject]@{
                        Host     = $zbxHost.name
                        Problema = $ev.name
                    }

                    $reportData += [PSCustomObject]@{
                        Host     = $zbxHost.name
                        IP       = '="' + $zbxHost.interfaces[0].ip + '"'
                        Grupo    = ($zbxHost.groups | ForEach-Object { $_.name }) -join " | "
                        Problema = $ev.name
                        Inicio   = $start
                        Estado   = $estado
                        Resuelto = $resolved
                        Duracion = $duracion
                    }
                }
                $resumenProblemas += [PSCustomObject]@{
                    Host     = $zbxHost.name
                    IP       = '="' + $zbxHost.interfaces[0].ip + '"'
                    Grupo    = ($zbxHost.groups | ForEach-Object { $_.name }) -join " | "
                    Cantidad = $countProblemas
                }
            }
        }
    }

    if ($reportData.Count -gt 0) {
    $reportData | Sort-Object -Property Inicio -Descending | Export-Excel -Path $outputFile -WorksheetName $groupName `
        -AutoSize -BoldTopRow -FreezeTopRow `
        -TableName ("Tabla_{0}" -f $groupName.Replace(" ", "_")) `
        -TableStyle Medium6 -Append
}

}

# === RESUMEN Y TOP 10 ===
if ($tipoInforme -eq "problemas" -and $resumenProblemas.Count -gt 0) {
    # Guardar resumen original
    $resumenProblemas | Export-Excel -Path $outputFile -WorksheetName "Resumen_Problemas" `
        -AutoSize -BoldTopRow -FreezeTopRow `
        -TableName "ResumenProblemas" `
        -TableStyle Medium2 -Append

    # Top 10 equipos más alertados
    $topHosts = $resumenProblemas | Sort-Object -Property Cantidad -Descending | Select-Object -First 10

    # Problemas más recurrentes
    $topProblemas = $detalleProblemas | Group-Object Problema | Sort-Object Count -Descending | Select-Object Name, Count

    # Exportar ambos en la misma hoja
    $wsParams = @{
        Path          = $outputFile
        WorksheetName = "Top_Alertas"
        AutoSize      = $true
        BoldTopRow    = $true
        FreezeTopRow  = $true
        TableStyle    = "Medium9"
    }
    $topHosts | Export-Excel @wsParams -StartRow 1 -StartColumn 1 -Title "Top 10 Equipos m$([char]0x00E1)s Alertados"
    $topProblemas | Export-Excel @wsParams -StartRow 1 -StartColumn 6 -Title "Problemas m$([char]0x00E1)s Recurrentes"

}

Write-Host "`nArchivo generado: $outputFile"
