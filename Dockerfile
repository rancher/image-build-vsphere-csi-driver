ARG GO_IMAGE=rancher/hardened-build-base:v1.26.5b1
ARG BCI_IMAGE=registry.suse.com/bci/bci-nano:16.0
ARG BCI_BASE_IMAGE=registry.suse.com/bci/bci-base:16.0

# Image that provides cross compilation tooling.
FROM --platform=$BUILDPLATFORM rancher/mirrored-tonistiigi-xx:1.6.1 AS xx

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS builder
# copy xx scripts to the build stage
COPY --from=xx / /
RUN apk add --no-cache file make git clang lld
ARG TARGETPLATFORM
RUN set -x && xx-apk --no-cache add musl-dev gcc lld

ARG PKG
ARG TAG
RUN git clone --depth=1 https://${PKG}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
COPY go-mod-overrides ./go-mod-overrides
RUN go-mod-overrides.sh ./go-mod-overrides
RUN go mod download

# cross-compilation setup
ARG TARGETARCH
RUN xx-go --wrap && \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o "/usr/local/bin/vsphere-csi" ./cmd/vsphere-csi && \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o "/usr/local/bin/syncer" ./cmd/syncer
RUN xx-verify --static /usr/local/bin/vsphere-csi /usr/local/bin/syncer
RUN if [ "$(xx-info arch)" = "amd64" ]; then \
        go-assert-boring.sh /usr/local/bin/vsphere-csi /usr/local/bin/syncer; \
    fi

# Runtime OS packages for the CSI node plugin. bci-nano has no package
# manager, so install into a rootfs with zypper on bci-base and copy it in.
# Matches the upstream driver image:
# https://github.com/kubernetes-sigs/vsphere-csi-driver/blob/master/images/driver/Dockerfile
# nfs-client : mount helpers for NFS-backed volumes (mount.nfs)
# util-linux : filesystem/partition tooling (mount, blkid, lsblk, ...)
# e2fsprogs  : ext2/3/4 filesystem utilities (mkfs.ext4, e2fsck, ...)
# xfsprogs   : XFS filesystem utilities (mkfs.xfs, xfs_repair, ...)
FROM ${BCI_BASE_IMAGE} AS csi-packages
RUN zypper --non-interactive --installroot /installroot refresh && \
    zypper --non-interactive --installroot /installroot install --no-recommends -y \
        nfs-client \
        util-linux \
        e2fsprogs \
        xfsprogs && \
    zypper --non-interactive --installroot /installroot clean --all && \
    rm -rf /installroot/var/log/* /installroot/var/cache/zypp/*

# vSphere CSI Driver
FROM ${BCI_IMAGE} AS vsphere-csi
LABEL org.opencontainers.image.description="vSphere CSI Driver"
COPY --from=csi-packages /installroot /
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /usr/local/bin/vsphere-csi /vsphere-csi
ENTRYPOINT ["/vsphere-csi"]

# vSphere CSI Metadata Syncer
FROM ${BCI_IMAGE} AS syncer
LABEL org.opencontainers.image.description="vSphere CSI Metadata Syncer"
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /usr/local/bin/syncer /syncer
ENTRYPOINT ["/syncer"]
