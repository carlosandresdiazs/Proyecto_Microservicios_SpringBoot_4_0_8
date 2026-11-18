#requires -Version 7.0
<#
.SYNOPSIS
  Comprueba las migraciones SQL versionadas de Flyway contra PostgreSQL en Kubernetes.
.DESCRIPTION
  No altera las bases de datos ni flyway_schema_history. Devuelve exit code 1 si
  existen errores de acceso, migraciones aplicadas incompatibles o archivos faltantes.
  Las migraciones nuevas sin aplicar se muestran como PENDIENTE.
.EXAMPLE
  pwsh -File scripts/check-flyway-history.ps1
.EXAMPLE
  pwsh -File scripts/check-flyway-history.ps1 -Namespace proyecto-03
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Namespace = 'proyecto-03'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$databaseInfo = @(
    @{ Service='auth-service';    Deployment='auth-db';     User='postgres';     Database='auth_db' },
    @{ Service='user-service';    Deployment='users-db';    User='postgres';     Database='users_db' },
    @{ Service='product-service'; Deployment='products-db'; User='postgres';     Database='product_db' },
    @{ Service='payment-service'; Deployment='payments-db'; User='payments_app'; Database='payments_db' }
)

function Get-FlywayChecksum {
    param([Parameter(Mandatory)][string]$Path)
    # Flyway SQL checksum: CRC32 de cada linea UTF-8 SIN caracteres de fin de linea.
    # StreamReader detecta y elimina el BOM inicial, sin modificar lineas posteriores.
    $crc = [uint32]::MaxValue
    $reader = [System.IO.StreamReader]::new($Path, [System.Text.Encoding]::UTF8, $true)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            foreach ($b in [System.Text.Encoding]::UTF8.GetBytes($line)) {
                $crc = $crc -bxor [uint32]$b
                for ($i = 0; $i -lt 8; $i++) {
                    if (($crc -band [uint32]1) -ne 0) {
                        $crc = ($crc -shr 1) -bxor [uint32]0xEDB88320
                    } else {
                        $crc = $crc -shr 1
                    }
                }
            }
        }
    } finally {
        $reader.Dispose()
    }
    $crc = $crc -bxor [uint32]::MaxValue
    if ([long]$crc -gt [int]::MaxValue) { return ([long]$crc - 4294967296L) }
    return [long]$crc
}

function Get-FlywayVersionKey {
    param([Parameter(Mandatory)][string]$Version)
    # Flyway representa los separadores '_' de nombres de archivos como '.'.
    return $Version.Replace('_', '.')
}

$errors = [System.Collections.Generic.List[string]]::new()
$pendingCount = 0
$okCount = 0

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error 'No se encontro kubectl en PATH.' -ErrorAction Continue
    exit 1
}

foreach ($item in $databaseInfo) {
    $service = $item.Service
    $dbName = $item.Database
    Write-Host "`n===== $service / $dbName ====="
    $migrationDir = Join-Path $root "$service/src/main/resources/db/migration"
    if (-not (Test-Path -LiteralPath $migrationDir -PathType Container)) {
        $errors.Add("$service`: no existe la carpeta $migrationDir")
        continue
    }

    $files = @(Get-ChildItem -LiteralPath $migrationDir -File -Filter 'V*__*.sql')
    $local = @{}
    foreach ($file in $files) {
        if ($file.Name -cnotmatch '^V([0-9]+(?:[._][0-9]+)*)__([^.]+)\.sql$') {
            $errors.Add("$service`: nombre de migracion no valido: $($file.Name)")
            continue
        }
        $version = Get-FlywayVersionKey $Matches[1]
        $description = $Matches[2].Replace('_', ' ')
        if ($local.ContainsKey($version)) {
            $errors.Add("$service`: varios archivos definen V${version}: $($local[$version].Script) y $($file.Name)")
            continue
        }
        $local[$version] = @{
            Script = $file.Name
            Description = $description
            Checksum = [string](Get-FlywayChecksum -Path $file.FullName)
        }
    }

    # Una fila por linea. El formato de salida no depende del idioma de psql.
    # ON_ERROR_STOP evita interpretar errores SQL como un historial vacio.
    $query = "SELECT version, description, script, COALESCE(checksum::text, ''), success FROM flyway_schema_history WHERE version IS NOT NULL ORDER BY installed_rank;"
    $cmdOutput = @(& kubectl -n $Namespace exec "deployment/$($item.Deployment)" -- `
        psql -X -v ON_ERROR_STOP=1 -U $item.User -d $dbName -A -t -F '|' -c $query 2>&1)
    $status = $LASTEXITCODE
    if ($status -ne 0) {
        $errors.Add("$service`: fallo la consulta a $dbName (exit=$status): $($cmdOutput -join ' ')")
        continue
    }

    $history = @{}
    $badRows = @()
    foreach ($outputLine in $cmdOutput) {
        $line = ([string]$outputLine).Trim()
        if (-not $line) { continue }
        if ($line -notmatch '^([^|]+)\|([^|]*)\|([^|]*)\|([^|]*)\|(t|f)$') {
            $badRows += $line
            continue
        }
        $version = $Matches[1]
        if ($history.ContainsKey($version)) {
            $errors.Add("$service`: version duplicada V${version} en flyway_schema_history")
            continue
        }
        $history[$version] = @{
            Description = $Matches[2]
            Script = $Matches[3]
            Checksum = $Matches[4]
            Success = $Matches[5]
        }
    }
    if ($badRows.Count -gt 0) {
        $errors.Add("$service`: respuesta psql no interpretable: $($badRows -join ' // ')")
        continue
    }

    foreach ($version in ($local.Keys | Sort-Object)) {
        $current = $local[$version]
        if (-not $history.ContainsKey($version)) {
            Write-Host "PENDIENTE V${version}: $($current.Script) (checksum=$($current.Checksum))"
            $pendingCount++
            continue
        }
        $saved = $history[$version]
        $differences = @()
        if ($saved.Success -ne 't') { $differences += 'migracion no exitosa' }
        if ($saved.Script -cne $current.Script) { $differences += 'nombre de archivo' }
        if ($saved.Description -cne $current.Description) { $differences += 'descripcion' }
        if ($saved.Checksum -cne $current.Checksum) { $differences += 'checksum' }

        if ($differences.Count -eq 0) {
            Write-Host "OK V${version}: $($current.Script) checksum=$($current.Checksum)"
            $okCount++
        } else {
            $errors.Add("$service V${version}: difiere $($differences -join ', '). DB=[$($saved.Script), $($saved.Description), $($saved.Checksum), success=$($saved.Success)] REPO=[$($current.Script), $($current.Description), $($current.Checksum)]")
        }
    }
    foreach ($version in $history.Keys) {
        if (-not $local.ContainsKey($version)) {
            $errors.Add("$service`: DB contiene V${version} ($($history[$version].Script)), pero falta el SQL local")
        }
    }
}

Write-Host "`nResumen: $okCount migraciones coincidentes; $pendingCount pendientes; $($errors.Count) errores."
if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "ERROR FLYWAY: $message" -ForegroundColor Red }
    Write-Host 'Se ha bloqueado el despliegue. Restaurar las migraciones historicas o revisar cambios de esquema antes de utilizar Flyway repair.' -ForegroundColor Red
    exit 1
}
Write-Host 'Preflight Flyway: sin discrepancias en migraciones versionadas registradas.' -ForegroundColor Green
exit 0
