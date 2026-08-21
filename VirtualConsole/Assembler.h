#pragma once

#include <cstdint>
#include <string>
#include <vector>

class Assembler
{
public:

    // origin - адрес, с которого программа реально будет исполняться
    // в памяти (по умолчанию 0, как boot.asm). Метки/адреса резолвятся
    // относительно него - нужен, когда код грузится не на адрес 0
    // (см. Disk::loadProgram, SHELL.ASM).
    std::vector<uint8_t> assemble(
        const std::string& source,
        uint32_t origin = 0
    );

private:

    struct Label
    {
        std::string name;
        uint32_t address;
    };

    std::vector<Label> labels;

    int findLabel(const std::string& name);

    int parseRegister(const std::string& name);

    uint32_t parseNumber(const std::string& text);

    void firstPass(
        const std::vector<std::string>& lines,
        uint32_t origin
    );

    void secondPass(
        const std::vector<std::string>& lines,
        std::vector<uint8_t>& output
    );
};