# pde2e-builder
Podman Desktop E2E tests setup and build process image repository

# Usage, building and pushing the image
The repository structure:
* `lib` folder contains platform specific (`windows/builder.ps1`, `darwin/builder.sh`) execution scripts that are shipped using `deliverest` image into a target host machine
* `Containerfile` is a build image configuration file that accepts `--build-args`: `OS` to determine the platform for which the particulat image is being built
* `Makefile` build instructions for building the image using `Containerfile` and pushing it into image registry
* `builder.sh` script that executes makefile for Windows and Mac OS platforms

In order to push an image, user needs to be logged in before executing building scipts.

## Running the image
```sh
# Running the image built for windows platform
podman run -d --name pde2e-builder-run \
          -e TARGET_HOST=$(cat host) \
          -e TARGET_HOST_USERNAME=$(cat username) \
          -e TARGET_HOST_KEY_PATH=/data/id_rsa \
          -e TARGET_FOLDER=pd-e2e \
          -e TARGET_RESULTS=results \
          -e OUTPUT_FOLDER=/data \
          -e DEBUG=true \
          -v $PWD:/data:z \
          quay.io/odockal/pde2e-builder:v0.0.1-windows  \
              pd-e2e/builder.ps1 \
                -targetFolder pd-e2e \
                -resultsFolder results \
                -fork containers \
                -branch main \
                -envVars 'TEST=true,XY=1' \
                -pnpmCommand 'pnpm compile'

# Running the image built for Mac OS
podman run --rm -d --name pde2e-builder-run \
          -e TARGET_HOST=$(cat host) \
          -e TARGET_HOST_USERNAME=$(cat username) \
          -e TARGET_HOST_PASSWORD=$(cat userpassword) \
          -e TARGET_HOST_KEY_PATH=/data/id_rsa \
          -e TARGET_FOLDER=pd-e2e \
          -e TARGET_RESULTS=results \
          -e OUTPUT_FOLDER=/data \
          -e DEBUG=true \
          -v $(pwd):/data:z \
          quay.io/odockal/pde2e-builder:v0.0.1-darwin  \
              pd-e2e/builder.sh \
                --targetFolder pd-e2e \
                --resultsFolder results \
                --fork containers \
                --branch main \
                --envVars 'TEST=true,XY=1' \
                --pnpmCommand 'compile:current'
```

## Get the image logs
```sh
podman logs -f pde2e-builder-run
```
