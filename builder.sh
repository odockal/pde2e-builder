#!/bin/bash

# Build and Push Mac OS image
OS=darwin make oci-build
OS=darwin make oci-push

# Build and Push Windows image
OS=windows make oci-build
OS=windows make oci-push

# Push Tekton Image
make tkn-push


