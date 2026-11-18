WORKDIR /workspace

COPY . .

RUN mvn -B --no-transfer-progress \
    -pl payment-service -am \
    clean package -DskipTests -e

RUN cp payment-service/target/payment-service-*.jar /tmp/app.jar

FROM eclipse-temurin:21-jre

WORKDIR /app

COPY --from=build /tmp/app.jar /app/app.jar

USER 10001:10001

EXPOSE 8084

ENTRYPOINT ["java", "-jar", "/app/app.jar"]