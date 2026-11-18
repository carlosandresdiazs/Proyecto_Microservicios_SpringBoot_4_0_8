# Despliegue por SHA en Docker Desktop Kubernetes. Requiere PowerShell 7 y kubectl.
# Conserva Secrets, bases de datos y volúmenes. No aplica manifests con etiquetas locales.
$ErrorActionPreference = 'Stop'
$namespace = 'proyecto-03'
$services = @('auth-service', 'user-service', 'product-service', 'payment-service', 'api-gateway')
$updated = [System.Collections.Generic.List[string]]::new()
$failedService = $null

function Invoke-Kubectl {
    param([Parameter(Mandatory = $true)][string[]] $Arguments)
    & kubectl @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl falló (código $LASTEXITCODE): $($Arguments -join ' ')"
    }
}

function Show-Diagnostics {
    param([string] $Service)
    Write-Host "===== Diagnóstico de $Service ====="
    & kubectl -n $namespace get deployment $Service -o wide
    & kubectl -n $namespace describe deployment $Service
    & kubectl -n $namespace get pods -l "app=$Service" -o wide
    & kubectl -n $namespace get events --sort-by=.lastTimestamp --field-selector type=Warning

    # Logs de pods actuales (incluye pods no Ready); las fallas de arranque
    # deben inspeccionarse ANTES de intentar la reversión.
    $names = @(& kubectl -n $namespace get pods -l "app=$Service" -o 'jsonpath={range .items[*]}{.metadata.name}{"\n"}{end}')
    foreach ($pod in ($names -split "`n")) {
        $pod = $pod.Trim()
        if (-not $pod) { continue }
        Write-Host "===== Logs actuales: $pod ====="
        & kubectl -n $namespace logs $pod -c app --tail=120 --timestamps=true
        Write-Host "===== Logs previos (si existen): $pod ====="
        & kubectl -n $namespace logs $pod -c app --previous --tail=80
    }
}

if (-not $env:IMAGE_OWNER -or -not $env:IMAGE_SHA) {
    throw 'IMAGE_OWNER e IMAGE_SHA son obligatorios.'
}
if ($env:IMAGE_SHA -notmatch '^[0-9a-fA-F]{40}$') {
    throw 'IMAGE_SHA debe ser un SHA Git completo de 40 caracteres.'
}
$owner = $env:IMAGE_OWNER.ToLowerInvariant()
if ($owner -notmatch '^[a-z0-9][a-z0-9-]*$') {
    throw 'IMAGE_OWNER inválido para GHCR.'
}
$sha = $env:IMAGE_SHA.ToLowerInvariant()

$context = (& kubectl config current-context)
if ($LASTEXITCODE -ne 0 -or ($context.Trim() -ne 'docker-desktop')) {
    throw "El contexto del runner debe ser docker-desktop. Detectado: $context"
}
Invoke-Kubectl @('get', 'namespace', $namespace)
foreach ($secret in @('app-secrets', 'rsa-keys', 'keycloak-realm')) {
    Invoke-Kubectl @('-n', $namespace, 'get', 'secret', $secret, '-o', 'name')
}
foreach ($service in $services) {
    Invoke-Kubectl @('-n', $namespace, 'get', 'deployment', $service, '-o', 'name')
}

# Las imágenes privadas requieren un imagePullSecret ya vinculado al Pod o
# a su ServiceAccount. No creamos ni imprimimos tokens desde Actions.
if ($env:GHCR_PRIVATE -eq 'true') {
    Invoke-Kubectl @('-n', $namespace, 'get', 'secret', 'ghcr-pull-secret', '-o', 'name')
    Write-Host 'GHCR privado: confirme que el Deployment o ServiceAccount usa ghcr-pull-secret.'
}

try {
    foreach ($service in $services) {
        $failedService = $service
        $deployment = "deployment/$service"
        $image = "ghcr.io/$owner/${service}:$sha"
        $currentImage = (& kubectl -n $namespace get deployment $service -o 'jsonpath={.spec.template.spec.containers[0].image}')
        if ($LASTEXITCODE -ne 0) { throw "No se pudo consultar la imagen de $service" }
        if ($currentImage.Trim() -eq $image) {
            Write-Host "Sin cambios en $service ($image); verificando disponibilidad."
        } else {
            Write-Host "Actualizando $service -> $image"
            # Una sola mutación del Pod template: evita revisiones innecesarias.
            # El SHA es único, por lo que IfNotPresent es suficiente.
            Invoke-Kubectl @('-n', $namespace, 'set', 'image', $deployment, "app=$image")
            $updated.Add($service)
        }
        Invoke-Kubectl @('-n', $namespace, 'rollout', 'status', $deployment, '--timeout=600s')
        Invoke-Kubectl @('-n', $namespace, 'get', 'deployment', $service, '-o', 'wide')
    }
    Write-Host 'Despliegue de los cinco microservicios completado.'
    Invoke-Kubectl @('-n', $namespace, 'get', 'deployments', '-o', 'wide')
} catch {
    $reason = $_
    Write-Warning "Falló deploy-local en $failedService : $reason"
    if ($failedService) {
        try { Show-Diagnostics -Service $failedService } catch { Write-Warning "Diagnóstico incompleto: $_" }
    }
    # Por defecto, conservar el estado fallido y los logs para diagnóstico.
    # Activar AUTO_ROLLBACK=true si se quiere restaurar los servicios actualizados.
    if ($env:AUTO_ROLLBACK -eq 'true') {
        $toRollback = $updated.ToArray()
        [array]::Reverse($toRollback)
        foreach ($service in $toRollback) {
            Write-Warning "Intentando reversión de $service"
            & kubectl -n $namespace rollout undo "deployment/$service"
            if ($LASTEXITCODE -ne 0) { Write-Warning "No fue posible revertir $service" }
        }
    } else {
        Write-Warning 'Reversión automática deshabilitada; inspeccione el Pod antes de restaurar la revisión.'
    }
    throw $reason
}

