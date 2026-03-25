# HARD PRINT SYSTEM DESIGN

## 🎯 **GOAL**
Transform naive checkpointing into true "crystallization" with sector-aligned NVMe writes, incremental updates, and metabolic cycle timing.

## 🔬 **CURRENT IMPLEMENTATION (Naive)**
```c
void save_nvme_checkpoint(int step, float* d_f, float* d_rho, float* d_ux, float* d_uy) {
    // 1. Saves EVERYTHING every 10k steps
    // 2. 48MB per checkpoint (Beast), 12MB (the-craw)
    // 3. Simple fwrite() with no optimization
    // 4. No incremental updates, no compression
}
```

## 🚀 **HARD PRINT REQUIREMENTS**

### **1. Metabolic Cycle Timing**
From seed-brain code:
- **Metabolic**: 0.005 Hz (200s cycle) - vapor chamber thermal
- **Cognitive**: 0.06 Hz (16.67s cycle) - thinking frequency  
- **12:1 ratio** - cognitive events nest inside metabolic cycles
- **Phase-locked persistence**: NVMe writes ONLY during 140-160s window

### **2. Morton Dirty-Tile System**
- Tiles marked "dirty" when coherence threshold exceeded
- Hot tiles (low decay age) have tighter thresholds
- Only dirty tiles flushed to NVMe
- Reduces I/O by 90-99%

### **3. Sector-Aligned Writes**
- Align writes to 512B/4K SSD sectors
- Reduce write amplification
- Improve NVMe longevity

### **4. State Compression**
- Compress state before writing
- Different compression for different data types
- Optimize for "crystallized" storage

### **5. Thermal Coupling**
- Hot silicon → more decay ticks → faster forgetting
- Cold silicon → fewer decay ticks → slower forgetting
- Evolutionary pressure: train on Beast (hot), persist on the-craw (cool)

## 🏗️ **ARCHITECTURE DESIGN**

### **Phase 1: Incremental Checkpointing**
```c
struct HardPrintState {
    uint32_t step;
    uint32_t dirty_tile_mask[1024/32][1024/32];  // 32×32 tile grid
    float* compressed_f;      // Only changed tiles
    float* compressed_rho;
    float* compressed_ux;
    float* compressed_uy;
    uint64_t checksum;
    uint32_t compression_type;
    uint32_t thermal_state;   // GPU temperature
    uint64_t metabolic_cycle; // 0-199 seconds
};
```

### **Phase 2: Metabolic Cycle Integration**
```c
// Track metabolic cycle
uint64_t get_metabolic_cycle_time() {
    auto now = std::chrono::steady_clock::now();
    uint64_t ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch()).count();
    return (ms / 1000) % 200;  // 200-second cycle
}

bool should_flush_to_nvme() {
    uint64_t cycle_time = get_metabolic_cycle_time();
    // Only flush during 140-160s window
    return (cycle_time >= 140 && cycle_time <= 160);
}
```

### **Phase 3: Dirty-Tile Detection**
```c
// Morton encoding for 32×32 tiles
uint32_t morton_encode(int x, int y) {
    x = (x | (x << 8)) & 0x00FF00FF;
    x = (x | (x << 4)) & 0x0F0F0F0F;
    x = (x | (x << 2)) & 0x33333333;
    x = (x | (x << 1)) & 0x55555555;
    
    y = (y | (y << 8)) & 0x00FF00FF;
    y = (y | (y << 4)) & 0x0F0F0F0F;
    y = (y | (y << 2)) & 0x33333333;
    y = (y | (y << 1)) & 0x55555555;
    
    return x | (y << 1);
}

// Check if tile changed beyond threshold
bool tile_changed(float* current, float* previous, int tile_x, int tile_y, 
                  float threshold, float thermal_factor) {
    // Hot silicon: tighter threshold (faster forgetting)
    // Cold silicon: looser threshold (slower forgetting)
    float adjusted_threshold = threshold * thermal_factor;
    
    // Calculate coherence between current and previous state
    float coherence = calculate_coherence(current, previous, tile_x, tile_y);
    return coherence < adjusted_threshold;
}
```

### **Phase 4: Sector-Aligned Writes**
```c
void sector_aligned_write(FILE* fp, void* data, size_t size) {
    const size_t SECTOR_SIZE = 4096;  // 4K sectors
    size_t padded_size = ((size + SECTOR_SIZE - 1) / SECTOR_SIZE) * SECTOR_SIZE;
    
    // Allocate sector-aligned buffer
    void* aligned_buffer = _aligned_malloc(padded_size, SECTOR_SIZE);
    if (!aligned_buffer) return;
    
    // Copy data
    memcpy(aligned_buffer, data, size);
    // Pad remainder with zeros
    memset((char*)aligned_buffer + size, 0, padded_size - size);
    
    // Write aligned to sector boundaries
    fwrite(aligned_buffer, padded_size, 1, fp);
    
    _aligned_free(aligned_buffer);
}
```

## 📊 **PERFORMANCE TARGETS**

### **Current (Naive):**
- **Size**: 48MB per checkpoint (Beast), 12MB (the-craw)
- **Frequency**: Every 10k steps
- **I/O**: 100% of data written every time
- **Overhead**: High

### **Hard Print Target:**
- **Size**: 1-5MB per checkpoint (90-95% reduction)
- **Frequency**: Every metabolic cycle (200s) + dirty tiles
- **I/O**: 5-10% of data written (only changed tiles)
- **Overhead**: Low

## 🚀 **IMPLEMENTATION PHASES**

### **Phase 1: Foundation (Today)**
1. Add checksum verification to current checkpoint
2. Implement incremental tile comparison
3. Test dirty-tile detection accuracy

### **Phase 2: Optimization (Today)**
1. Add compression (zstd or simple delta encoding)
2. Implement sector-aligned writes
3. Add metadata storage (thermal state, cycle time)

### **Phase 3: Metabolic Integration (Tomorrow)**
1. Add metabolic cycle timing
2. Implement phase-locked persistence
3. Add thermal coupling logic

### **Phase 4: Production (This Week)**
1. Full crash recovery system
2. Cross-server compatibility
3. Performance benchmarking
4. Documentation

## 🧪 **TESTING STRATEGY**

### **Test 1: Data Integrity**
- Verify checksums match after write/read
- Test corruption detection
- Validate restore functionality

### **Test 2: Performance**
- Measure I/O reduction (target: 90%+)
- Compare with naive checkpointing
- Measure NVMe wear reduction

### **Test 3: Crash Recovery**
- Kill process at random points
- Verify latest valid checkpoint
- Test restore and resume

### **Test 4: Cross-Server**
- Compare Beast vs the-craw performance
- Verify compatibility
- Test migration scenarios

## 📁 **FILE STRUCTURE**

```
C:\fractal_nvme_test\
├── checkpoint_00100000.bin          # Current naive checkpoint
├── hardprint_00100000.hp            # New Hard Print format
├── hardprint_00100000.meta          # Metadata (checksums, tiles, thermal)
├── hardprint_index.bin              # Index of all checkpoints
└── recovery.log                     # Crash recovery log
```

## 🎯 **SUCCESS CRITERIA**

1. **I/O Reduction**: ≥90% reduction in written data
2. **Integrity**: 100% data integrity verification
3. **Performance**: ≤10% overhead vs naive checkpointing
4. **Recovery**: ≤30 seconds to restore from crash
5. **Compatibility**: Works on both Beast and the-craw

## 🔄 **MIGRATION PATH**

1. **Keep current system** as fallback
2. **Implement Hard Print** alongside current
3. **Test thoroughly** before switching
4. **Phase out naive** once Hard Print proven

**Ready for implementation.**