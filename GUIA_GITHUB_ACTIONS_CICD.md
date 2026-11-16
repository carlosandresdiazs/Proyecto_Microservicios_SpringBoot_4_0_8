# CI/CD de microservicios con GitHub Actions + Docker Desktop (Windows)

## Estado del código

La raíz `pom.xml` utiliza **Spring Boot 4.0.8**, Spring Cloud 2025.1.3 y Java 21; el código y la carpeta de entrega se identifican ahora como Spring Boot 4.0.8.

Se corrigió la definición de la clave de firma RSA en `RsaKeyConfig`: ahora se construye explícitamente el JWK RS256 con `kid=proyecto03-key` para el JWT de `auth-service`. Se incorporó una prueba JUnit para generar, firmar y verificar un token. También se incorporaron migraciones Flyway `V1__initial_schema.sql` para instalaciones nuevas. **Antes de aplicarlas a PVC con datos existentes, hacer copia de respaldo.** Las tablas existentes no se eliminan, pero cualquier incompatibilidad de esquema debe resolverse antes de desplegar.

## Primera instalación (solo una vez, equipo Windows)

1. Activar Kubernetes en Docker Desktop y comprobar `kubectl config current-context` = `docker-desktop`.
2. Abrir Git Bash en la carpeta raíz del proyecto:

```bash
bash scripts/generate-rsa-keys.sh
bash scripts/build-images.sh
bash scripts/k8s-setup.sh
```

3. Verificar `kubectl -n proyecto-03 get deploy,pods,pvc` y que se hayan creado `app-secrets`, `rsa-keys` y `keycloak-realm`. **Conservar los PVC, Secrets y claves RSA para despliegues sucesivos.**
4. Importar los dos archivos de `postman/Proyecto03_Kubernetes_*.json`; los secretos de las variables del entorno deben asignarse en Postman y nunca guardarse en Git.

## Publicación inicial en GitHub

Crear un repositorio privado **vacío** desde https://github.com/new. No habilitar README inicial ni añadir ficheros que pudieran producir un conflicto. Después, desde Git Bash en la raíz del proyecto:

```bash
git init
git branch -M main
git add .
git status --short
git commit -m "Corregir autenticacion y configurar CI CD Kubernetes"
git remote add origin https://github.com/TU_USUARIO/TU_REPOSITORIO.git
git push -u origin main
```

Antes del commit, confirmar que `git status` no incluya: `.env`, `secrets/`, `*.pem`, logs, contraseñas o archivos de respaldo. GitHub solicita autenticación segura (gestor de credenciales o SSH), no una contraseña de cuenta.

## Configurar el runner de despliegue **en el equipo con Docker Desktop**

GitHub Actions hospedado por GitHub **no puede ver** `docker-desktop` del PC. Se requiere que el PC esté **encendido**, conectado a la red y con Kubernetes activo. En GitHub: `Settings > Actions > Runners > New self-hosted runner` > Windows x64. Seguir exactamente las instrucciones mostradas para descargar y registrar el runner (sin compartir el token de registro). Asignar la etiqueta adicional **`docker-desktop`**. Iniciar el runner bajo la cuenta de Windows que tiene acceso a Docker Desktop y al contexto `kubectl docker-desktop`.

**Seguridad:** usar este runner únicamente con un repositorio de confianza; evitar contribuciones externas no revisadas y no permitir que los pull requests ejecuten tareas en el runner. El workflow solo ejecuta el job de despliegue en `push` a `main` o por ejecución manual desde `main`. Mantener Docker Desktop y el runner actualizados.

## Flujo automático

- Pull request hacia `main`: Java 21 + Maven `clean verify` + validaciones del contrato Postman (sin despliegue).
- Push a `main`: lo anterior y construcción/publicación de cinco imágenes `ghcr.io/usuario/servicio:SHA` en GHCR.
- Después: runner local Windows hace `docker login` con el token temporal del job, descarga imágenes por SHA, actualiza los cinco Deployments y exige `kubectl rollout status`.
- El pipeline **no reinstala PostgreSQL ni Keycloak, no recrea credenciales ni elimina volúmenes**.
- La publicación en GHCR depende de los permisos de paquetes de la organización/repositorio. El `GITHUB_TOKEN` del workflow tiene permisos `packages: write`, y el job local `packages: read`.

## Comprobación Postman

Abrir dos terminales Git Bash y mantenerlas abiertas:

```bash
kubectl -n proyecto-03 port-forward svc/api-gateway 8080:8080
kubectl -n proyecto-03 port-forward svc/keycloak 8085:8080
```

Importar `postman/Proyecto03_Kubernetes_REST.postman_collection.json` y `postman/Proyecto03_Kubernetes_Local.postman_environment.json` y seleccionar el entorno. Probar: registro → login → perfil con JWT → consultas; operaciones ADMIN requieren un ADMIN previamente aprovisionado de forma segura y **no** pueden ejecutarse con el usuario `USER` recién registrado. Los pagos requieren un token **OAuth de Keycloak** con audiencia `payments-api` y los scopes `payments:read` y `payments:write`; no sirve el JWT RSA de auth-service. La firma del webhook se genera con el HMAC secreto creado en Kubernetes.

Pruebas de sanidad:

```bash
kubectl -n proyecto-03 rollout status deploy/auth-service --timeout=300s
kubectl -n proyecto-03 rollout status deploy/api-gateway --timeout=300s
kubectl -n proyecto-03 logs deployment/auth-service --tail=100
```

**Limitación:** las comprobaciones estáticas y el unit test incorporado no sustituyen las llamadas Postman contra los cinco servicios y las bases reales; esas pruebas deben ejecutarse en el clúster. Si el repositorio o el runner son nuevos, la configuración inicial descrita arriba es necesaria antes del primer despliegue automático.
