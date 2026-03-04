# === CONFIGURACIÓN ===
$zabbixUrl        = "http://10.161.115.127/zabbix/api_jsonrpc.php"
$authToken        = "c72cf6e672eb4c4800c004902e70f798"
$hostsFile        = "hosts_a_agregar.txt"
$groupId          = 44
$templateSnmpId   = 11575

# Variables para SNMPv3
$snmpSecurityName   = "Monitoreosolarwinds"
$snmpAuthPassphrase = "Or10nconf3"
$snmpPrivPassphrase = "Or10nconf3"

$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $authToken"
}

function HostExists {
    param ([string]$hostname, [string]$ip)

    # Buscar por nombre
    $bodyByName = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            output = "hostid"
            filter = @{ host = @($hostname) }
        }
        id = 1
    } | ConvertTo-Json -Depth 3

    $respByName = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Headers $headers -Body $bodyByName
    if ($respByName.result.Count -gt 0) {
        return $true
    }

    # Buscar por IP en interfaces
    $bodyByIp = @{
        jsonrpc = "2.0"
        method  = "host.get"
        params  = @{
            output = "extend"
            selectInterfaces = "extend"
        }
        id = 2
    } | ConvertTo-Json -Depth 4

    $respByIp = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Headers $headers -Body $bodyByIp
    foreach ($zbxhost in $respByIp.result) {
        foreach ($iface in $zbxhost.interfaces) {
            if ($iface.useip -eq 1 -and $iface.ip -eq $ip) {
                return $true
            }
        }
    }

    return $false
}

function CreateHost {
    param ([string]$ip, [string]$hostname)
    Write-Host "→ Creando host '$hostname' con IP $ip..." -ForegroundColor Cyan

    $interfaces = @(@{
        type    = 2          # SNMP
        main    = 1
        useip   = 1
        ip      = $ip
        dns     = ""
        port    = "161"
        details = @{
            version        = 3
            securityname   = $snmpSecurityName
            securitylevel  = 2              # authPriv
            authprotocol   = 3              # SHA256 (numérico)
            authpassphrase = $snmpAuthPassphrase
            privprotocol   = 3              # AES256 (numérico)
            privpassphrase = $snmpPrivPassphrase
            contextname    = $snmpSecurityName
        }
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
        id = 3
    } | ConvertTo-Json -Depth 6

    try {
        $res = Invoke-RestMethod -Uri $zabbixUrl -Method Post -Body $createBody -Headers $headers
        if ($res.result -and $res.result.hostids) {
            Write-Host "[OK] Host '$hostname' creado exitosamente (ID: $($res.result.hostids[0]))" -ForegroundColor Green
        } elseif ($res.error) {
            Write-Host "[ERROR] Error al crear '$hostname': $($res.error.message) - $($res.error.data)" -ForegroundColor Red
        } else {
            Write-Host "[ERROR] No se pudo crear '$hostname'. Respuesta desconocida: $($res | ConvertTo-Json -Depth 5)" -ForegroundColor Red
        }
    } catch {
        Write-Host "[ERROR] Fallo al crear '$hostname': $_" -ForegroundColor Red
    }
}

if (Test-Path $hostsFile) {
    Get-Content $hostsFile | ForEach-Object {
        if ($_ -match "\S") {
            $parts = ($_ -split "\s+") | ForEach-Object { $_.Trim() }
            $ipRegex = '^(?:\d{1,3}\.){3}\d{1,3}$'
            $ip = $parts | Where-Object { $_ -match $ipRegex } | Select-Object -First 1
            $hostnameParts = $parts | Where-Object { $_ -notmatch $ipRegex }
            $hostname = ($hostnameParts -join " ").Trim()

            if ($ip -and $hostname) {
                if (HostExists -hostname $hostname -ip $ip) {
                    Write-Host "[INFO] Host '$hostname' o IP '$ip' ya existe en Zabbix. No se crea ni modifica." -ForegroundColor Yellow
                } else {
                    CreateHost -ip $ip -hostname $hostname
                }
            } else {
                Write-Host "[ERROR] Línea inválida en el archivo: $_" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "[ERROR] Archivo '$hostsFile' no encontrado." -ForegroundColor Red
}
