# Integración Postman + Spring Boot 4.0.8 + Kubernetes (Proyecto 03)

## Alcance verificado directamente contra el código

- **Gateway** `http://localhost:8080`: enrutamiento `/api/auth/**`, `/api/users/**`, `/api/products/**`, `/api/payments/**`.
- **auth-service**: `POST /api/auth/register`, `POST /api/auth/login`; genera JWT RSA propio.
- **user-service**: `POST /api/users`, `GET /api/users/me`, `GET /api/users`, `GET /api/users/{id}`, `PUT /api/users/{id}`, `DELETE /api/users/{id}`; borrado y listado solo ADMIN.
- **product-service**: `POST/GET /api/products`, `GET/PUT/DELETE /api/products/{id}`; escritura solo ADMIN.
- **payment-service**: `POST/GET /api/payments`, `GET /api/payments/{id}`, `POST /api/payments/webhooks/sandbox`; OAuth Keycloak, audiencia `payments-api`, scopes `payments:read`/`payments:write`.
- Los controladores de pagos **no implementan PUT o DELETE**. No se añadieron endpoints ficticios.

## Preparación sin alterar tu despliegue

1. Si la aplicación está desplegada, **no** regeneres contraseñas, Secrets, claves RSA ni PVC. Valida `kubectl -n proyecto-03 get pods,svc,pvc` y `bash scripts/postman-check.sh`.
2. En dos terminales Git Bash distintas deja activos `kubectl -n proyecto-03 port-forward svc/api-gateway 8080:8080` y `kubectl -n proyecto-03 port-forward svc/keycloak 8085:8080`.
3. En Postman > Import importa `Proyecto03_Kubernetes_REST.postman_collection.json` y `Proyecto03_Kubernetes_Local.postman_environment.json`, y selecciona el entorno local.
4. Ejecuta primero `00 - Kubernetes y salud`, luego `01 - Autenticacion JWT RSA`: **Registrar usuario** y **Login usuario**. La colección guarda los tokens y los ID automáticamente en variables del entorno.
5. Ejecuta las pruebas de usuario con JWT `userToken`. Para escrituras de productos y operaciones ADMIN de usuarios, es necesario iniciar sesión con un usuario ADMIN existente; **no hay ADMIN automático** en Kubernetes (`DEMO_USERS_ENABLED=false`). El registro público crea usuarios con rol USER. No conviertas el registro público en ADMIN ni actives cuentas de demostración con claves conocidas.
6. Para pagos, en Keycloak > realm `proyecto03` > Clients > `payments-machine` > Credentials consulta el secreto del cliente, cópialo **solo a una variable local** `keycloakClientSecret` (marcada secret). Ejecuta `Obtener token Keycloak POST` y después las operaciones de pagos. El secret del cliente se genera durante `k8s-setup.sh`; no se incluye aquí. Si no existe, verifica primero el realm importado.
7. No guardes ni sincronices/exportes entornos Postman con tokens o secretos reales. Borra secretos antes de compartir resultados. Los ejemplos usan datos de laboratorio exclusivamente.

## Orden de pruebas y límites

- La colección está organizada en carpetas: `00` salud, `01` autenticación, `02` usuarios, `03` productos, `04` pagos, `05` autorización.
- **No ejecutes toda la colección de una vez sin preparación**: las llamadas ADMIN dependen de una cuenta ADMIN ya existente; el borrado de usuarios modifica datos; Keycloak necesita su secreto y port-forward. Usa el Collection Runner por carpeta según el escenario.
- En `02` la llamada DELETE requiere ADMIN. En `03` las llamadas POST, PUT y DELETE requieren ADMIN.
- En `04` el token `client_credentials` corresponde a la cuenta de servicio `payments-machine`, no al JWT de `auth-service`. La prueba de idempotencia repite la misma clave y el mismo `orderId`.
- Para el endpoint `POST /api/payments/webhooks/sandbox` la firma es `HMAC-SHA256(secret=WEBHOOK_SECRET, bytes exactos del body)` enviada como `X-Sandbox-Signature` hexadecimal. No se incluye una petición auto-firmada porque revelar el secreto HMAC a Postman aumenta el riesgo. Se puede probar con un generador local y un secreto efímero exclusivo de laboratorio.
- La llamada a Keycloak usa `http://localhost:8085` porque el YAML de Keycloak publica ese issuer y el payment-service valida exactamente ese valor. En otro entorno la configuración debe adaptarse.
- Las pruebas negativas incluyen HTTP 401, 403 y 400 según código; los resultados concretos deben verificarse en ejecución.

## Diagnóstico

```bash
kubectl config use-context docker-desktop
kubectl -n proyecto-03 get pods,svc,pvc
kubectl -n proyecto-03 get endpoints
kubectl -n proyecto-03 logs deployment/api-gateway --tail=100
kubectl -n proyecto-03 logs deployment/payment-service --tail=100
```

La colección y el entorno se validaron **estructuralmente como JSON**, pero no se realizaron llamadas Postman/Kubernetes reales desde este entorno. No hay garantía de que los Pods estén funcionando en tu computador hasta ejecutar las pruebas.
