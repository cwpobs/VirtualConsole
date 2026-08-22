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
    //
    // relocations (необязательно) - если передан указатель, туда
    // складываются смещения (относительно НАЧАЛА возвращаемого
    // машинного кода, т.е. относительно origin) всех 4-байтных
    // адресов, полученных из МЕТКИ (не числового литерала) - то есть
    // тех мест, которые нужно сдвинуть, если этот же код потом
    // скопировать на ДРУГОЙ адрес (см. Disk::build()/loadChildRun(),
    // ASSEMBLY.md - "LOAD_CHILD"). Числовые литералы вроде
    // `STA 0xF00007D8` в это множество не попадают - это абсолютные
    // адреса устройств, не зависящие от того, где лежит сама
    // программа.
    std::vector<uint8_t> assemble(
        const std::string& source,
        uint32_t origin = 0,
        std::vector<uint32_t>* relocations = nullptr
    );

private:

    struct Label
    {
        std::string name;
        uint32_t address;
    };

    std::vector<Label> labels;
    std::vector<uint32_t> lastRelocations;

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