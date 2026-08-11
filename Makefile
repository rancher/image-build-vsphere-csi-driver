SEVERITIES = HIGH,CRITICAL

UNAME_M = $(shell uname -m)
ifndef TARGET_PLATFORMS
	ifeq ($(UNAME_M), x86_64)
		TARGET_PLATFORMS:=linux/amd64
	else ifeq ($(UNAME_M), aarch64)
		TARGET_PLATFORMS:=linux/arm64
	else
		TARGET_PLATFORMS:=linux/$(UNAME_M)
	endif
endif

REPO ?= ghcr.io/rancher
PKG ?= github.com/kubernetes-sigs/vsphere-csi-driver
BUILD_META=-build$(shell date +%Y%m%d)
TAG ?= ${GITHUB_ACTION_TAG}

ifeq ($(TAG),)
TAG := $(shell cat TAG)$(BUILD_META)
endif

ifeq (,$(filter %$(BUILD_META),$(TAG)))
$(error TAG $(TAG) needs to end with build metadata: $(BUILD_META))
endif

.PHONY: build-image-vsphere-csi-driver
build-image-vsphere-csi-driver: IMAGE = $(REPO)/hardened-vsphere-csi-driver:$(TAG)
build-image-vsphere-csi-driver:
	docker buildx build \
		--platform=$(TARGET_PLATFORMS) \
		--build-arg PKG=$(PKG) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--target vsphere-csi \
		--tag $(IMAGE) \
		--load \
	.

.PHONY: push-image-vsphere-csi-driver
push-image-vsphere-csi-driver: IMAGE = $(REPO)/hardened-vsphere-csi-driver:$(TAG)
push-image-vsphere-csi-driver:
	docker buildx build \
		$(IID_FILE_FLAG) \
		--sbom=true \
		--attest type=provenance,mode=max \
		--platform=$(TARGET_PLATFORMS) \
		--build-arg PKG=$(PKG) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--target vsphere-csi \
		--tag $(IMAGE) \
		--push \
		.

.PHONY: build-image-vsphere-csi-syncer
build-image-vsphere-csi-syncer: IMAGE = $(REPO)/hardened-vsphere-csi-syncer:$(TAG)
build-image-vsphere-csi-syncer:
	docker buildx build \
		--platform=$(TARGET_PLATFORMS) \
		--build-arg PKG=$(PKG) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--target syncer \
		--tag $(IMAGE) \
		--load \
	.

.PHONY: push-image-vsphere-csi-syncer
push-image-vsphere-csi-syncer: IMAGE = $(REPO)/hardened-vsphere-csi-syncer:$(TAG)
push-image-vsphere-csi-syncer:
	docker buildx build \
		$(IID_FILE_FLAG) \
		--sbom=true \
		--attest type=provenance,mode=max \
		--platform=$(TARGET_PLATFORMS) \
		--build-arg PKG=$(PKG) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--target syncer \
		--tag $(IMAGE) \
		--push \
		.

.PHONY: build-image-all
build-image-all: build-image-vsphere-csi-driver build-image-vsphere-csi-syncer

.PHONY: push-image-all
push-image-all: push-image-vsphere-csi-driver push-image-vsphere-csi-syncer

.PHONY: image-scan
image-scan:
	trivy image --severity $(SEVERITIES) --no-progress --ignore-unfixed $(REPO)/hardened-vsphere-csi-driver:$(TAG)
	trivy image --severity $(SEVERITIES) --no-progress --ignore-unfixed $(REPO)/hardened-vsphere-csi-syncer:$(TAG)

.PHONY: log
log:
	@echo "TARGET_PLATFORMS=$(TARGET_PLATFORMS)"
	@echo "REPO=$(REPO)"
	@echo "PKG=$(PKG)"
	@echo "TAG=$(TAG:$(BUILD_META)=)"
	@echo "BUILD_META=$(BUILD_META)"
	@echo "UNAME_M=$(UNAME_M)"
