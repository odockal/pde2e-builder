FROM quay.io/rhqp/deliverest:v0.0.4

# Expects one of windows or darwin
ARG OS=windows

 # how about windows path?
ENV ASSETS_FOLDER=/opt/pde2e-builder \
    OS=${OS}

COPY /lib/${OS}/* ${ASSETS_FOLDER}/
