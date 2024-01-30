FROM quay.io/rhqp/deliverest:v0.0.4

LABEL org.opencontainers.image.authors="Ondrej Dockal<odockal@redhat.com>"

# Expects one of windows or darwin
ARG OS

ENV ASSETS_FOLDER=/opt/pde2e-builder \
    OS=${OS}

COPY /lib/${OS}/* ${ASSETS_FOLDER}/
