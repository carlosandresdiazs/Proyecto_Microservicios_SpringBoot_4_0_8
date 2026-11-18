# Ejecutar DESDE LA RAIZ del proyecto, una vez extraído el ZIP en esa raíz.
# Requiere hacer primero backup: pwsh -File scripts/backup-postgres.ps1
$ErrorActionPreference='Stop'
foreach ($service in @('user-service','product-service','payment-service')) {
    $old = Join-Path $service 'src/main/resources/db/migration/V1__initial_schema.sql'
    if (Test-Path -LiteralPath $old) {
        git rm -- $old
        if ($LASTEXITCODE -ne 0) { throw "No se pudo eliminar V1 obsoleta de $service" }
    }
}
python scripts/validate-project.py
if ($LASTEXITCODE -ne 0) { throw 'Validación estática falló' }
pwsh -File scripts/check-flyway-history.ps1
if ($LASTEXITCODE -ne 0) { throw 'Checksum o descripción NO coinciden. Recuperar V1 originales; NO desplegar.' }
Write-Host 'Preflight correcto; revisar diff y publicar a GitHub manualmente.'
