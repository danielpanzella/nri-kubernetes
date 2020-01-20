OSFLAG := $(shell uname -s | tr A-Z a-z)
OSFLAG := $(OSFLAG)_amd64
BIN_DIR = ./bin
TOOLS_DIR := $(BIN_DIR)/dev-tools
BINARY_NAME = nr-kubernetes
E2E_BINARY_NAME := $(BINARY_NAME)-e2e

GOVENDOR_VERSION = 1.0.8
GOLANGCILINT_VERSION = 1.13

.PHONY: all
all: build

.PHONY: build
build: clean lint  test compile

.PHONY: clean
clean:
	@echo "[clean] Removing integration binaries"
	@rm -rf $(BIN_DIR)/$(BINARY_NAME) $(BIN_DIR)/$(E2E_BINARY_NAME)

$(TOOLS_DIR):
	@mkdir -p $@

$(TOOLS_DIR)/golangci-lint: $(TOOLS_DIR)
	@echo "[tools] Downloading 'golangci-lint'"
	@wget -O - -q https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | BINDIR=$(@D) sh -s v$(GOLANGCILINT_VERSION) &> /dev/null

$(TOOLS_DIR)/govendor: $(TOOLS_DIR)
	@echo "[tools] Downloading 'govendor'"
	@wget -O $(@D)/govendor -q --no-use-server-timestamps https://github.com/kardianos/govendor/releases/download/v$(GOVENDOR_VERSION)/govendor_$(OSFLAG); chmod +x $(@D)/govendor

$(TOOLS_DIR)/papers-go: $(TOOLS_DIR)
	@echo "[tools] Downloading 'papers-go'"
	@go get source.datanerd.us/ohai/papers-go/...
	@cp $(GOPATH)/bin/papers-go $(TOOLS_DIR)/papers-go

.PHONY: deps
deps: $(TOOLS_DIR)/govendor
	@echo "[deps] Installing package dependencies required by the project"
	@$(TOOLS_DIR)/govendor sync

.PHONY: lint
lint: $(TOOLS_DIR)/golangci-lint
	@echo "[validate] Validating source code running golangci-lint"
	@$(TOOLS_DIR)/golangci-lint run

.PHONY: lint-all
lint-all: $(TOOLS_DIR)/golangci-lint
	@echo "[validate] Validating source code running golangci-lint"
	@$(TOOLS_DIR)/golangci-lint run --enable=interfacer --enable=gosimple

.PHONY: license-check
license-check: $(TOOLS_DIR)/papers-go
	@echo "[validate] Validating licenses of package dependencies required by the project"
	@$(TOOLS_DIR)/papers-go validate

.PHONY: compile
compile: deps
	@echo "[compile] Building $(BINARY_NAME)"
	@go build -o $(BIN_DIR)/$(BINARY_NAME) ./src

.PHONY: compile-dev
compile-dev: deps
	@echo "[compile-dev] Building $(BINARY_NAME) for development environment"
	@GOOS=linux GOARCH=amd64 go build -o $(BIN_DIR)/$(BINARY_NAME) ./src

.PHONY: deploy-dev
deploy-dev: compile-dev
	@echo "[deploy-dev] Deploying dev container image containing $(BINARY_NAME) in Kubernetes"
	@skaffold run

.PHONY: test
test: deps
	@echo "[test] Running unit tests"
	@go test ./...

guard-%:
	@ if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* not set"; \
		exit 1; \
	fi

.PHONY: e2e
e2e: guard-CLUSTER_NAME guard-NR_LICENSE_KEY
	@go run e2e/cmd/e2e.go

.PHONY: e2e-compile
e2e-compile: deps
	@echo "[compile E2E binary] Building $(E2E_BINARY_NAME)"
	# CGO_ENABLED=0 is needed since the binary is compiled in a non alpine linux.
	@GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o $(BIN_DIR)/$(E2E_BINARY_NAME) ./e2e/cmd/e2e.go

.PHONY: e2e-compile-only
e2e-compile-only:
	@echo "[compile E2E binary] Building $(E2E_BINARY_NAME)"
	# CGO_ENABLED=0 is needed since the binary is compiled in a non alpine linux.
	@GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o $(BIN_DIR)/$(E2E_BINARY_NAME) ./e2e/cmd/e2e.go
