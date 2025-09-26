PLATFORMS := linux darwin
BUILD_DIR := bin

build:
	go mod tidy && $(foreach platform,$(PLATFORMS), \
		rm -fr $(BUILD_DIR)/$(platform);\
		mkdir -p $(BUILD_DIR)/$(platform); \
	GOARCH=amd64 GOOS=$(platform) go build -ldflags "-s -w" -tags full -o $(BUILD_DIR)/$(platform)/exec-amd64 ./cmd; \
	GOARCH=arm64 GOOS=$(platform) go build -ldflags "-s -w" -tags full -o $(BUILD_DIR)/$(platform)/exec-arm64 ./cmd; \
	GOARCH=amd64 GOOS=$(platform) go build -ldflags "-s -w" -tags full -o $(BUILD_DIR)/$(platform)/exec-x86_64 ./cmd; \
)
