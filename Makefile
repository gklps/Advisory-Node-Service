.PHONY: build run test clean install deps

# Build variables
BINARY_NAME=advisory-node
GO=go
GOFLAGS=-v

# Build the binary
build:
	$(GO) build $(GOFLAGS) -o $(BINARY_NAME) .

# Run the application
run: build
	./$(BINARY_NAME)

# Run in debug mode
debug: build
	./$(BINARY_NAME) -mode=debug

# Install dependencies
deps:
	$(GO) mod download
	$(GO) mod tidy

# Run tests (when we add them)
test:
	$(GO) test -v ./...

# Clean build artifacts
clean:
	rm -f $(BINARY_NAME)
	$(GO) clean

# Install globally
install: build
	$(GO) install

# Run with custom port
run-custom:
	./$(BINARY_NAME) -port=9090 -mode=debug

# Build for different platforms
build-all:
	GOOS=darwin GOARCH=amd64 $(GO) build -o $(BINARY_NAME)-darwin-amd64 .
	GOOS=darwin GOARCH=arm64 $(GO) build -o $(BINARY_NAME)-darwin-arm64 .
	GOOS=linux GOARCH=amd64 $(GO) build -o $(BINARY_NAME)-linux-amd64 .
	GOOS=windows GOARCH=amd64 $(GO) build -o $(BINARY_NAME)-windows-amd64.exe .

# Docker support (for future use)
docker-build:
	docker build -t advisory-node:latest .

docker-run:
	docker run -p 8080:8080 advisory-node:latest

# Development helpers
dev:
	$(GO) run . -mode=debug

format:
	$(GO) fmt ./...

vet:
	$(GO) vet ./...

# Help command
help:
	@echo "Available commands:"
	@echo "  make build       - Build the binary"
	@echo "  make run         - Build and run the application"
	@echo "  make debug       - Run in debug mode"
	@echo "  make deps        - Download dependencies"
	@echo "  make test        - Run tests"
	@echo "  make clean       - Remove build artifacts"
	@echo "  make install     - Install globally"
	@echo "  make build-all   - Build for all platforms"
	@echo "  make dev         - Run in development mode"
	@echo "  make format      - Format code"
	@echo "  make vet         - Run go vet"