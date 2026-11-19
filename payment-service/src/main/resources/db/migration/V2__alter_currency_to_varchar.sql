-- V2: Alinear la columna currency con el modelo JPA.
-- Ejecutar mediante Flyway después de reconciliar V1.

ALTER TABLE public.payments
ALTER COLUMN currency TYPE VARCHAR(3)
USING currency::VARCHAR(3);