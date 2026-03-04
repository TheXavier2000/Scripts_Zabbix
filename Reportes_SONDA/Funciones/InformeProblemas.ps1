function Format-Duration {
    param([TimeSpan]$duration)

    $parts = @()
    if ($duration.Days -gt 0)    { $parts += "$($duration.Days)d" }
    if ($duration.Hours -gt 0)   { $parts += "$($duration.Hours)h" }
    if ($duration.Minutes -gt 0) { $parts += "$($duration.Minutes)m" }
    if ($duration.Seconds -gt 0) { $parts += "$($duration.Seconds)s" }

    if ($parts.Count -eq 0) { return "0s" }
    return $parts -join ' '
}

function Start-InformeProblemas {
    param (
        $groupIds, $groupRes, $authToken, $timeFrom, $timeTill, $outputFile
    )

    $resumenProblemas = @()
    $detalleProblemas = @()
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
        if (-not $groupName) { continue }

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
        if (-not $hosts) { continue }

        $hostIds = $hosts.hostid
        $reportData = @()

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

            if ($reportData.Count -gt 0) {
                $reportData | Sort-Object -Property Inicio -Descending | Export-Excel -Path $outputFile -WorksheetName $groupName `
                    -AutoSize -BoldTopRow -FreezeTopRow `
                    -TableName ("Tabla_{0}" -f $groupName.Replace(" ", "_")) `
                    -TableStyle Medium6 -Append
            }
        }
    }

    if ($resumenProblemas.Count -gt 0) {
        $resumenProblemas | Export-Excel -Path $outputFile -WorksheetName "Resumen_Problemas" `
            -AutoSize -BoldTopRow -FreezeTopRow `
            -TableName "ResumenProblemas" `
            -TableStyle Medium2 -Append

        $topHosts = $resumenProblemas | Sort-Object -Property Cantidad -Descending | Select-Object -First 10
        $topProblemas = $detalleProblemas | Group-Object Problema | Sort-Object Count -Descending | Select-Object Name, Count

        $wsParams = @{
            Path          = $outputFile
            WorksheetName = "Top_Alertas"
            AutoSize      = $true
            BoldTopRow    = $true
            FreezeTopRow  = $true
            TableStyle    = "Medium9"
        }

        $topHosts     | Export-Excel @wsParams -StartRow 1 -StartColumn 1 -Title "Top 10 Equipos más Alertados"
        $topProblemas | Export-Excel @wsParams -StartRow 1 -StartColumn 6 -Title "Problemas más Recurrentes"
    }
}
