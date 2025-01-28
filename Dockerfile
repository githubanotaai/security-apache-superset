# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements. See the NOTICE file for additional details.
# The ASF licenses this file to You under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0

######################################################################
# Node stage to deal with static asset construction
######################################################################
ARG PY_VER=3.11-slim-bookworm

ARG BUILDPLATFORM=${BUILDPLATFORM:-amd64}

# Stage for frontend asset building
FROM --platform=${BUILDPLATFORM} node:20-bullseye-slim AS superset-node-ci

ARG BUILD_TRANSLATIONS="false"
ARG DEV_MODE="false"
ENV BUILD_TRANSLATIONS=${BUILD_TRANSLATIONS}
ENV DEV_MODE=${DEV_MODE}

COPY docker/ /app/docker/

# Install system dependencies required for node-gyp
RUN /app/docker/apt-install.sh build-essential python3 zstd

# Environment variables for frontend build
ENV BUILD_CMD="build" \
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true

# Run memory monitoring script
RUN /app/docker/frontend-mem-nag.sh

WORKDIR /app/superset-frontend

# Create necessary directories
RUN mkdir -p /app/superset/static/assets /app/superset/translations

# Install dependencies if not in dev mode
RUN --mount=type=bind,source=./superset-frontend/package.json,target=./package.json \
    --mount=type=bind,source=./superset-frontend/package-lock.json,target=./package-lock.json \
    --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/root/.npm \
    if [ "$DEV_MODE" = "false" ]; then \
        npm ci; \
    else \
        echo "Skipping 'npm ci' in dev mode"; \
    fi

# Copy frontend source code
COPY superset-frontend /app/superset-frontend

# Stage for compiling frontend assets
FROM superset-node-ci AS superset-node

RUN --mount=type=cache,target=/app/superset-frontend/.temp_cache \
    --mount=type=cache,target=/root/.npm \
    if [ "$DEV_MODE" = "false" ]; then \
        NODE_OPTIONS="--max-old-space-size=2048" npm run ${BUILD_CMD}; \
    else \
        echo "Skipping 'npm run ${BUILD_CMD}' in dev mode"; \
    fi;

COPY superset/translations /app/superset/translations

RUN if [ "$BUILD_TRANSLATIONS" = "true" ]; then \
        NODE_OPTIONS="--max-old-space-size=2048" npm run build-translation; \
    fi; \
    rm -rf /app/superset/translations/*/*/*.po /app/superset/translations/*/*/*.mo;

######################################################################
# Base python layer
######################################################################
FROM python:${PY_VER} AS python-base

ARG BUILD_TRANSLATIONS="false"
ARG DEV_MODE="false"
ENV BUILD_TRANSLATIONS=${BUILD_TRANSLATIONS}
ENV DEV_MODE=${DEV_MODE}

# Set environment variables
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    SUPERSET_ENV=production \
    FLASK_APP="superset.app:create_app()" \
    PYTHONPATH="/app/pythonpath" \
    SUPERSET_HOME="/app/superset_home" \
    SUPERSET_PORT=8088

RUN useradd --user-group -d ${SUPERSET_HOME} -m --no-log-init --shell /bin/bash superset

# Copy and set permissions for scripts
COPY --chmod=755 docker/*.sh /app/docker/

RUN pip install --no-cache-dir --upgrade uv
RUN uv venv /app/.venv
ENV PATH="/app/.venv/bin:${PATH}"

# Install optional browser dependencies
ARG INCLUDE_CHROMIUM="true"
ARG INCLUDE_FIREFOX="false"
RUN --mount=type=cache,target=/root/.cache/uv\
    if [ "$INCLUDE_CHROMIUM" = "true" ] || [ "$INCLUDE_FIREFOX" = "true" ]; then \
        uv pip install playwright && \
        playwright install-deps && \
        if [ "$INCLUDE_CHROMIUM" = "true" ]; then playwright install chromium; fi && \
        if [ "$INCLUDE_FIREFOX" = "true" ]; then playwright install firefox; fi; \
    else \
        echo "Skipping browser installation"; \
    fi

######################################################################
# Python translation compiler layer
######################################################################
FROM python-base AS python-translation-compiler

COPY requirements/translations.txt requirements/
RUN --mount=type=cache,target=/root/.cache/uv \
    /app/docker/pip-install.sh --requires-build-essential -r requirements/translations.txt

COPY superset/translations/ /app/translations_mo/
RUN if [ "$BUILD_TRANSLATIONS" = "true" ]; then \
        pybabel compile -d /app/translations_mo | true; \
    fi; \
    rm -f /app/translations_mo/*/*/*.po /app/translations_mo/*/*/*.json;

######################################################################
# Python APP common layer
######################################################################
FROM python-base AS python-common

COPY --chmod=755 docker/entrypoints /app/docker/entrypoints

WORKDIR /app
RUN mkdir -p ${SUPERSET_HOME} ${PYTHONPATH} superset/static superset-frontend \
    && touch superset/static/version_info.json

# Copy required files
COPY pyproject.toml setup.py MANIFEST.in README.md ./
COPY superset-frontend/package.json superset-frontend/
COPY scripts/check-env.py scripts/

COPY --chmod=755 ./docker/entrypoints/run-server.sh /usr/bin/

RUN /app/docker/apt-install.sh \
      curl \
      libsasl2-dev \
      libsasl2-modules-gssapi-mit \
      libpq-dev \
      libecpg-dev \
      libldap2-dev

COPY --from=superset-node /app/superset/static/assets superset/static/assets
COPY superset superset
RUN rm superset/translations/*/*/*.po

COPY --from=superset-node /app/superset/translations superset/translations
COPY --from=python-translation-compiler /app/translations_mo superset/translations

# Copy Superset custom config with OIDC
COPY docker/pythonpath_dev/superset_config.py /app/pythonpath/superset_config.py
ENV SUPERSET_CONFIG_PATH=/app/pythonpath/superset_config.py

HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD curl -f "http://localhost:${SUPERSET_PORT}/health" || exit 1
CMD [ "/app/docker/entrypoints/run-server.sh" ]
EXPOSE ${SUPERSET_PORT}

######################################################################
# Final lean image...
######################################################################
FROM python-common AS lean

COPY requirements/base.txt requirements/
RUN --mount=type=cache,target=/root/.cache/uv \
    /app/docker/pip-install.sh --requires-build-essential -r requirements/base.txt

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install .

RUN python -m compileall /app/superset

USER superset

######################################################################
# Dev image...
######################################################################
FROM python-common AS dev

RUN /app/docker/apt-install.sh \
    git \
    pkg-config \
    default-libmysqlclient-dev

COPY requirements/*.txt requirements/
RUN --mount=type=cache,target=/root/.cache/uv \
    /app/docker/pip-install.sh --requires-build-essential -r requirements/development.txt

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install .

RUN python -m compileall /app/superset

USER superset

######################################################################
# CI image...
######################################################################
FROM lean AS ci

CMD [ "/app/docker/entrypoints/docker-ci.sh" ]