#requires -Version 7.0
<#
Correcciones conservadoras para Proyecto_Microservicios_SpringBoot_4_0_8.
Ejecutar desde la raiz del repositorio con: pwsh -File ./corregir_despliegue.ps1
No modifica migraciones SQL, credenciales, Secrets, PVC ni bases de datos.
#>
$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
if (-not (Test-Path (Join-Path $root 'pom.xml'))) { throw 'Ejecute este script desde la raiz del proyecto (donde se encuentra pom.xml).' }
$target = Join-Path $root 'scripts/deploy-local.ps1'
if (-not (Test-Path $target)) { throw "No existe $target" }
$content = [System.IO.File]::ReadAllText($target)
$old = 'Invoke-Kubectl @('
$new = 'Invoke-Kubectl -Arguments @('
$count = ([regex]::Matches($content, [regex]::Escape($old))).Count
if ($count -gt 0) { $content = $content.Replace($old, $new) }
$oldExit = "if (-not `$?) { throw 'Preflight Flyway fallido.' }"
$newExit = 'if ($LASTEXITCODE -ne 0) { throw "Preflight Flyway fallido (exit=$LASTEXITCODE)." }'
if ($content.Contains($oldExit)) { $content = $content.Replace($oldExit,$newExit) }
[System.IO.File]::WriteAllText($target, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "Revisado: scripts/deploy-local.ps1 ($count llamadas modificadas)"
$modules = @('api-gateway','auth-service','user-service','product-service')
foreach ($module in $modules) {
  $path = Join-Path $root "$module/Dockerfile"
  if (-not (Test-Path $path)) { throw "Falta $path" }
  $dockerfile = [System.IO.File]::ReadAllText($path)
  $dockerfile = $dockerfile.Replace('maven:3.9.11-eclipse-temurin-25','maven:3.9.11-eclipse-temurin-21').Replace('eclipse-temurin:25-jre','eclipse-temurin:21-jre')
  [System.IO.File]::WriteAllText($path,$dockerfile,[System.Text.UTF8Encoding]::new($false))
  Write-Host "Revisado: $module/Dockerfile"
}
Write-Host 'Archivos corregidos. Revisar git diff antes de crear commit.'
Write-Host 'Validacion sugerida: python scripts/validate-project.py; mvn -B clean verify'
Write-Host 'Antes de desplegar: pwsh -File scripts/check-flyway-history.ps1'
