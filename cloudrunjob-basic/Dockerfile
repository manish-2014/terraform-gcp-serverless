# --- Build Stage ---
# Use a specific Maven version compatible with Java 17
FROM maven:3.9.6-eclipse-temurin-17 as builder
WORKDIR /build

# === Handle local JAR dependency ===
# 1. Copy the local JAR from the build context into the container.
#    Ensure 'libs/cloud-transfer-lib-1.0-SNAPSHOT.jar' exists relative to the Dockerfile.
COPY libs/cloud-transfer-lib-1.0-SNAPSHOT.jar /build/cloud-transfer-lib.jar

# 2. Install the JAR into the container's local Maven repository.
#    Coordinates must match the <dependency> tag in your main pom.xml.
RUN mvn install:install-file \
    -Dfile=/build/cloud-transfer-lib.jar \
    -DgroupId=org.manishsharan.cloudtransfer \
    -DartifactId=cloud-transfer-lib \
    -Dversion=1.0-SNAPSHOT \
    -Dpackaging=jar \
    -DgeneratePom=true
# === End local JAR section ===

# Copy the pom.xml file AFTER installing the local dependency
COPY pom.xml .

# Download dependencies using the pom.xml.
RUN mvn dependency:go-offline --fail-never || true

# Copy the rest of the source code
COPY src ./src

# Package the application, skipping tests.
# This command uses the source code and downloaded dependencies.
RUN mvn package -DskipTests

# --- Runtime Stage ---
# Use a minimal JRE base image
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Create a non-root user and group for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy the built JAR from the builder stage
COPY --from=builder /build/target/cloudrun-basic-*.jar app.jar

# Change ownership of the app directory and JAR to the non-root user
RUN chown -R appuser:appgroup /app

# Switch to the non-root user
USER appuser

# *** REMOVED EXPOSE 8080 - Not needed for a Cloud Run Job ***

# Set the entrypoint to run the application JAR.
# Arguments (like the TransferConfig JSON) must be provided
# when creating/running the Cloud Run Job instance, not here.
ENTRYPOINT ["java", "-XX:+UseG1GC", "-XX:+UseStringDeduplication", "-jar", "app.jar"]