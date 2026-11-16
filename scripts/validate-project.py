#!/usr/bin/env python3
"""Static source/route/Postman checks; not a substitute for live integration tests."""
from pathlib import Path
import json, re, xml.etree.ElementTree as ET
root=Path(__file__).resolve().parent.parent
collection=json.loads((root/'postman/Proyecto03_Kubernetes_REST.postman_collection.json').read_text())
requests=[]
def walk(items):
    for item in items:
        if 'item' in item: walk(item['item'])
        if 'request' in item: requests.append(item)
walk(collection['item'])
assert requests, 'No Postman requests found'
ns={'m':'http://maven.apache.org/POM/4.0.0'}
pom=ET.parse(root/'pom.xml').getroot()
assert pom.find('m:parent/m:version',ns).text=='4.0.8', 'Spring Boot parent must be 4.0.8'
assert pom.find('m:properties/m:java.version',ns).text=='21', 'Java must be 21'
expected=['api-gateway','auth-service','user-service','product-service','payment-service']
assert {x.text for x in pom.findall('m:modules/m:module',ns)}==set(expected), 'Unexpected Maven modules'
for module in expected:
    module_pom=ET.parse(root/module/'pom.xml').getroot()
    assert module_pom.find('m:parent/m:artifactId',ns).text=='taller-03-microservices', f'{module} must inherit root BOM'

for item in requests:
    url=item['request']['url']
    if isinstance(url, dict): url=url.get('raw','')
    assert url, f'Missing URL {item["name"]}'
for service in ['auth','user','product','payment']:
    base=root/f'{service}-service'
    assert (base/'src/main/resources/db/migration/V1__initial_schema.sql').is_file()
assert (root/'.github/workflows/ci-cd.yml').is_file()
assert '!**/src/main/resources/db/migration/*.sql' in (root/'.gitignore').read_text(), 'Flyway migrations must be tracked by Git'

print(f'Static checks OK: {len(requests)} Postman requests; 4 SQL migrations; Spring Boot 4.0.8; workflow.')
