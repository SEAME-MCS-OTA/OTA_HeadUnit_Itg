#ifndef SHAREDMEMORY_H
# define SHAREDMEMORY_H

# include <sys/mman.h>
# include <sys/stat.h>
# include <fcntl.h>
# include <unistd.h>
# include <cstring>
# include <string>
# include <stdexcept>

/**
 * @brief Generic POSIX Shared Memory Manager
 * 
 * Provides low-level shared memory operations for cross-process communication.
 * This class handles the POSIX shared memory lifecycle without any domain-specific logic.
 */
class SharedMemory {
public:
    /**
     * @brief Constructor
     * @param name Shared memory segment name (without leading slash)
     * @param size Size of shared memory segment in bytes
     * @param create_mode If true, creates new segment; if false, connects to existing
     */
    SharedMemory(const std::string& name, size_t size, bool create_mode = false);
    
    /**
     * @brief Destructor - automatically cleans up resources
     */
    ~SharedMemory();

    /**
     * @brief Check if shared memory is properly initialized
     * @return true if ready for read/write operations
     */
    bool isValid() const;

    /**
     * @brief Get raw pointer to shared memory
     * @return void* pointer to mapped memory, nullptr if invalid
     */
    void* getMemoryPtr() const;

    /**
     * @brief Get the size of shared memory segment
     * @return Size in bytes
     */
    size_t getSize() const;

    /**
     * @brief Force synchronization of memory to storage
     * Ensures all writes are committed to shared memory
     */
    void sync();

    /**
     * @brief Get the shared memory name
     * @return Name of the shared memory segment
     */
    const std::string& getName() const;

    /**
     * @brief Unlink (delete) the shared memory segment
     * Should only be called by the process that created it
     */
    void unlink();

    // Disable copy constructor and assignment
    SharedMemory(const SharedMemory&) = delete;
    SharedMemory& operator=(const SharedMemory&) = delete;

private:
    std::string shm_name;       // Full name with leading slash
    size_t shm_size;            // Size of shared memory
    int shm_fd;                 // File descriptor
    void* shm_ptr;              // Mapped memory pointer
    bool created_by_this;       // Track if we created the segment

    /**
     * @brief Create new shared memory segment
     */
    void createSharedMemory();

    /**
     * @brief Connect to existing shared memory segment
     */
    void connectToSharedMemory();

    /**
     * @brief Map the shared memory into process address space
     */
    void mapSharedMemory();

    /**
     * @brief Clean up resources
     */
    void cleanup();
};

#endif