# Inicio rápido: GitHub + GitHub Actions + Docker Desktop Kubernetes

## 1. Publicar en GitHub

El contenido de esta carpeta fue preparado para publicarse sin el directorio `.git` heredado ni las carpetas `target/`.

1. Crear un repositorio **privado y vacío** con nombre `Proyecto_Microservicios_SpringBoot_4_0_8` en https://github.com/new en la cuenta `carlosandresdiazs`. No seleccionar README, .gitignore ni licencia inicial.
2. Desde VS Code: `Terminal > New Terminal`, usando **Git Bash** en la raíz extraída.
3. Ejecutar:

```bash
git init
git branch -M main
git add .
git status --short
git diff --cached --name-only
git commit -m "Proyecto Spring Boot 4.0.8 y CI/CD Kubernetes"
git remote add origin https://github.com/carlosandresdiazs/Proyecto_Microservicios_SpringBoot_4_0_8.git
git push -u origin main
```

Confirme antes del commit que no haya credenciales, claves privadas, .env, kubeconfig o respaldos. Nunca suba `secrets/`.

## 2. Primera instalación Kubernetes (una única vez)

En **Git Bash** con Docker Desktop y Kubernetes habilitado:

```bash
kubectl config current-context
bash scripts/generate-rsa-keys.sh
bash scripts/build-images.sh
bash scripts/k8s-setup.sh
kubectl -n proyecto-03 get deployments,pods,pvc,secrets
```

El contexto debe ser `docker-desktop`. El script de instalación pide contraseñas interactivamente y crea Kubernetes Secrets. Conservar volúmenes y Secrets durante futuras actualizaciones. Realizar respaldo si ya hay datos.

## 3. Activar runner local Windows

En GitHub, abrir el repositorio > **Settings > Actions > Runners > New self-hosted runner** y elegir **Windows x64**. Seguir las instrucciones que GitHub muestra para instalarlo y registrarlo; no compartir el token. Añadir la etiqueta personalizada `docker-desktop`. Iniciar con la cuenta Windows que puede ejecutar `docker` y `kubectl`.

**Requisitos:** equipo encendido, conexión a Internet, Docker Desktop y Kubernetes activos. En repo **Settings > Actions > General**, comprobar que Actions esté permitido y que el job pueda publicar paquetes con `GITHUB_TOKEN`.

## 4. Flujo automático ya configurado

Archivo `.github/workflows/ci-cd.yml`:
- En pull requests hacia main: Maven verify y validación estática.
- En push a main: CI, construcción y publicación de 5 imágenes en GitHub Container Registry (GHCR).
- En runner Windows con etiqueta docker-desktop: `docker pull`, `kubectl set image` y `kubectl rollout status`.

**Aviso importante sobre GHCR privado:** el inicio de sesión Docker del runner no necesariamente concede al *kubelet* de Kubernetes permiso para descargar imágenes privadas. Si los pods muestran `ImagePullBackOff`, configure en Kubernetes un `imagePullSecret` con credenciales de solo lectura para GHCR y agréguelo al `ServiceAccount` de los deployments, o publique las imágenes en un paquete de visibilidad pública si el laboratorio lo permite. No guarde tokens en Git ni confíe en que `GITHUB_TOKEN` siga vigente tras finalizar el workflow. Las imágenes también pueden necesitar ser accesibles desde el almacén de imágenes utilizado por Kubernetes, que no siempre es el mismo que el de Docker Desktop.

## 5. Verificar

En GitHub: **Actions > CI/CD - Microservicios Kubernetes**. En terminal:

```bash
kubectl -n proyecto-03 get pods,deploy
kubectl -n proyecto-03 rollout status deploy/api-gateway --timeout=300s
kubectl -n proyecto-03 get pods -o wide
kubectl -n proyecto-03 port-forward svc/api-gateway 8080:8080
```

En otra terminal, `curl http://localhost:8080/actuator/health`. Para confirmar un cambio, edite código, haga commit y `git push origin main`, luego compruebe el nuevo workflow y el hash de imagen desplegada.

## Limitaciones de verificación

Se ejecutó `python3 scripts/validate-project.py` correctamente en la copia preparada. No se ejecutó `mvn verify`, ni `docker build`, ni `kubectl apply`, ya que este entorno no tiene esos programas o acceso al equipo Windows. Tampoco se creó el repositorio remoto: no existe un destino accesible en la conexión GitHub de esta sesión.
