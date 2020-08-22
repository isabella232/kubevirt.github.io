#!/usr/bin/env bash

set -e

declare -A IMAGES
IMAGES[gocli]="gocli@sha256:0cec3163e5f8b050f129fa795b76c20cb1eb27c91564c63663160b095064a1f9"
if [ -z $KUBEVIRTCI_PROVISION_CHECK ]; then
    IMAGES[k8s-fedora-1.17.0]="k8s-fedora-1.17.0@sha256:aebf67b8b1b499c721f4d98a7ab9542c680553a14cbc144d1fa701fe611f3c0d"
    IMAGES[k8s-1.18]="k8s-1.18@sha256:f8bc8616139463a7e98330484f6c3748fe10c6ff5f5be614a373fd69b60a957c"
    IMAGES[k8s-1.17]="k8s-1.17@sha256:49de8023fdce76dcf6f3685b4cedc3c84f38c90d58ddf3daf08078f3405e51df"
    IMAGES[k8s-1.16]="k8s-1.16@sha256:1e153fb62c9a30ce6bc6ddc1af21bb28a56b780ec93ab15e113d729bf664469a"
    IMAGES[k8s-1.15]="k8s-1.15@sha256:c58cb9d79968590f24e070bc2517088d44fa2f83ba73e989a7e0f690ad08460b"
    IMAGES[k8s-1.14]="k8s-1.14@sha256:46e449b292dcb420f0944cac0a7a5c667c6f19bba2a4192737380e8e77f27ed0"
fi
export IMAGES

image="${IMAGES[$KUBEVIRT_PROVIDER]:-${KUBEVIRT_PROVIDER}${IMAGE_SUFFIX}:latest}"
export image
