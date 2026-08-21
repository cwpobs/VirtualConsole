#pragma once

#include <cstdint>
#include <string>
#include <vector>

class Assembler
{
public:

    std::vector<uint8_t> assemble(const std::string& source);

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

    void firstPass(const std::vector<std::string>& lines);

    void secondPass(
        const std::vector<std::string>& lines,
        std::vector<uint8_t>& output
    );
};