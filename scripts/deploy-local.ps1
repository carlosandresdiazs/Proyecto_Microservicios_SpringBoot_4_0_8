# PowerShell 7 (pwsh) - ejecutar desde la raíz del repositorio.
# Para GHCR privado, crear antes un Secret imagePullSecret permanente (ver guía).
$ErrorActionPreference = 'Stop'
$namespace = 'proyecto-03'
$services = @('api-gateway','auth-service','user-service','product-service','payment-service')

function Invoke-Kubectl {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    & kubectl @Arguments
    if ($LASTEXITCODE -ne 0) { throw "kubectl falló: $($Arguments -join ' ')" }
}

if (-not $env:IMAGE_OWNER -or -not $env:IMAGE_SHA) {
    throw 'Faltan variables IMAGE_OWNER e IMAGE_SHA.'
}
if ($env:IMAGE_SHA -notmatch '^[0-9a-fA-F]{40}$') {
    throw 'IMAGE_SHA debe ser el SHA completo de 40 caracteres de Git.'
}
$owner = $env:IMAGE_OWNER.ToLowerInvariant()
if ($owner -notmatch '^[a-z0-9][a-z0-9-]*$') { throw 'IMAGE_OWNER inválido.' }
$context = (& kubectl config current-context).Trim()
if ($LASTEXITCODE -ne 0 -or $context -ne 'docker-desktop') {
    throw "El contexto debe ser docker-desktop. Actual: $context"
}
Invoke-Kubectl @('get', 'namespace', $namespace)
foreach ($secret in @('app-secrets','rsa-keys','keycloak-realm')) {
    Invoke-Kubectl @('-n', $namespace, 'get', 'secret', $secret)
}
foreach ($service in $services) {
    Invoke-Kubectl @('-n', $namespace, 'get', 'deployment', $service)
}

# Kubernetes obtiene las imágenes del registro. No dependemos de que
# 'docker pull' y Kubernetes compartan exactamente el mismo image store.
# Los tags SHA son inmutables por convención: evitar sobrescribir el mismo tag.
$updated = [System.Collections.Generic.List[string]]::new()
try {
    foreach ($service in $services) {
        $image = "ghcr.io/$owner/${service}:$($env:IMAGE_SHA.ToLowerInvariant())"
        Write-Host "Actualizando $service -> $image"
        # Si GHCR es privado, se requiere imagePullSecrets: ghcr-pull-secret.
        # Si las imágenes son públicas, no es necesario configurarlo.
        if ($env:GHCR_PRIVATE -eq 'true') {
            Invoke-Kubectl @('-n', $namespace, 'get', 'secret', 'ghcr-pull-secret')
            Invoke-Kubectl @('-n', $namespace, 'patch', 'deployment', $service,
                '--type=strategic', '-p', '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ghcr-pull-secret"}]}}}}')
        }
        Invoke-Kubectl @('-n', $namespace, 'set', 'image', "deployment/$service", "app=$image")
        $updated.Add($service)
        Invoke-Kubectl @('-n', $namespace, 'patch', 'deployment', $service,
            '--type=strategic', '-p', '{"spec":{"template":{"spec":{"containers":[{"name":"app","imagePullPolicy":"Always"}]}}}}')
        Invoke-Kubectl @('-n', $namespace, 'rollout', 'status', "deployment/$service", '--timeout=300s')
    }
    Write-Host 'Despliegue finalizado correctamente.'
    Invoke-Kubectl @('-n', $namespace, 'get', 'deployments', '-o', 'wide')
}
catch {
    Write-Warning "Despliegue fallido: $_"
    # Revierte el historial del Deployment si existe revisión anterior.
    foreach ($service in $updated) {
        Write-Warning "Revisar/revertir $service"
        & kubectl -n $namespace rollout undo "deployment/$service"
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "No fue posible revertir $service automáticamente."
        }
    }
    throw
}
