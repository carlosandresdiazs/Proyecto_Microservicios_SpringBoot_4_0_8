# Diagnostico de migraciones aplicadas sin modificar PostgreSQL.
# Ejecutar desde raiz del repositorio en el equipo del runner Windows (PowerShell 7).
$ErrorActionPreference = 'Stop'
$ns = 'proyecto-03'
$root = Split-Path -Parent $PSScriptRoot
$databaseInfo = @(
    @{ Service='auth-service'; DB='auth-db'; User='postgres'; Database='auth_db' },
    @{ Service='user-service'; DB='users-db'; User='postgres'; Database='users_db' },
    @{ Service='product-service'; DB='products-db'; User='postgres'; Database='product_db' },
    @{ Service='payment-service'; DB='payments-db'; User='payments_app'; Database='payments_db' }
)

function Get-FlywayChecksum([string]$File) {
    # Flyway calcula CRC32 concatenando los bytes UTF-8 de cada linea SIN saltos de linea.
    [uint32]$crc = 4294967295
    foreach ($line in [System.IO.File]::ReadAllLines($File, [System.Text.Encoding]::UTF8)) {
        $clean = $line.TrimStart([char]0xFEFF)
        foreach ($b in [System.Text.Encoding]::UTF8.GetBytes($clean)) {
            $crc = $crc -bxor [uint32]$b
            for ($i = 0; $i -lt 8; $i++) {
                if (($crc -band 1) -ne 0) {
                    $crc = ($crc -shr 1) -bxor [uint32]3988292384
                } else { $crc = $crc -shr 1 }
            }
        }
    }
    $crc = $crc -bxor [uint32]4294967295
    if ([long]$crc -gt 2147483647) { return ([long]$crc - 4294967296) }
    return [long]$crc
}

$errors = [System.Collections.Generic.List[string]]::new()
foreach ($item in $databaseInfo) {
    $dir = Join-Path $root "$($item.Service)/src/main/resources/db/migration"
    $files = @(Get-ChildItem -LiteralPath $dir -Filter 'V*__*.sql' -File)
    Write-Host "`n===== $($item.Service) / $($item.Database) ====="
    $query = 'SELECT version, description, script, COALESCE(checksum::text, ''''), success FROM flyway_schema_history WHERE version IS NOT NULL ORDER BY installed_rank;'
    $rows = @(& kubectl -n $ns exec "deployment/$($item.DB)" -- psql -U $item.User -d $item.Database -A -t -F '|' -c $query 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $errors.Add("No se pudo consultar Flyway en $($item.DB): $($rows -join ' ')")
        continue
    }
    $history = @{}
    foreach ($row in $rows) {
        if ($row -notmatch '^([^|]+)\|([^|]*)\|([^|]*)\|([^|]*)\|(t|f)$') { continue }
        $history[$Matches[1]] = @{ Description=$Matches[2]; Script=$Matches[3]; Checksum=$Matches[4]; Success=$Matches[5] }
    }
    foreach ($file in $files) {
        if ($file.Name -notmatch '^V([0-9][0-9._]*)__([^.]+)\.sql$') { continue }
        $version = $Matches[1].Replace('_','.')
        $description = $Matches[2].Replace('_',' ')
        $checksum = Get-FlywayChecksum $file.FullName
        if (-not $history.ContainsKey($version)) {
            Write-Host "PENDIENTE V${version}: $($file.Name) (checksum=$checksum)"
            continue
        }
        $saved = $history[$version]
        $ok = $saved.Success -eq 't' -and $saved.Description -eq $description -and $saved.Script -eq $file.Name -and $saved.Checksum -eq "$checksum"
        if ($ok) { Write-Host "OK V${version}: $($file.Name) checksum=$checksum" }
        else {
            $errors.Add("$($item.Service) V${version}: DB=[$($saved.Script), $($saved.Description), $($saved.Checksum), success=$($saved.Success)] REPO=[$($file.Name), $description, $checksum]")
        }
    }
    foreach ($v in $history.Keys) {
        if (-not ($files | Where-Object { $_.Name -match ('^V' + [regex]::Escape($v) + '__') })) {
            $errors.Add("$($item.Service): DB contiene V${v}, pero falta el archivo local correspondiente")
        }
    }
}
if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Host "ERROR FLYWAY: $e" }
    throw 'Migraciones incompatibles. Restaurar las V1 historicas o preparar migraciones nuevas; no alterar flyway_schema_history automaticamente.'
}
Write-Host "`nPreflight Flyway: sin discrepancias en migraciones versionadas registradas."
