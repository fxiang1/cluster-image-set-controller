# Repo hosting the image with path
REPO ?= "quay.io/stolostron/"

# Image URL to use all building/pushing image targets
IMG ?= $(REPO)cluster-imageset-controller:latest

export CGO_ENABLED=1

# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.22

KUBECTL?=kubectl

JUNIT_REPORT_FILE?=e2e-junit-report.xml

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development


.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) -p path)" go test $(shell go list ./... | grep -v /test/e2e) -coverprofile cover.out

##@ Build
.PHONY: vendor
vendor:
	go mod vendor

.PHONY: build
build: vendor fmt vet ## Build manager binary.
	GOFLAGS="" go build -o bin/clusterimageset cmd/main.go

.PHONY: build-konflux
build-konflux:
	GOFLAGS="" go build -o bin/clusterimageset cmd/main.go

.PHONY: run
run: fmt vet ## Run a controller from your host.
	go run cmd/main.go

.PHONY: docker-build
docker-build:   # Build docker image with the manager.
	docker build -t ${IMG} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	docker push ${IMG}

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

ENVTEST = $(shell pwd)/bin/setup-envtest
ENVTEST_PACKAGE ?= sigs.k8s.io/controller-runtime/tools/setup-envtest@release-0.17
.PHONY: envtest
envtest: ## Download envtest-setup locally if necessary.
	$(call go-get-tool,$(ENVTEST),$(ENVTEST_PACKAGE))

# go-get-tool will 'go get' any package $2 and install it to $1.
PROJECT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
define go-get-tool
	$(call go-get-tool-internal,$(1),$(2),$(firstword $(subst @, ,$(2))))
endef

define go-get-tool-internal
@[ -f $(1) ] || { \
set -e ;\
TMP_DIR=$$(mktemp -d) ;\
cd $$TMP_DIR ;\
go mod init tmp ;\
echo "Downloading $(2)" ;\
GOBIN=$(PROJECT_DIR)/bin go get -d $(2) ;\
GOBIN=$(PROJECT_DIR)/bin go install $(3) ;\
rm -rf $$TMP_DIR ;\
}
endef

build-e2e:
	go test -c ./test/e2e

test-e2e: build-e2e deploy-ocm 
	./e2e.test -test.v -ginkgo.v -ginkgo.junit-report $(JUNIT_REPORT_FILE)

deploy-ocm: ensure-clusteradm
	hack/install_ocm.sh

.PHONY: ensure-clusteradm
ensure-clusteradm:
ifeq (, $(shell which clusteradm))
	@{ \
	set -e ;\
	export INSTALL_DIR="${GOPATH}/bin" ;\
	curl -L https://raw.githubusercontent.com/open-cluster-management-io/clusteradm/main/install.sh | bash ;\
	}
	CLUSTERADM=${GOPATH}/bin/clusteradm
else
	CLUSTERADM=$(shell which clusteradm)
endif
	$(@info CLUSTERADM="$(CLUSTERADM)")
