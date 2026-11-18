#requires -Version 7.0
<#
Respalda cuatro bases de PostgreSQL de Kubernetes sin imprimir contraseñas.
Necesita permisos kubectl exec/cp y directorio ./backups ignorado por Git.
No aplica cambios en Flyway ni elimina archivos en el clúster.
#>
$ErrorActionPreference = 'Stop'
$ns = 'proyecto-03'
$root = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $root 'backups'
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dbs = @(
    @{Pod='auth-db';User='postgres';DB='auth_db'},
    @{Pod='users-db';User='postgres';DB='users_db'},
    @{Pod='products-db';User='postgres';DB='product_db'},
    @{Pod='payments-db';User='payments_app';DB='payments_db'}
)
foreach ($entry in $dbs) {
    $pod = (& kubectl -n $ns get pods -l "app=$($entry.Pod)" -o 'jsonpath={.items[0].metadata.name}')
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($pod)) { throw "No existe Pod para $($entry.Pod)" }
    $file = "$($entry.DB)-$stamp.dump"
    $remote = "/tmp/$file"
    Write-Host "Creando respaldo de $($entry.DB) en $pod"
    & kubectl -n $ns exec $pod -- pg_dump -U $entry.User -d $entry.DB -Fc -f $remote
    if ($LASTEXITCODE -ne 0) { throw "pg_dump falló para $($entry.DB)" }
    try {
        # kubectl cp no interpreta rutas absolutas Windows con ':'.
        Push-Location -LiteralPath $destination
        try {
            & kubectl -n $ns cp "${pod}:$remote" "./$file"
            if ($LASTEXITCODE -ne 0) { throw "kubectl cp falló para $($entry.DB)" }
        } finally { Pop-Location }
        $local = Join-Path $destination $file
        if (-not (Test-Path -LiteralPath $local) -or (Get-Item -LiteralPath $local).Length -lt 100) {
            throw "Respaldo inexistente o demasiado pequeño: $local"
        }
        # Comprueba que el remoto tiene formato PostgreSQL custom legible.
        & kubectl -n $ns exec $pod -- pg_restore --list $remote | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "pg_restore no pudo leer $remote" }
        Write-Host "RESPALDO CREADO: $local"
    } finally {
        & kubectl -n $ns exec $pod -- rm -f $remote | Out-Null
    }
}
Write-Host 'Respaldo completado. Verifique que backups/ NO se publique en Git.'
