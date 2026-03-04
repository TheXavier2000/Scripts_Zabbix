function Start-InformeDisponibilidad {
    param (
        [int[]] $groupIds,
        [object] $groupRes,
        [string] $authToken,
        [int] $timeFrom,
        [int] $timeTill,
        [string] $outputFile
    )

    $groupIds = $groupIds | ForEach-Object { [int]$_ }
    $validGroupIds = $groupRes.result | Where-Object { $groupIds -contains ([int]$_.groupid) } | ForEach-Object { [int]$_.groupid }

    if (-not $validGroupIds -or $validGroupIds.Count -eq 0) {
        Write-Warning "No se encontraron grupos válidos para procesar. Revisar IDs proporcionados."
        return
    }

    $fechaEjecucion = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $promediosGlobales = New-Object System.Collections.Generic.List[double]
    $globalIndex = 0
    $totalHostsGlobal = 0
    $promediosPorGrupo = @()
    $hostsDisponibilidades = @()

    # Primera pasada para contar todos los hosts de todos los grupos
    foreach ($groupId in $validGroupIds) {
        try {
            $hostsCountRes = Invoke-Zabbix @(
                @{ jsonrpc = "2.0"; method = "host.get"; params = @{ output = @("hostid"); groupids = $groupId }; auth = $authToken; id = 900 + $groupId }
            )
            if ($hostsCountRes -and $hostsCountRes.result) {
                $totalHostsGlobal += $hostsCountRes.result.Count
            }
        } catch {
            Write-Warning "Error obteniendo conteo de hosts para grupo ID $groupId : $_"
        }
    }

    $globalIndex = 0 # Reiniciamos para usarlo como contador de progreso
    $datosPorGrupo = @{}

    foreach ($groupId in $validGroupIds) {
        $groupEntry = $groupRes.result | Where-Object { [int]$_.groupid -eq $groupId }
        if (-not $groupEntry) {
            Write-Warning "No se pudo determinar el nombre del grupo con ID $groupId. Se omite."
            continue
        }

        $groupName = $groupEntry.name

        # Progreso por grupo
        $grupoIndex = [array]::IndexOf($validGroupIds, $groupId)
        $porcentajeGrupo = [math]::Round(($grupoIndex / $validGroupIds.Count) * 100)
        Write-Progress -Activity "Procesando grupo: $groupName" -Status "Grupo $($grupoIndex + 1) de $($validGroupIds.Count)" -PercentComplete $porcentajeGrupo

        try {
            $hostsRes = Invoke-Zabbix @(
                @{ jsonrpc = "2.0"; method = "host.get"; params = @{ output = @("hostid", "host", "name"); selectInterfaces = @("ip"); selectGroups = @("name"); groupids = $groupId }; auth = $authToken; id = 100 + $groupId }
            )
        } catch {
            Write-Warning "Error obteniendo hosts para grupo $groupName : $_"
            continue
        }

        $hosts = $hostsRes.result
        if (-not $hosts -or $hosts.Count -eq 0) {
            Write-Warning "No se encontraron hosts para el grupo $groupName."
            continue
        }

        $allHostIds = $hosts | ForEach-Object { $_.hostid }

        try {
            $itemRes = Invoke-Zabbix @(
                @{ jsonrpc = "2.0"; method = "item.get"; params = @{ output = @("itemid", "hostid", "key_"); hostids = $allHostIds; filter = @{ key_ = "icmpping" } }; auth = $authToken; id = 101 + $groupId }
            )
        } catch {
            Write-Warning "Error obteniendo items icmpping para grupo $groupName : $_"
            continue
        }

        $items = $itemRes.result
        if (-not $items -or $items.Count -eq 0) {
            Write-Warning "No se encontraron items icmpping para $groupName."
            continue
        }

        $itemIds = $items | ForEach-Object { $_.itemid }

        try {
            $historyRes = Invoke-Zabbix @(
                @{ jsonrpc = "2.0"; method = "history.get"; params = @{ output = "extend"; history = 3; itemids = $itemIds; time_from = $timeFrom; time_till = $timeTill; sortfield = "clock"; sortorder = "ASC"; limit = 100000 }; auth = $authToken; id = 102 + $groupId }
            )
        } catch {
            Write-Warning "Error obteniendo histórico para grupo $groupName : $_"
            continue
        }
        $history = $historyRes.result

        try {
            $problemRes = Invoke-Zabbix @(
                @{ jsonrpc = "2.0"; method = "problem.get"; params = @{ output = @("eventid", "name", "clock", "r_eventid", "hostid"); hostids = $allHostIds; time_from = $timeFrom; time_till = $timeTill; selectRelatedObject = "extend" }; auth = $authToken; id = 103 + $groupId }
            )
        } catch {
            Write-Warning "Error obteniendo problemas para grupo $groupName : $_"
            continue
        }
        $problems = $problemRes.result

        $historyByItem = @{}
        foreach ($h in $history) {
            if (-not $historyByItem.ContainsKey($h.itemid)) {
                $historyByItem[$h.itemid] = @()
            }
            $historyByItem[$h.itemid] += $h
        }

        $problemsByHost = @{}
        foreach ($p in $problems) {
            if (-not $problemsByHost.ContainsKey($p.hostid)) {
                $problemsByHost[$p.hostid] = @()
            }
            $problemsByHost[$p.hostid] += $p
        }

        $reportData = @()
        $promediosLocales = @()

        foreach ($zbxhost in $hosts) {
            $globalIndex++

            # Progreso por host
            $porcentajeHost = if ($totalHostsGlobal -gt 0) {
                [math]::Round(($globalIndex / $totalHostsGlobal) * 100)
            } else {
                0
            }
            Write-Progress -Activity "Procesando host: $($zbxhost.name)" -Status "Host $globalIndex de $totalHostsGlobal" -PercentComplete $porcentajeHost

            $item = $items | Where-Object { $_.hostid -eq $zbxhost.hostid }
            if (-not $item) { continue }

            $hostHistory = if ($historyByItem.ContainsKey($item.itemid)) { $historyByItem[$item.itemid] } else { @() }
            $hostProblems = if ($problemsByHost.ContainsKey($zbxhost.hostid)) { $problemsByHost[$zbxhost.hostid] } else { @() }

            $disponibilidadPromedio = "Sin datos"

            if ($hostHistory.Count -gt 0) {
                $hayProblemaICMP = $hostProblems | Where-Object { $_.name -like "*unavailable by icmp ping*" }
                if ($hayProblemaICMP) {
                    $disponibilidadPromedio = 0
                } else {
                    $histPorDia = @{}
                    foreach ($entry in $hostHistory) {
                        $dia = ([System.DateTimeOffset]::FromUnixTimeSeconds([int]$entry.clock)).DateTime.Date
                        if (-not $histPorDia.ContainsKey($dia)) {
                            $histPorDia[$dia] = @()
                        }
                        $histPorDia[$dia] += $entry
                    }

                    $disponibilidadesDias = @()
                    foreach ($dia in $histPorDia.Keys) {
                        $datosDia = $histPorDia[$dia]
                        $countUp = ($datosDia | Where-Object { $_.value -eq "1" }).Count
                        $total = $datosDia.Count
                        if ($total -gt 0) {
                            $disponibilidadesDias += [math]::Round(($countUp / $total) * 100, 2)
                        }
                    }

                    if ($disponibilidadesDias.Count -gt 0) {
                        $disponibilidadPromedio = [math]::Round(($disponibilidadesDias | Measure-Object -Average).Average, 2)
                    }
                }
            }

            if ($disponibilidadPromedio -isnot [string]) {
                $promediosGlobales += $disponibilidadPromedio
                $promediosLocales += $disponibilidadPromedio
                $hostsDisponibilidades += [PSCustomObject]@{
                    Nombre         = $zbxhost.name
                    IP             = if ($zbxhost.interfaces) { '="' + $zbxhost.interfaces[0].ip + '"' } else { "" }
                    Grupo          = ($zbxhost.groups | ForEach-Object { $_.name }) -join " | "
                    Disponibilidad = $disponibilidadPromedio
                }
            }

            $reportData += [PSCustomObject]@{
                Nombre         = $zbxhost.name
                IP             = if ($zbxhost.interfaces) { '="' + $zbxhost.interfaces[0].ip + '"' } else { "" }
                Grupo          = ($zbxhost.groups | ForEach-Object { $_.name }) -join " | "
                Disponibilidad = if ($disponibilidadPromedio -is [string]) { $disponibilidadPromedio } else { "$disponibilidadPromedio%" }
                FechaReporte   = $fechaEjecucion
            }
        }

        if ($reportData.Count -gt 0) {
            $datosPorGrupo[$groupName] = $reportData
        }

        if ($promediosLocales.Count -gt 0) {
            $avgGrupo = [math]::Round(($promediosLocales | Measure-Object -Average).Average, 2)
        } else {
            $avgGrupo = "Sin datos"
        }

        $promediosPorGrupo += [PSCustomObject]@{
            Grupo                    = $groupName
            Promedio_Disponibilidad = if ($avgGrupo -is [string]) { $avgGrupo } else { "$avgGrupo%" }
        }
    }

    # Limpiar archivo si existe antes de escribir
    if (Test-Path $outputFile) { Remove-Item $outputFile }

    $primerGrupo = $true
    foreach ($groupName in $datosPorGrupo.Keys) {
        $data = $datosPorGrupo[$groupName] | Sort-Object -Property Nombre

        if ($data.Count -gt 0) {
        $data | Export-Excel -Path $outputFile -WorksheetName $groupName -AutoSize -BoldTopRow -FreezeTopRow -TableName ("Tabla_{0}" -f $groupName.Replace(" ", "_")) -TableStyle Medium6 -Append:(!$primerGrupo)
}
 else {
            Write-Warning "No hay datos para exportar en el grupo $groupName"
        }

        $primerGrupo = $false
    }

# === GENERACIÓN DE HOJA RESUMEN MEJORADA ===

# Convertir fechas para mostrar en el resumen
$fechaInicio = ([System.DateTimeOffset]::FromUnixTimeSeconds($timeFrom)).ToString("yyyy-MM-dd HH:mm")
$fechaFin = ([System.DateTimeOffset]::FromUnixTimeSeconds($timeTill)).ToString("yyyy-MM-dd HH:mm")

# Calcular promedio general
$promedioGeneral = if ($promediosGlobales.Count -gt 0) {
    [math]::Round(($promediosGlobales | Measure-Object -Average).Average, 2)
} else {
    "Sin datos"
}

# Crear objeto resumen
$resumen = [PSCustomObject]@{
    Fecha_Generacion                 = $fechaEjecucion
    Rango_Analizado                 = "$fechaInicio - $fechaFin"
    Promedio_Disponibilidad_General = if ($promedioGeneral -is [string]) { $promedioGeneral } else { "$promedioGeneral%" }
}

# Crear Top 10 (ordenado de menor a mayor disponibilidad)
$top10 = $hostsDisponibilidades |
    Sort-Object Disponibilidad |
    Select-Object -First 10 |
    ForEach-Object {
        [PSCustomObject]@{
            Nombre         = $_.Nombre
            IP             = $_.IP
            Grupo          = $_.Grupo
            Disponibilidad = "$($_.Disponibilidad)%"
        }
    }

# Exportar resumen general
if ($resumen) {
    $resumen | Export-Excel -Path $outputFile -WorksheetName "Resumen" `
        -AutoSize -BoldTopRow -FreezeTopRow -TableStyle Medium2
}

# Crear tabla de promedios por grupo + rango analizado para hoja Resumen
$promediosPorGrupoConRango = $promediosPorGrupo | ForEach-Object {
    [PSCustomObject]@{
        Grupo                   = $_.Grupo
        Rango_Analizado         = "$fechaInicio - $fechaFin"
        Promedio_Disponibilidad = $_.Promedio_Disponibilidad
    }
}

if ($promediosPorGrupoConRango.Count -gt 0) {
    $promediosPorGrupoConRango | Export-Excel -Path $outputFile `
        -WorksheetName "Resumen" `
        -Append `
        -StartRow 5 `
        -StartColumn 1 `
        -TableStyle Medium9 `
        -TableName "PromedioPorGrupoConRango"
} else {
    Write-Warning "No hay datos para promedio por grupo con rango"
}

# Exportar Top 10 equipos con menor disponibilidad si hay datos
if ($top10.Count -gt 0) {
    # Ajustar startRow para no pisar tabla anterior
    $startRow = 8
    if ($promediosPorGrupoConRango.Count -gt 0) {
        # +3 filas para espacio y título, + count filas tabla promedio
        $startRow = 5 + $promediosPorGrupoConRango.Count + 3
    }

    # Exportar título Top 10 (opcional)
    $tituloTop10 = [PSCustomObject]@{ Top10_Peor_Disponibilidad = "Dispositivos con mayor pérdida" }
    $tituloTop10 | Export-Excel -Path $outputFile -WorksheetName "Resumen" -Append `
        -StartRow $startRow -StartColumn 1 -TableStyle None

    # Exportar tabla Top 10
    $top10 | Export-Excel -Path $outputFile -WorksheetName "Resumen" -Append `
        -StartRow ($startRow + 1) -StartColumn 1 -TableStyle Medium10 -TableName "Top10PeorDisponibilidad"

} else {
    Write-Warning "No hay datos para Top 10"
}

Write-Progress -Activity "Calculando disponibilidad" -Completed


}