ARG BUILD_FROM=ghcr.io/home-assistant/base:latest
ARG BUILD_VERSION=0.1.0
ARG BUILD_ARCH

FROM node:22-alpine AS node_builder

ARG OPENCLAW_VERSION=2026.4.9

RUN npm install -g "openclaw@${OPENCLAW_VERSION}" --prefix /opt/openclaw/global \
    && npm cache clean --force

FROM ${BUILD_FROM}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.type="app" \
  io.hass.arch="${BUILD_ARCH}"

RUN apk add --no-cache \
      bash \
      ca-certificates \
      curl \
      git \
      nginx \
    && rm -f /etc/nginx/http.d/default.conf

COPY --from=node_builder /usr/local /usr/local
COPY --from=node_builder /opt/openclaw /opt/openclaw

COPY run.sh /

RUN chmod a+x /run.sh

ENV PATH="/opt/openclaw/global/bin:/usr/local/bin:${PATH}"

CMD [ "/run.sh" ]
