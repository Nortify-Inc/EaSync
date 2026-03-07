/*
 * @file memory.hpp
 * @author Radmann
 * @brief Memory module for context storage and retrieval.
 *
 * Supports persistence, indexing, incremental updates, and configuration.
 *
 * Methods:
 *   Memory() - Constructor.
 *   void store(const std::string& context) - Stores context.
 *   std::string retrieve(const std::string& query) - Retrieves context.
 *   std::vector<std::string> vectorSearch(...) - Vector search for context.
 *   void persist(...) - Persists memory to disk.
 *   void load(...) - Loads memory from disk.
 *   void index() - Indexes memory.
 *   void update(...) - Updates memory.
 *   void configure(...) - Configures memory module.
 *
 * Attributes:
 *   std::vector<std::string> memoryStore - Stored contexts.
 *   std::string persistencePath - Path for persistence.
 */
#pragma once
#include <string>
#include <vector>

class Memory {
public:
    Memory();
    void store(const std::string& context);
    std::string retrieve(const std::string& query);
    std::vector<std::string> vectorSearch(const std::string& query);
    void persist(const std::string& path);
    void load(const std::string& path);
    void index();
    void update(const std::string& context);
    void configure(const std::string& path);
private:
    std::vector<std::string> memoryStore;
    std::string persistencePath;
};
