# pde2e-builder
Podman Desktop E2E setup and build image repository

# Usage

## Run the image
```sh
podman run -d --name pde2e-builder-run \
          -e TARGET_HOST=$(cat host) \
          -e TARGET_HOST_USERNAME=$(cat username) \
          -e TARGET_HOST_KEY_PATH=/data/id_rsa \
          -e TARGET_FOLDER=pd-e2e-builder \
          -e TARGET_RESULTS=results \
          -e OUTPUT_FOLDER=/data \
          -e DEBUG=true \
          -v $PWD:/data:z \
          quay.io/odockal/pde2e-builder:v0.0.1-snapshot  \
              pd-e2e-builder/run.ps1 \
                  -targetFolder pd-e2e-builder \
                  -resultsFolder results \
                  -fork containers \
                  -branch main \

```

## Get the image logs
```sh
podman logs -f pde2e-builder-run
```
