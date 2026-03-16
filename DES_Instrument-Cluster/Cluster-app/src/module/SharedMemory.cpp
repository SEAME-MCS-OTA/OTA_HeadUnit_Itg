#include "SharedMemory.h"

SharedMemory::SharedMemory(const std::string& name, size_t size, bool create_mode)
    : shm_name("/" + name), shm_size(size), shm_fd(-1), shm_ptr(nullptr), created_by_this(false) {
    
    if (create_mode) {
        createSharedMemory();
    } else {
        connectToSharedMemory();
    }
}

SharedMemory::~SharedMemory() {
    cleanup();
}

bool SharedMemory::isValid() const {
    return shm_fd != -1 && shm_ptr != nullptr && shm_ptr != MAP_FAILED;
}

void* SharedMemory::getMemoryPtr() const {
    return isValid() ? shm_ptr : nullptr;
}

size_t SharedMemory::getSize() const {
    return shm_size;
}

void SharedMemory::sync() {
    if (isValid()) {
        msync(shm_ptr, shm_size, MS_SYNC);
    }
}

const std::string& SharedMemory::getName() const {
    return shm_name;
}

void SharedMemory::unlink() {
    if (created_by_this) {
        shm_unlink(shm_name.c_str());
    }
}

void SharedMemory::createSharedMemory() {
    // Try to create new shared memory
    shm_fd = shm_open(shm_name.c_str(), O_CREAT | O_EXCL | O_RDWR, 0666);
    
    if (shm_fd == -1) {
        if (errno == EEXIST) {
            // Already exists, connect to existing instead
            connectToSharedMemory();
            return;
        } else {
            throw std::runtime_error("Failed to create shared memory '" + shm_name + "': " + strerror(errno));
        }
    }

    created_by_this = true;

    // Set the size of the shared memory
    if (ftruncate(shm_fd, shm_size) == -1) {
        close(shm_fd);
        shm_unlink(shm_name.c_str());  // Clean up on failure
        throw std::runtime_error("Failed to set shared memory size: " + std::string(strerror(errno)));
    }

    // Map the shared memory
    mapSharedMemory();
}

void SharedMemory::connectToSharedMemory() {
    // Connect to existing shared memory
    shm_fd = shm_open(shm_name.c_str(), O_RDWR, 0666);

    if (shm_fd == -1) {
        throw std::runtime_error("Failed to open existing shared memory '" + shm_name + "': " + strerror(errno));
    }

    created_by_this = false;
    
    // Map the shared memory
    mapSharedMemory();
}

void SharedMemory::mapSharedMemory() {
    shm_ptr = mmap(nullptr, shm_size, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
    
    if (shm_ptr == MAP_FAILED) {
        close(shm_fd);
        if (created_by_this) {
            shm_unlink(shm_name.c_str());
        }
        throw std::runtime_error("Failed to map shared memory: " + std::string(strerror(errno)));
    }
}

void SharedMemory::cleanup() {
    if (shm_ptr && shm_ptr != MAP_FAILED) {
        munmap(shm_ptr, shm_size);
        shm_ptr = nullptr;
    }
    
    if (shm_fd != -1) {
        close(shm_fd);
        shm_fd = -1;
    }

    // Note: We don't automatically unlink here to avoid race conditions
    // Call unlink() explicitly if needed
}