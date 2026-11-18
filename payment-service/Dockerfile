# Etapa 1: compilar payment-service con Java 21
FROM maven:3.9.11-eclipse-temurin-21 AS build

WORKDIR /workspace

COPY . .

RUN mvn -B --no-transfer-progress \
    -pl payment-service -am \
    clean package -DskipTests

RUN cp payment-service/target/payment-service-*.jar /tmp/app.jar

# Etapa 2: ejecutar con Java 21
FROM eclipse-temurin:21-jre

WORKDIR /app

COPY --from=build /tmp/app.jar /app/app.jar

USER 10001:10001

EXPOSE 8084

ENTRYPOINT ["java", "-jar", "/app/app.jar"]