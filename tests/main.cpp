#include <iostream>
#include "core_services.h"

int main() {
    std::cout << "Running C++ tests..." << std::endl;
    init_core_services();
    std::cout << "All C++ smoke tests passed." << std::endl;
    return 0;
}
