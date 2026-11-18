# Actualización de deploy-local (GitHub Actions + Docker Desktop Kubernetes)

## Archivos incluidos

- `.github/workflows/ci-cd.yml` sustituye al workflow existente.
- `scripts/deploy-local.ps1` se agrega como script nuevo.
- No sobrescribir `k8s/03-applications.yaml` en la instalación inicial: sigue usando imágenes locales `proyecto03/*:3.1`. El job `deploy-local` actualiza en vivo esos Deployments a las imágenes GHCR con SHA.

## Configuración del runner Windows

1. Instalar y habilitar Kubernetes en Docker Desktop.
2. Abrir PowerShell 7 (`pwsh`) y verificar `kubectl config use-context docker-desktop` y `kubectl get nodes`.
3. Registrar un GitHub Actions runner **self-hosted** para este repositorio con etiquetas `self-hosted`, `Windows`, `X64` y `docker-desktop`.
4. Mantener encendido el runner y garantizar que el usuario que ejecuta el servicio tenga acceso a la configuración de `kubectl` y a Docker Desktop.
5. Inicializar el clúster una sola vez mediante `bash scripts/generate-rsa-keys.sh`, `bash scripts/build-images.sh` y `bash scripts/k8s-setup.sh` desde Git Bash (o comprobar que el namespace, Secrets y Deployments ya existen).

## Importante: permisos GHCR

El workflow publica paquetes con `GITHUB_TOKEN`, pero el runtime Kubernetes debe poder descargar los paquetes de forma independiente. Dos opciones:

- **GHCR público:** en GitHub, configurar cada paquete de imagen como público. Kubernetes podrá hacer `pull` sin credenciales.
- **GHCR privado:** crear un token de acceso a paquetes de duración apropiada y almacenar credenciales solo en un Secret de Kubernetes; no hacer commit de contraseñas. En PowerShell, con `GHCR_USER` y `GHCR_PAT` definidos de forma segura, ejecutar:

```powershell
kubectl -n proyecto-03 create secret docker-registry ghcr-pull-secret `
  --docker-server=ghcr.io `
  --docker-username="$env:GHCR_USER" `
  --docker-password="$env:GHCR_PAT"
```

Para habilitar la vinculación automática de `imagePullSecrets`, definir una variable de repositorio o entorno `GHCR_PRIVATE=true` y añadir en `deploy-local`:

```yaml
        env:
          IMAGE_OWNER: ${{ github.repository_owner }}
          IMAGE_SHA: ${{ github.sha }}
          GHCR_PRIVATE: 'true'
```

Nota: para despliegues privados sin ese indicador, la descarga puede terminar en `ImagePullBackOff`. Las credenciales del `docker/login-action` no son automáticamente credenciales para Kubernetes.

## Verificaciones

Tras ejecutar `deploy-local`:

```powershell
kubectl -n proyecto-03 get deployments,pods -o wide
kubectl -n proyecto-03 get pods
kubectl -n proyecto-03 describe pod <NOMBRE-POD>
kubectl -n proyecto-03 get deployment api-gateway -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl -n proyecto-03 rollout status deployment/api-gateway --timeout=300s
kubectl -n proyecto-03 port-forward svc/api-gateway 8080:8080
```

En otra terminal: `curl.exe http://localhost:8080/actuator/health`.

## Consideraciones

- Los cinco Dockerfile existentes usan Maven con contexto raíz y Java 25, compatibles con el job de construcción.
- No borrar PVC ni reinicializar Secrets para actualizar código.
- Si las imágenes son privadas, el clúster debe disponer de credenciales vigentes; los permisos `packages:read` del job no autorizan por sí solos al kubelet.
- El trabajo de GitHub Actions solo tendrá éxito si Maven compila, se publican las cinco imágenes, el runner local está conectado y los Pods pasan readiness.
- El mecanismo `rollout undo` intenta revertir imágenes anteriores, pero el resultado depende del historial de réplicas y de que las versiones anteriores estén accesibles.
