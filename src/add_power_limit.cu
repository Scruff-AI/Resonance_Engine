// Example of adding power limit to fractal_habit
#include <nvml.h>

void set_power_limit(unsigned int power_limit_mW) {
    nvmlReturn_t result;
    nvmlDevice_t device;
    
    result = nvmlInit();
    if (result != NVML_SUCCESS) {
        printf("NVML Init failed: %s\n", nvmlErrorString(result));
        return;
    }
    
    result = nvmlDeviceGetHandleByIndex(0, &device);
    if (result != NVML_SUCCESS) {
        printf("Failed to get device handle: %s\n", nvmlErrorString(result));
        nvmlShutdown();
        return;
    }
    
    // Get current limits
    unsigned int min_limit, max_limit;
    result = nvmlDeviceGetPowerManagementLimitConstraints(device, &min_limit, &max_limit);
    if (result != NVML_SUCCESS) {
        printf("Failed to get power constraints: %s\n", nvmlErrorString(result));
        nvmlShutdown();
        return;
    }
    
    printf("Power limits: %u mW - %u mW\n", min_limit, max_limit);
    
    // Set new limit
    if (power_limit_mW < min_limit) power_limit_mW = min_limit;
    if (power_limit_mW > max_limit) power_limit_mW = max_limit;
    
    result = nvmlDeviceSetPowerManagementLimit(device, power_limit_mW);
    if (result != NVML_SUCCESS) {
        printf("Failed to set power limit to %u mW: %s\n", power_limit_mW, nvmlErrorString(result));
    } else {
        printf("Power limit set to %u mW (%.1f W)\n", power_limit_mW, power_limit_mW / 1000.0f);
    }
    
    nvmlShutdown();
}

int main() {
    // Set to 150W = 150,000 mW
    set_power_limit(150000);
    return 0;
}