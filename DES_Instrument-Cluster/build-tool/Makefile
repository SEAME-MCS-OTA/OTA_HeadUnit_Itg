# Makefile for building, deploying, and running the Raspberry Pi project.

# --- Configuration ---
# You can customize these variables

# Name for the Docker build image
DOCKER_IMAGE_NAME := rpi-builder

# Name of your final executable file
TARGET_EXEC := appIC

# Name of the directory for build artifacts
BUILD_DIR := build

# Raspberry Pi SSH connection details
RPI_USER := admin
RPI_HOST := seame2025t2
# Directory on the Pi where the app will be copied
RPI_TARGET_DIR := ~/

# --- Internal Variables (usually no need to change) ---
LOCAL_TARGET_PATH := $(BUILD_DIR)/$(TARGET_EXEC)
RPI_TARGET_PATH := $(RPI_TARGET_DIR)/$(TARGET_EXEC)
# DOCKER_BUILD_CMD := cmake -B $(BUILD_DIR) -S . && cmake --build $(BUILD_DIR)
DOCKER_BUILD_CMD := cmake -B $(BUILD_DIR) -S . $(CMAKE_FLAGS) && cmake --build $(BUILD_DIR)

# --- phony targets (commands that are not files) ---
.PHONY: all build deploy run clean docker-image all-run

# --- Main Targets ---

# Default command: build the code and deploy it to the Pi.
# Usage: make
all: deploy

# Build the Docker image (only if it doesn't already exist).
# This version uses a more robust check.
docker-image:
	@if [ -z "$$(docker images -q $(DOCKER_IMAGE_NAME):latest)" ]; then \
		echo "--- Docker image not found. Building '$(DOCKER_IMAGE_NAME)'... ---"; \
		docker build -t $(DOCKER_IMAGE_NAME) .; \
	else \
		echo "--- Docker image '$(DOCKER_IMAGE_NAME)' found. Skipping build. ---"; \
	fi

# Build the C++ project inside the Docker container.
# This depends on the Docker image being present.
# Usage: make build
build: docker-image
	@echo "--- Building project in Docker... ---"
	docker run --rm -v $(CURDIR):/app $(DOCKER_IMAGE_NAME) sh -c "$(DOCKER_BUILD_CMD)"

# Deploy the built executable to the Raspberry Pi using scp.
# This depends on the project being successfully built.
# Usage: make deploy
deploy: build
	@echo "--- Deploying executable to $(RPI_USER)@$(RPI_HOST) ---"
	scp $(LOCAL_TARGET_PATH) $(RPI_USER)@$(RPI_HOST):$(RPI_TARGET_DIR)

# Run the application on the Raspberry Pi via SSH.
# This will first make the file executable.
# Depends on the project being deployed first.
# Usage: make run
run: deploy
	@echo "--- Running application on Raspberry Pi via SSH... ---"
	ssh $(RPI_USER)@$(RPI_HOST) "chmod +x $(RPI_TARGET_PATH) && $(RPI_TARGET_PATH)"
	
# A single command to build, deploy, and run.
# Usage: make all-run
all-run: run

# --- New Debug Targets ---

# Build the project in Debug mode.
# Usage: make debug
debug:
	@echo "--- Building project in DEBUG mode ---"
	$(MAKE) build CMAKE_FLAGS="-D CMAKE_BUILD_TYPE=Debug"

# Deploy the debug build to the Pi.
# Usage: make deploy-debug
deploy-debug: debug
	$(MAKE) deploy

# Run the debug build on the Pi.
# Usage: make run-debug
run-debug: deploy-debug
	$(MAKE) run

# Clean up local build artifacts.
# Usage: make clean
clean:
	@echo "--- Cleaning up build directory... ---"
	rm -rf $(BUILD_DIR)