VERSION ?= 0.0.1
CONTAINER_MANAGER ?= podman
IMG ?= quay.io/odockal/pde2e-builder:v${VERSION}

# Build the container image
.PHONY: oci-build
$(info    Building the image: $(IMG)-$(OS))
oci-build: 
	${CONTAINER_MANAGER} build -t ${IMG}-${OS} -f Containerfile --build-arg=OS=${OS} .

# Build the container image # requires user to be logged into a registry
.PHONY: oci-push
$(info    Pushing the image: $(IMG)-$(OS))
oci-push: 
	${CONTAINER_MANAGER} push ${IMG}-${OS}