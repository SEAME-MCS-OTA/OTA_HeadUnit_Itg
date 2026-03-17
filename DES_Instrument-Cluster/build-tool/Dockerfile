# Use a base image that exactly matches your Pi's OS version
FROM debian:bookworm

# Install all build dependencies inside the container
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    qt6-base-dev \
    qt6-declarative-dev \
    libxkbcommon-dev \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Set a working directory
WORKDIR /app