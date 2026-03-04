# === CONFIGURACIÓN ===
$zabbixUrl = "http://172.18.168.120/zabbix/api_jsonrpc.php"
$authToken = "73567c1bd39693ce5e498a5a1e9930eb"
$hostsFile = "graficas_a_agregar.txt"
$dashboardId = 348
$pageIndex = 1  # Página 2 (0-based)

function Invoke-Zabbix {
    param($body)
    $json = $body | ConvertTo-Json -Depth 15 -Compress
    Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $json -ContentType "application/json"
}

# === Leer hosts (primer campo por línea) ===
$hosts = Get-Content $hostsFile | ForEach-Object { ($_ -split '\s+')[0].Trim() } | Where-Object { $_ } | Sort-Object -Unique

# === Obtener dashboard completo ===
$dashboardRes = Invoke-Zabbix @{
    jsonrpc = "2.0"
    method = "dashboard.get"
    params = @{ dashboardids = @($dashboardId); selectPages = "extend" }
    auth = $authToken
    id = 1
}

if (-not $dashboardRes.result) {
    Write-Error "Dashboard no encontrado."
    exit
}

$dashboard = $dashboardRes.result[0]

Write-Host "Dashboard ID: $($dashboard.dashboardid), Nombre: $($dashboard.name)"
Write-Host "Número de páginas en dashboard: $($dashboard.pages.Count)"

# Validar si la página existe
if ($dashboard.pages.Count -le $pageIndex) {
    Write-Warning "La página $pageIndex no existe, creando una nueva..."
    $newPage = @{
        name = "Página $([int]$pageIndex + 1)"
        widgets = @()
    }
    $dashboard.pages += $newPage
}

$page = $dashboard.pages[$pageIndex]

if (-not $page) {
    Write-Error "No se pudo obtener la página $pageIndex del dashboard."
    exit
}

Write-Host "Trabajando con página: $($page.name)"

# Limpiar widgets existentes
$page.widgets = @()

# Configuración de layout
$widgetWidth = 10
$widgetHeight = 2
#$maxX = 200
$maxY = 24

# Definir thresholds como string JSON comprimido
$thresholdsJson = '[{"value":0,"color":"FF0000"},{"value":1,"color":"00FF00"}]'


foreach ($hostname in $hosts) {
    Write-Host "[INFO] Creando widget para: $hostname"

    # Obtener hostid
    $hostRes = Invoke-Zabbix @{
        jsonrpc = "2.0"
        method = "host.get"
        params = @{ output = "hostid"; filter = @{ host = @($hostname) } }
        auth = $authToken
        id = 2
    }

    if (-not $hostRes.result) {
        Write-Warning "Host no encontrado: $hostname"
        continue
    }

    $hostid = $hostRes.result[0].hostid

    # Obtener itemid SNMP
    $itemRes = Invoke-Zabbix @{
        jsonrpc = "2.0"
        method = "item.get"
        params = @{
            output = @("itemid", "key_")
            hostids = $hostid
            filter = @{ key_ = "zabbix[host,snmp,available]" }
        }
        auth = $authToken
        id = 3
    }

    if (-not $itemRes.result) {
        Write-Warning "Item SNMP no encontrado para host: $hostname"
        continue
    }

    $itemid = $itemRes.result[0].itemid

# Parámetros para layout
    $widgetsPerRow = 7

    $row = [math]::Floor($page.widgets.Count / $widgetsPerRow)
    $col = $page.widgets.Count % $widgetsPerRow

    $xPos = $col * $widgetWidth
    $yPos = $row * $widgetHeight


    if ($yPos + $widgetHeight - 1 -gt $maxY) {
        $yPos = $maxY - $widgetHeight + 1
    }


# Definir los thresholds como cadena JSON comprimida
$thresholds = @(
    @{ value = 0; color = "FF0000" }  # rojo para 0
    @{ value = 1; color = "00FF00" }  # verde para 1
)

# Crear widget
$newWidget = @{
    type = "gauge"
    name = $hostname
    x = $xPos
    y = $yPos
    width = $widgetWidth
    height = $widgetHeight
    fields = @(
        @{ type = 4; name = "itemid.0"; value = "$itemid" }
        @{ type = 1; name = "min"; value = "0" }
        @{ type = 1; name = "max"; value = "1" }
        @{ type = 0; name = "show.0"; value = 1 }
        @{ type = 0; name = "show.1"; value = 2 }
        @{ type = 0; name = "show.2"; value = 3 }
        @{ type = 0; name = "show.4"; value = 4 }
        @{ type = 0; name = "show.5"; value = 5 }
        @{ type = 1; name = "angle"; value = "270" }
        @{
            type = 1
            name = "thresholds"
            value = $thresholdsJson
        }
    )
}

    $page.widgets += $newWidget
}

Write-Host "Widgets en página antes de actualizar: $($page.widgets.Count)"

# === Actualizar dashboard ===
$updateRes = Invoke-Zabbix @{
    jsonrpc = "2.0"
    method = "dashboard.update"
    params = @{
        dashboardid = $dashboardId
        name = $dashboard.name
        pages = $dashboard.pages
    }
    auth = $authToken
    id = 4
}

if ($updateRes.result) {
    Write-Host "[SUCCESS] Dashboard actualizado correctamente." -ForegroundColor Green
} else {
    Write-Warning "[ERROR] Error al actualizar dashboard."
    Write-Warning "Mensaje: $($updateRes.error.message) - $($updateRes.error.data)"
}
