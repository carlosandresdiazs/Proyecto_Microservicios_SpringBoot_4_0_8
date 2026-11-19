#!/usr/bin/env python3
"""Parche conservador basado en los archivos revisados de la rama main (19 nov 2026).
Ejecutar desde la raíz del repositorio. No modifica bases de datos ni Secrets.
"""
from pathlib import Path
import shutil
import sys

root = Path.cwd()
if not (root / 'pom.xml').exists() or not (root / 'auth-service').is_dir():
    sys.exit('ERROR: ejecutar desde la carpeta raíz del proyecto (donde está pom.xml).')

changed = []
def patch(path, old, new):
    file = root / path
    s = file.read_text(encoding='utf-8')
    if new in s:
        print('Ya corregido:', path)
        return
    if s.count(old) != 1:
        sys.exit(f'ERROR: no coincide contenido esperado en {path}. No se modificó este archivo.')
    backup = file.with_suffix(file.suffix + '.bak-local')
    if not backup.exists(): shutil.copy2(file, backup)
    file.write_text(s.replace(old, new), encoding='utf-8')
    changed.append(path)

patch('product-service/src/main/java/edu/unibague/products/dto/ProductRequest.java',
      '@NotNull @DecimalMin("0.00") BigDecimal price,',
      '@NotNull @DecimalMin("0.00") @Digits(integer=10, fraction=2) BigDecimal price,')

path = 'api-gateway/src/main/java/edu/unibague/gateway/filter/CorrelationIdFilter.java'
patch(path,
      'if (correlationId == null || correlationId.isBlank()) {',
      'if (correlationId == null || !correlationId.matches("[A-Za-z0-9._-]{1,64}")) {')

# Añadir manejo de conflictos de claves únicas por concurrencia en servicios con tablas UNIQUE.
for service, package in [('auth-service', 'auth'), ('user-service', 'users')]:
    path = f'{service}/src/main/java/edu/unibague/{package}/exception/GlobalExceptionHandler.java'
    patch(path,
          'import org.springframework.http.HttpStatus;',
          'import org.springframework.dao.DataIntegrityViolationException;\nimport org.springframework.http.HttpStatus;')
    patch(path,
          '    @ExceptionHandler(MethodArgumentNotValidException.class)',
          '    @ExceptionHandler(DataIntegrityViolationException.class)\n'
          '    public ResponseEntity<ApiError> integrityViolation(DataIntegrityViolationException ex, HttpServletRequest request) {\n'
          '        return build(HttpStatus.CONFLICT, "Conflicto de integridad de datos", request.getRequestURI(), Map.of());\n'
          '    }\n\n'
          '    @ExceptionHandler(MethodArgumentNotValidException.class)')

# La prueba del DTO requiere el proveedor de validación ya incluido en starter-validation.
test_dir = root / 'product-service/src/test/java/edu/unibague/products/dto'
test_dir.mkdir(parents=True, exist_ok=True)
test = test_dir / 'ProductRequestValidationTest.java'
if not test.exists():
    test.write_text('''package edu.unibague.products.dto;

import jakarta.validation.Validation;
import jakarta.validation.Validator;
import org.junit.jupiter.api.Test;
import java.math.BigDecimal;
import static org.junit.jupiter.api.Assertions.*;

class ProductRequestValidationTest {
    private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

    @Test
    void acceptsValidPrice() {
        var req = new ProductRequest("Producto", "Descripcion", new BigDecimal("123.45"), 10);
        assertTrue(validator.validate(req).isEmpty());
    }

    @Test
    void rejectsTooManyDigitsAndFractionalPlaces() {
        assertFalse(validator.validate(new ProductRequest("Producto", "Descripcion", new BigDecimal("12345678901.00"), 1)).isEmpty());
        assertFalse(validator.validate(new ProductRequest("Producto", "Descripcion", new BigDecimal("12.345"), 1)).isEmpty());
    }
}
''', encoding='utf-8')
    changed.append(str(test.relative_to(root)))

# product-service no tenía dependencia de test en el POM revisado.
patch('product-service/pom.xml',
      ' </dependencies>',
      '  <dependency><groupId>org.springframework.boot</groupId>\n'
      '   <artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>\n'
      ' </dependencies>')

print('\nArchivos corregidos/agregados:')
for p in sorted(set(changed)): print(' -', p)
print('\nAhora ejecutar: mvn -B clean verify')
print('Revisar diferencias con: git diff --check; git diff')
print('No ejecutar despliegue hasta validar Flyway y Kubernetes.')
