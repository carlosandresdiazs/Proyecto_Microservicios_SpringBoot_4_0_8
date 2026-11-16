# Publicar este proyecto Spring Boot 4.0.8 en GitHub

**No se ha publicado automáticamente:** el acceso de GitHub disponible no incluye un repositorio de destino propio de este proyecto, y no se debe sobrescribir un repositorio ajeno.

1. Crea un repositorio **privado** y vacío en https://github.com/new (por ejemplo `Proyecto_Microservicios_SpringBoot_4_0_8`).
2. Extrae este ZIP y abre una terminal Git Bash dentro de la carpeta de proyecto.
3. Ejecuta estos comandos, cambiando `TU_USUARIO` por el propietario y `TU_REPOSITORIO` por el nombre creado:

```bash
git init
git branch -M main
git add .
git status --short
git check-ignore auth-service/src/main/resources/db/migration/V1__initial_schema.sql || true
git commit -m "Configurar Spring Boot 4.0.8 y pipeline CI/CD"
git remote add origin https://github.com/TU_USUARIO/TU_REPOSITORIO.git
git push -u origin main
```

El comando `git check-ignore` no debe mostrar el SQL de migración. Revisa `git status` antes del commit para confirmar que no incluya credenciales privadas, archivos `.env`, `.pem` ni copias de bases de datos.

Tras publicar, configura el self-hosted runner en tu PC Windows siguiendo `GUIA_GITHUB_ACTIONS_CICD.md`. El pipeline no puede desplegar por sí solo en tu Docker Desktop local sin un runner instalado y el clúster preparado.
