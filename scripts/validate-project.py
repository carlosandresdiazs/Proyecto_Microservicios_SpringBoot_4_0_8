#!/usr/bin/env python3
"""Validaciones estáticas: no reemplazan Flyway validate ni pruebas Kubernetes."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
collection = json.loads((root / 'postman/Proyecto03_Kubernetes_REST.postman_collection.json').read_text(encoding='utf-8'))
requests = []

def walk(items):
    for item in items:
        if 'item' in item:
            walk(item['item'])
        if 'request' in item:
            requests.append(item)

walk(collection['item'])
assert requests, 'No hay peticiones Postman'
ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
pom = ET.parse(root / 'pom.xml').getroot()
assert pom.find('m:parent/m:version', ns).text == '4.0.8', 'Spring Boot debe ser 4.0.8'
assert pom.find('m:properties/m:java.version', ns).text == '21', 'Java debe ser 21'
services = ['api-gateway', 'auth-service', 'user-service', 'product-service', 'payment-service']
assert {x.text for x in pom.findall('m:modules/m:module', ns)} == set(services)
for service in services:
    module = ET.parse(root / service / 'pom.xml').getroot()
    assert module.find('m:parent/m:artifactId', ns).text == 'taller-03-microservices'
for item in requests:
    url = item['request']['url']
    assert (url.get('raw') if isinstance(url, dict) else url), f'URL vacía: {item["name"]}'
migrations = {
    'auth-service': 'V1__create_credentials.sql',
    'user-service': 'V1__create_user_profiles.sql',
    'product-service': 'V1__create_products.sql',
    'payment-service': 'V1__create_payments.sql',
}
for service, filename in migrations.items():
    directory = root / service / 'src/main/resources/db/migration'
    assert (directory / filename).is_file(), f'Falta migración: {service}/{filename}'
    versions = list(directory.glob('V1__*.sql'))
    assert len(versions) == 1, f'{service}: debe existir solo UNA V1, encontradas {versions}'
assert (root / '.github/workflows/ci-cd.yml').is_file()
assert '!**/src/main/resources/db/migration/*.sql' in (root / '.gitignore').read_text(encoding='utf-8')
print(f'Validación estática OK: {len(requests)} peticiones; migraciones V1 con nombres históricos. Checksums pendientes de validar contra PostgreSQL.')
