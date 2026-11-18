# Corrección conservadora: migraciones Flyway y despliegue local

## Alcance y estado
Este paquete se basó en la rama `main` del proyecto revisada el 18-11-2026. Corrige el **nombre** de V1 en los módulos `user-service`, `product-service` y `payment-service`, y ajusta la validación estática. **No garantiza** la coincidencia de checksum: según GitHub Actions #21, PostgreSQL registra SQL histórico distinto al contenido `V1__initial_schema.sql` actual. No se cambia ninguna tabla, PVC, Secret ni el historial de Flyway automáticamente.

## Pasos
1. Desde la raíz del repositorio, ejecutar `pwsh -File scripts/backup-postgres.ps1` y conservar los respaldos fuera de Git. Revisar que los cuatro `.dump` existan y probar una restauración en una base aislada antes de intervenir datos importantes.
2. Copiar las tres nuevas migraciones y `scripts/validate-project.py` desde el ZIP, y eliminar de esos tres módulos los anteriores `V1__initial_schema.sql`. No modificar la V1 de auth-service.
3. Ejecutar `python scripts/validate-project.py`.
4. Ejecutar `pwsh -File scripts/check-flyway-history.ps1` desde la raíz. Si falla checksum, **NO desplegar**.
5. Conseguir el SQL exacto de las migraciones históricas (`V1__create_user_profiles.sql`, `V1__create_products.sql`, `V1__create_payments.sql`) desde una copia original, imagen histórica, o respaldo de código. Sustituir las V1 propuestas por esos originales y volver a ejecutar el chequeo.
6. Si no existe código histórico, comparar los DDL reales con los SQL deseados (`psql -c '\d+ user_profiles'`, `products`, `payments` y `webhook_events`). En entorno de laboratorio y tras respaldo comprobado, evaluar ejecutar **Flyway repair oficial** con la misma configuración de localizaciones, esquema y versión de Flyway utilizada por el servicio. `repair` debe seguir una revisión manual; cambia metadatos, no las tablas. Si difieren los DDL, preparar nuevas migraciones V2 y un plan de reconciliación. No ejecutar UPDATE directo sobre `flyway_schema_history`.
7. Tras aprobar todos los checks, publicar cambios: `git add -A ...`, `git commit`, `git push origin main`. Ejecutar CI/CD y comprobar `kubectl -n proyecto-03 get deployments,pods -o wide`.

## Consultas SQL de diagnóstico (solo lectura)
```powershell
kubectl -n proyecto-03 exec deployment/users-db -- psql -U postgres -d users_db -c "SELECT version,description,script,checksum,success FROM flyway_schema_history;"
kubectl -n proyecto-03 exec deployment/products-db -- psql -U postgres -d product_db -c "SELECT version,description,script,checksum,success FROM flyway_schema_history;"
kubectl -n proyecto-03 exec deployment/payments-db -- psql -U payments_app -d payments_db -c "SELECT version,description,script,checksum,success FROM flyway_schema_history;"
```

## Riesgos y precauciones
- El archivo `k8s/03-applications.yaml` existente ya contiene las sondas y conserva Secrets; reaplicarlo durante un rollout puede restaurar imágenes locales `proyecto03/*:3.1`. No reaplicarlo en un despliegue GHCR.
- `deploy-local.ps1` actual verifica el historial antes de desplegar. Mantener esa protección; no silenciar el error.
- Si GHCR es privado, configurar `imagePullSecrets` en los Pods o ServiceAccount antes de desplegar.
- No subir la carpeta `backups/` a Git; añadirla a `.gitignore` si no está ignorada. Los respaldos podrían contener datos sensibles.
- El respaldo es una medida de protección, no una garantía de recuperación hasta probar restauración.
