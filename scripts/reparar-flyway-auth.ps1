# Reparación controlada del checksum V1 de auth-service, SOLO para la incidencia documentada.
# Ejecutar en PowerShell 7 desde Windows con acceso al clúster docker-desktop.
# No modifica migraciones SQL ni elimina tablas o PVC.
[CmdletBinding()]
param(
    [switch]$AplicarReparacion,
    [string]$DestinoBackup = (Join-Path (Get-Location) 'backups')
)
$ErrorActionPreference = 'Stop'
$ns = 'proyecto-03'
$expectedOld = '299997627'    # Checksum registrado según logs aportados
$expectedNew = '2064439196'   # Checksum del SQL de la imagen en los logs

function K {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & kubectl @Arguments
    if ($LASTEXITCODE -ne 0) { throw "kubectl falló: $($Arguments -join ' ')" }
}

K @('config','current-context')
$context = (& kubectl config current-context).Trim()
if ($context -ne 'docker-desktop') { throw "Contexto inesperado: $context" }
K @('-n',$ns,'get','deployment','auth-db','-o','name')
$pod = (& kubectl -n $ns get pods -l app=auth-db -o 'jsonpath={.items[0].metadata.name}').Trim()
if ($LASTEXITCODE -ne 0 -or -not $pod) { throw 'No se encontró el Pod de auth-db' }
K @('-n',$ns,'exec',$pod,'--','pg_isready','-U','postgres','-d','auth_db')

Write-Host '--- Historial de migraciones ---'
$sqlHistory = 'SELECT installed_rank,version,description,checksum,success FROM flyway_schema_history ORDER BY installed_rank;'
K @('-n',$ns,'exec',$pod,'--','psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','auth_db','-c',$sqlHistory)
Write-Host '--- Estructura de credentials ---'
K @('-n',$ns,'exec',$pod,'--','psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','auth_db','-c','\d+ public.credentials')

if (-not $AplicarReparacion) {
    Write-Host 'Modo diagnóstico: NO se ha cambiado la base de datos.'
    Write-Host 'Compare la estructura con V1__initial_schema.sql, incluidos PK, UNIQUE, NOT NULL y tipos.'
    Write-Host 'Si coinciden, invoque -AplicarReparacion para hacer backup y reparar SOLO el checksum indicado.'
    exit 0
}

# Validar columnas, tipos y nulabilidad de V1 antes de cualquier cambio.
$schemaCheck = @'
WITH expected(name, typ, nullable) AS (
 VALUES
 ('id','uuid','NO'),
 ('username','character varying','NO'),
 ('email','character varying','NO'),
 ('password_hash','character varying','NO'),
 ('role','character varying','NO'),
 ('created_at','timestamp with time zone','NO')
), actual AS (
 SELECT column_name, data_type, is_nullable, character_maximum_length
 FROM information_schema.columns
 WHERE table_schema='public' AND table_name='credentials'
), constraints_ok AS (
 SELECT EXISTS (
  SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid
  JOIN pg_namespace n ON n.oid=t.relnamespace
  WHERE n.nspname='public' AND t.relname='credentials' AND c.contype='p'
  AND pg_get_constraintdef(c.oid)='PRIMARY KEY (id)'
 ) AS pk,
 EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='credentials' AND indexdef LIKE 'CREATE UNIQUE INDEX%' AND indexdef LIKE '%(username)%') AS uq_username,
 EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='credentials' AND indexdef LIKE 'CREATE UNIQUE INDEX%' AND indexdef LIKE '%(email)%') AS uq_email
)
SELECT CASE WHEN
 (SELECT COUNT(*) FROM actual)=6
 AND (SELECT COUNT(*) FROM expected e JOIN actual a ON e.name=a.column_name AND e.typ=a.data_type AND e.nullable=a.is_nullable)=6
 AND (SELECT COUNT(*) FROM actual WHERE (column_name='username' AND character_maximum_length=60) OR (column_name='email' AND character_maximum_length=120) OR (column_name='password_hash' AND character_maximum_length=100) OR (column_name='role' AND character_maximum_length=20))=4
 AND (SELECT pk AND uq_username AND uq_email FROM constraints_ok)
 THEN 'OK' ELSE 'NO_COINCIDE' END;
'@
$result = (& kubectl -n $ns exec $pod -- psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d auth_db -c $schemaCheck)
if ($LASTEXITCODE -ne 0 -or ($result.Trim() -ne 'OK')) { throw "Esquema NO coincide con V1. No reparar. Resultado: $result" }

# Backup físico lógico PostgreSQL: se crea en Pod y copia a Windows antes de reparar.
New-Item -ItemType Directory -Force -Path $DestinoBackup | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$remote = "/tmp/auth-db-before-flyway-$stamp.dump"
$local = Join-Path $DestinoBackup "auth-db-before-flyway-$stamp.dump"
try {
    K @('-n',$ns,'exec',$pod,'--','pg_dump','-U','postgres','-d','auth_db','-Fc','-f',$remote)
    K @('-n',$ns,'cp',"${pod}:$remote",$local)
    if (-not (Test-Path $local) -or (Get-Item $local).Length -le 0) { throw 'Backup vacío o inexistente' }
    Write-Host "Backup guardado en $local"
} finally {
    & kubectl -n $ns exec $pod -- rm -f $remote | Out-Null
}

Write-Warning 'Se actualizará SOLAMENTE el checksum V1 del historial Flyway tras verificar esquema y crear backup.'
$confirmation = Read-Host 'Escriba REPARAR-V1 para confirmar'
if ($confirmation -cne 'REPARAR-V1') { throw 'Operación cancelada: no se modificó el historial.' }

# Transacción y precondiciones estrictas: debe existir exactamente UNA V1 exitosa con checksum anterior.
$repair = @"
DO `$`$
DECLARE n integer;
BEGIN
 SELECT COUNT(*) INTO n FROM flyway_schema_history
 WHERE version = '1' AND checksum = $expectedOld AND success = true;
 IF n <> 1 THEN RAISE EXCEPTION 'V1 no coincide con el checksum anterior esperado'; END IF;
 UPDATE flyway_schema_history SET checksum = $expectedNew
 WHERE version = '1' AND checksum = $expectedOld AND success = true;
END;
`$`$;
"@
K @('-n',$ns,'exec',$pod,'--','psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','auth_db','-c',$repair)
Write-Host 'Checksum de V1 actualizado; ninguna tabla de aplicación fue eliminada o recreada.'
Write-Host 'Ahora ejecutar el workflow completo (re-run NO: el commit de imagen puede ser antiguo) o kubectl rollout restart deployment/auth-service.'
Write-Host "Backup disponible: $local"
