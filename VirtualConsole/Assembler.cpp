#include "Assembler.h"

#include <sstream>
#include <stdexcept>
#include <algorithm>
#include <cctype>


// ============================================================
// Вспомогательные функции
// ============================================================

static std::string trim(const std::string& text)
{
    size_t start = text.find_first_not_of(" \t\r\n");

    if (start == std::string::npos)
        return "";

    size_t end = text.find_last_not_of(" \t\r\n");

    return text.substr(start, end - start + 1);
}


static std::string upper(const std::string& text)
{
    std::string result = text;

    for (char& c : result)
        c = static_cast<char>(std::toupper(c));

    return result;
}


// ============================================================
// Register
// ============================================================

int Assembler::parseRegister(const std::string& name)
{
    std::string reg = upper(name);

    if (reg == "A") return 0;
    if (reg == "B") return 1;
    if (reg == "C") return 2;
    if (reg == "D") return 3;

    return -1;
}


// ============================================================
// Number
// ============================================================

int Assembler::parseNumber(const std::string& text)
{
    std::string value = text;

    // HEX: 0x10
    if (value.size() > 2 &&
        value[0] == '0' &&
        (value[1] == 'x' || value[1] == 'X'))
    {
        return std::stoi(value, nullptr, 16);
    }

    // Decimal
    return std::stoi(value);
}


// ============================================================
// Find label
// ============================================================

int Assembler::findLabel(const std::string& name)
{
    std::string target = upper(name);

    for (const Label& label : labels)
    {
        if (upper(label.name) == target)
            return label.address;
    }

    return -1;
}


// ============================================================
// PASS 1
// ============================================================

void Assembler::firstPass(
    const std::vector<std::string>& lines)
{
    uint16_t address = 0;

    for (const std::string& originalLine : lines)
    {
        std::string line = originalLine;

        // Удаляем комментарий
        size_t comment = line.find(';');

        if (comment != std::string::npos)
            line = line.substr(0, comment);

        line = trim(line);

        if (line.empty())
            continue;


        // -------------------------
        // Label
        // -------------------------

        size_t colon = line.find(':');

        if (colon != std::string::npos)
        {
            std::string labelName =
                trim(line.substr(0, colon));

            Label label;

            label.name = labelName;
            label.address = address;

            labels.push_back(label);

            line = trim(line.substr(colon + 1));

            if (line.empty())
                continue;
        }


        // -------------------------
        // Instruction size
        // -------------------------

        std::stringstream ss(line);

        std::string instruction;

        ss >> instruction;

        instruction = upper(instruction);


        if (instruction == "LDI")
        {
            // opcode + register + value

            address += 3;
        }
        else if (instruction == "ADD" ||
            instruction == "SUB" ||
            instruction == "CMP" ||
            instruction == "PUSH" ||
            instruction == "POP")
        {
            // opcode + register

            address += 2;
        }
        else if (instruction == "LDA" ||
            instruction == "STA" ||
            instruction == "JMP" ||
            instruction == "JZ" ||
            instruction == "JNZ" ||
            instruction == "CALL")
        {
            // opcode + 16-bit address

            address += 3;
        }
        else if (instruction == "HLT" ||
            instruction == "RET")
        {
            address += 1;
        }
        else
        {
            throw std::runtime_error(
                "Unknown instruction: " + instruction
            );
        }
    }
}


// ============================================================
// PASS 2
// ============================================================

void Assembler::secondPass(
    const std::vector<std::string>& lines,
    std::vector<uint8_t>& output)
{
    for (const std::string& originalLine : lines)
    {
        std::string line = originalLine;

        // Удаляем комментарий
        size_t comment = line.find(';');

        if (comment != std::string::npos)
            line = line.substr(0, comment);

        line = trim(line);

        if (line.empty())
            continue;


        // -------------------------
        // Label
        // -------------------------

        size_t colon = line.find(':');

        if (colon != std::string::npos)
        {
            line = trim(line.substr(colon + 1));

            if (line.empty())
                continue;
        }


        // -------------------------
        // Разбираем инструкцию
        // -------------------------

        std::stringstream ss(line);

        std::string instruction;

        ss >> instruction;

        instruction = upper(instruction);


        // -------------------------
        // LDI register, value
        // -------------------------

        if (instruction == "LDI")
        {
            std::string regName;
            std::string valueText;

            ss >> regName;
            ss >> valueText;

            // Убираем запятую:
            // LDI A, 10

            if (!regName.empty() &&
                regName.back() == ',')
            {
                regName.pop_back();
            }

            int reg = parseRegister(regName);

            if (reg < 0)
                throw std::runtime_error(
                    "Invalid register: " + regName
                );

            int value = parseNumber(valueText);

            output.push_back(0x01);
            output.push_back(static_cast<uint8_t>(reg));
            output.push_back(static_cast<uint8_t>(value));
        }


        // -------------------------
        // ADD register
        // -------------------------

        else if (instruction == "ADD")
        {
            std::string regName;

            ss >> regName;

            int reg = parseRegister(regName);

            if (reg < 0)
                throw std::runtime_error(
                    "Invalid register: " + regName
                );

            output.push_back(0x04);
            output.push_back(static_cast<uint8_t>(reg));
        }


        // -------------------------
        // SUB register
        // -------------------------

        else if (instruction == "SUB")
        {
            std::string regName;

            ss >> regName;

            int reg = parseRegister(regName);

            if (reg < 0)
                throw std::runtime_error(
                    "Invalid register: " + regName
                );

            output.push_back(0x05);
            output.push_back(static_cast<uint8_t>(reg));
        }


        // -------------------------
        // CMP register
        // -------------------------

        else if (instruction == "CMP")
        {
            std::string regName;

            ss >> regName;

            int reg = parseRegister(regName);

            if (reg < 0)
                throw std::runtime_error(
                    "Invalid register: " + regName
                );

            output.push_back(0x06);
            output.push_back(static_cast<uint8_t>(reg));
        }


        // -------------------------
        // PUSH register
        // -------------------------

        else if (instruction == "PUSH")
        {
            std::string regName;

            ss >> regName;

            int reg = parseRegister(regName);

            if (reg < 0)
                throw std::runtime_error(
                    "Invalid register: " + regName
                );

            output.push_back(0x0A);
            output.push_back(static_cast<uint8_t>(reg));
        }


        // -------------------------
        // POP register
        // -------------------------

        else if (instruction == "POP")
        {
            std::string regName;

            ss >> regName;

            int reg = parseRegister(regName);

            if (reg < 0)
                throw std::runtime_error(
                    "Invalid register: " + regName
                );

            output.push_back(0x0B);
            output.push_back(static_cast<uint8_t>(reg));
        }


        // -------------------------
        // LDA / STA / JMP / JZ / JNZ
        // -------------------------

        else if (instruction == "LDA" ||
            instruction == "STA" ||
            instruction == "JMP" ||
            instruction == "JZ" ||
            instruction == "JNZ" ||
            instruction == "CALL")
        {
            std::string addressText;

            ss >> addressText;

            int address;

            if (std::isdigit(addressText[0]) ||
                addressText[0] == '-')
            {
                address = parseNumber(addressText);
            }
            else
            {
                address = findLabel(addressText);

                if (address < 0)
                    throw std::runtime_error(
                        "Unknown label: " + addressText
                    );
            }


            uint8_t opcode;

            if (instruction == "LDA")
                opcode = 0x02;

            else if (instruction == "STA")
                opcode = 0x03;

            else if (instruction == "JMP")
                opcode = 0x07;

            else if (instruction == "JZ")
                opcode = 0x08;

            else if (instruction == "JNZ")
                opcode = 0x09;

            else
                opcode = 0x0C;


            output.push_back(opcode);

            output.push_back(
                static_cast<uint8_t>(address & 0xFF)
            );

            output.push_back(
                static_cast<uint8_t>((address >> 8) & 0xFF)
            );
        }


        // -------------------------
        // HLT
        // -------------------------

        else if (instruction == "HLT")
        {
            output.push_back(0xFF);
        }


        // -------------------------
        // RET
        // -------------------------

        else if (instruction == "RET")
        {
            output.push_back(0x0D);
        }


        else
        {
            throw std::runtime_error(
                "Unknown instruction: " + instruction
            );
        }
    }
}


// ============================================================
// Assemble
// ============================================================

std::vector<uint8_t> Assembler::assemble(
    const std::string& source)
{
    labels.clear();

    std::vector<std::string> lines;

    std::stringstream stream(source);

    std::string line;

    while (std::getline(stream, line))
    {
        lines.push_back(line);
    }


    // Первый проход:
    // ищем адреса меток

    firstPass(lines);


    // Второй проход:
    // генерируем машинный код

    std::vector<uint8_t> output;

    secondPass(lines, output);

    return output;
}