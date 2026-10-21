VERSION ?= 0.1.0-dev
DIST ?= dist

.PHONY: build test fmt clean

build:
	mkdir -p $(DIST)
	go build -trimpath -ldflags "-s -w -X main.version=$(VERSION)" -o $(DIST)/frappe1tap ./cmd/frappe1tap

test:
	go test ./...

fmt:
	gofmt -w cmd internal

clean:
	rm -rf $(DIST)
