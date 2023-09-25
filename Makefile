VERSION ?= 0.0.1-snapshot
CONTAINER_MANAGER ?= podman
IMG ?= quay.io/odockal/pde2e-builder:v${VERSION}

.PHONY: oci-build
oci-build:
	${CONTAINER_MANAGER} build -t ${IMG} -f Containerfile .

.PHONY: oci-push
oci-push:
	${CONTAINER_MANAGER} push ${IMG}
