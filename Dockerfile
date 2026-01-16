# Copyright 2020 Google LLC
# Licensed under the Apache License, Version 2.0

############################
# AdService (Java) stages  #
############################
FROM eclipse-temurin:19@sha256:f3fbf1ad599d4b5dbdd7ceb55708d10cb9fafb08e094ef91e92aa63b520a232e AS adservice-builder

WORKDIR /app
COPY ["build.gradle", "gradlew", "./"]
COPY gradle gradle
RUN chmod +x gradlew && ./gradlew downloadRepos
COPY . .
RUN chmod +x gradlew && ./gradlew installDist

FROM eclipse-temurin:19.0.1_10-jre-alpine@sha256:a75ea64f676041562cd7d3a54a9764bbfb357b2bf1bebf46e2af73e62d32e36c AS adservice-runtime-base
RUN apk add --no-cache ca-certificates

# Stackdriver Profiler Java agent (optional)
RUN mkdir -p /opt/cprof && \
    wget -q -O- https://storage.googleapis.com/cloud-profiler/java/latest/profiler_java_agent_alpine.tar.gz \
    | tar xzv -C /opt/cprof && \
    rm -rf profiler_java_agent.tar.gz

WORKDIR /app
COPY --from=adservice-builder /app .

# Final AdService image
FROM adservice-runtime-base AS adservice
ENV GRPC_HEALTH_PROBE_VERSION=v0.4.18
RUN wget -qO/bin/grpc_health_probe https://github.com/grpc-ecosystem/grpc-health-probe/releases/download/${GRPC_HEALTH_PROBE_VERSION}/grpc_health_probe-linux-amd64 && \
    chmod +x /bin/grpc_health_probe
EXPOSE 9555
ENTRYPOINT ["/app/build/install/hipstershop/bin/AdService"]

###############################
# EmailService (Python) stages#
###############################
FROM python:3.10.8-slim@sha256:49749648f4426b31b20fca55ad854caa55ff59dc604f2f76b57d814e0a47c181 AS email-base

FROM email-base AS email-builder
RUN apt-get -qq update && \
    apt-get install -y --no-install-recommends wget g++ && \
    rm -rf /var/lib/apt/lists/*

# grpc health probe
ENV GRPC_HEALTH_PROBE_VERSION=v0.4.18
RUN wget -qO/bin/grpc_health_probe https://github.com/grpc-ecosystem/grpc-health-probe/releases/download/${GRPC_HEALTH_PROBE_VERSION}/grpc_health_probe-linux-amd64 && \
    chmod +x /bin/grpc_health_probe

# Python deps
COPY requirements.txt .
RUN pip install -r requirements.txt

FROM email-base AS email-runtime
ENV PYTHONUNBUFFERED=1
ENV ENABLE_PROFILER=1
WORKDIR /email_server

# Bring in installed libs and app
COPY --from=email-builder /usr/local/lib/python3.10/ /usr/local/lib/python3.10/
COPY . .

# Final EmailService image
FROM email-runtime AS emailservice
COPY --from=email-builder /bin/grpc_health_probe /bin/grpc_health_probe
EXPOSE 8080
ENTRYPOINT ["python", "email_server.py"]
