# === Configurar consola para mostrar tildes correctamente ===
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# === Cargar funciones ===  
. "$PSScriptRoot\Funciones\InformeDisponibilidad.ps1"
. "$PSScriptRoot\Funciones\InformeProblemas.ps1"
#. "$PSScriptRoot\funciones\Utilidades.ps1"  # Si usas Convert-ToTimestamp, Format-Duration, etc.

# === Configuración ===
$zabbixUrl = "http://172.18.168.120/zabbix/api_jsonrpc.php"
$authToken = "07ea5813c003d29399b563a0db4798b7"

Import-Module ImportExcel -ErrorAction Stop

# === Función para llamadas a la API de Zabbix ===
# === Función para llamadas a la API de Zabbix (Zabbix 7.4+ compatible) ===
function Invoke-Zabbix {
    param($body)

    $json = $body | ConvertTo-Json -Depth 12 -Compress
    $headers = @{
        "Content-Type"  = "application/json"
        "Authorization" = "Bearer $authToken"
    }

    try {
        return Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $json -Headers $headers
    } catch {
        Write-Host "❌ ERROR en la API: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}


# === Obtener y mostrar grupos disponibles ===
$groupRes = Invoke-Zabbix @{
    jsonrpc = "2.0"
    method  = "hostgroup.get"
    params  = @{ output = "extend" }
    id      = 1
}

if (-not $groupRes.result) {
    Write-Host ("No se encontraron grupos.")
    exit
}

Write-Host "`n================ LISTA DE GRUPOS DISPONIBLES ================"
Write-Host "| GroupID | Nombre                                        |"
Write-Host "------------------------------------------------------------"
foreach ($g in $groupRes.result) {
    Write-Host ("| {0,-7} | {1,-44} |" -f $g.groupid, $g.name)
}
Write-Host "============================================================"

# === Selección de grupos con validación ===
do {
    $selectedIds = Read-Host "Ingrese los IDs de los grupos separados por coma"
    $groupIds = $selectedIds -split "," | ForEach-Object { $_.Trim() }
    # Validar que todos los IDs existen
    $invalidIds = $groupIds | Where-Object { -not ($groupRes.result.groupid -contains $_) }
    if ($invalidIds.Count -gt 0) {
        Write-Host ("Los siguientes IDs NO son válidos: $($invalidIds -join ', ')") -ForegroundColor Red
    }
} while ($invalidIds.Count -gt 0 -or $groupIds.Count -eq 0)

# === Tipo de informe con validación ===
do {
    Write-Host "`n================== OPCIONES DE INFORME =================="
    Write-Host ("| [1] Informe de Disponibilidad                           |")
    Write-Host ("| [0] Informe de Problemas                                |")
    Write-Host "=========================================================="
    $tipoInput = Read-Host "Seleccione (0 o 1)"
} while ($tipoInput -notin @("0","1"))

$tipoInforme = if ($tipoInput -eq "1") { "disponibilidad" } else { "problemas" }

# === Selección de rango de fechas con opciones sencillas ===
Write-Host "`nSeleccione el rango de fechas:"
Write-Host ("  [1] Últimos 7 días")
Write-Host ("  [2] Últimos 30 días")
Write-Host ("  [3] Personalizado")

do {
    $rangoInput = Read-Host "Ingrese opción (1, 2 o 3)"
} while ($rangoInput -notin @("1","2","3"))

switch ($rangoInput) {
    "1" {
        $fechaFin = Get-Date
        $fechaInicio = $fechaFin.AddDays(-7)
    }
    "2" {
        $fechaFin = Get-Date
        $fechaInicio = $fechaFin.AddDays(-30)
    }
    "3" {
        Write-Host "Ingrese las fechas en formato:" `
            + "`n- YYYY-MM-DD" `
            + "`n- o YYYY-MM-DD HH:mm:ss (opcional para hora)" `
            + "`nSi solo pone fecha, se usará 00:00:00 para inicio y 23:59:59 para fin."

        # Fecha inicio
        do {
            if ($fechaInicioInput -match '^\d{4}-\d{2}-\d{2}$') {
                    $fechaInicio = $fechaInicio.Date
                }

            $fechaInicioInput = Read-Host "Fecha inicial (YYYY-MM-DD o YYYY-MM-DD HH:mm:ss)"
            try {
                $fechaInicio = [datetime]$fechaInicioInput
                if ($fechaInicioInput.Length -le 10) {
                    $fechaInicio = $fechaInicio.Date
                }
            } catch {
                Write-Host "Formato inválido. Intente de nuevo." -ForegroundColor Red
                $fechaInicio = $null
            }
        } while (-not $fechaInicio)

        # Fecha fin
        do {
            $fechaFinInput = Read-Host "Fecha final (YYYY-MM-DD o YYYY-MM-DD HH:mm:ss)"
            try {
                $fechaFin = [datetime]$fechaFinInput
                if ($fechaFinInput.Length -le 10) {
                    $fechaFin = $fechaFin.Date.AddHours(23).AddMinutes(59).AddSeconds(59)
                }
            } catch {
                Write-Host "Formato inválido. Intente de nuevo." -ForegroundColor Red
                $fechaFin = $null
            }
        } while (-not $fechaFin)

        if ($fechaFin -lt $fechaInicio) {
            Write-Host "⚠️ La fecha final no puede ser anterior a la inicial. Se ajustará automáticamente."
            $fechaFin = $fechaInicio.AddDays(1).AddSeconds(-1)
        }
    }
}

# Convertir a timestamp UNIX
function Convert-ToTimestamp {
    param($dateTime)
    [int][double]::Parse((Get-Date $dateTime -UFormat %s))
}

$timeFrom = Convert-ToTimestamp $fechaInicio
$timeTill = Convert-ToTimestamp $fechaFin

# Construir nombre de archivo con rango y tipo de informe
# Formato: Informe_<tipo>_YYYYMMDD-HHMMSS_YYYYMMDD-HHMMSS.xlsx
$outputFile = "Informe_${tipoInforme}_$($fechaInicio.ToString('yyyy-MM-dd_HH-mm-ss'))_$($fechaFin.ToString('yyyy-MM-dd_HHmm-ss')).xlsx"

# === Eliminar archivo si existe ===
if (Test-Path $outputFile) { Remove-Item $outputFile }

# === Ejecutar función según tipo ===
if ($tipoInforme -eq "disponibilidad") {
    Start-InformeDisponibilidad -groupIds $groupIds -groupRes $groupRes -authToken $authToken `
                               -timeFrom $timeFrom -timeTill $timeTill -outputFile $outputFile
} else {
    Start-InformeProblemas -groupIds $groupIds -groupRes $groupRes -authToken $authToken `
                          -timeFrom $timeFrom -timeTill $timeTill -outputFile $outputFile
}

Write-Host "`n✅ Archivo generado: $outputFile"
