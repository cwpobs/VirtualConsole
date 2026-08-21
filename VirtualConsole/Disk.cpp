#include "Disk.h"
#include "Bus.h"

#include <sstream>

Disk::Disk(const std::string& folder, Bus* bus)
{
    basePath = folder;
    this->bus = bus;

    std::filesystem::create_directories(basePath);

    for (int i = 0; i < 12; i++)
    {
        name[i] = 0;
    }

    status = 0;
    dataByte = 0;
    fileSize = 0;

    dirIt = std::filesystem::directory_iterator();
}

uint8_t Disk::read(uint32_t address)
{
    if (address <= 11)
    {
        return name[address];
    }

    if (address == 13)
    {
        return status;
    }

    if (address == 14)
    {
        return dataByte;
    }

    if (address >= 15 && address <= 18)
    {
        return (fileSize >> ((address - 15) * 8)) & 0xFF;
    }

    return 0;
}

void Disk::write(uint32_t address, uint8_t value)
{
    if (address <= 11)
    {
        name[address] = value;
        return;
    }

    if (address == 12)
    {
        switch (value)
        {
        case 1: listFirst(); break;
        case 2: listNext(); break;
        case 3: openRead(); break;
        case 4: readByte(); break;
        case 5: openWrite(); break;
        case 6: writeByte(); break;
        case 7: closeFiles(); break;
        case 8: loadProgram(); break;
        case 9: deleteFile(); break;
        default: break;
        }

        return;
    }

    if (address == 14)
    {
        dataByte = value;
        return;
    }
}

std::string Disk::nameAsString() const
{
    std::string result;

    for (int i = 0; i < 12 && name[i] != 0; i++)
    {
        result += static_cast<char>(name[i]);
    }

    return result;
}

void Disk::listFirst()
{
    std::error_code ec;

    dirIt = std::filesystem::directory_iterator(basePath, ec);

    if (ec)
    {
        status = 2;
        return;
    }

    skipToRegularFile();
    populateNameFromIterator();
}

void Disk::listNext()
{
    if (dirIt != std::filesystem::directory_iterator())
    {
        std::error_code ec;
        dirIt.increment(ec);
    }

    skipToRegularFile();
    populateNameFromIterator();
}

void Disk::skipToRegularFile()
{
    while (dirIt != std::filesystem::directory_iterator() &&
        !dirIt->is_regular_file())
    {
        std::error_code ec;
        dirIt.increment(ec);
    }
}

void Disk::populateNameFromIterator()
{
    for (int i = 0; i < 12; i++)
    {
        name[i] = 0;
    }

    if (dirIt == std::filesystem::directory_iterator())
    {
        status = 1;
        return;
    }

    std::string fileName = dirIt->path().filename().string();

    for (int i = 0; i < 12 && i < static_cast<int>(fileName.size()); i++)
    {
        name[i] = static_cast<uint8_t>(fileName[i]);
    }

    status = 0;
}

void Disk::openRead()
{
    if (readStream.is_open())
    {
        readStream.close();
    }

    readStream.clear();

    readStream.open(basePath / nameAsString(), std::ios::binary);

    if (!readStream)
    {
        status = 2;
        fileSize = 0;
        return;
    }

    readStream.seekg(0, std::ios::end);
    fileSize = static_cast<uint32_t>(readStream.tellg());
    readStream.seekg(0, std::ios::beg);

    status = 0;
}

void Disk::readByte()
{
    if (!readStream.is_open())
    {
        status = 2;
        return;
    }

    int c = readStream.get();

    if (c == EOF)
    {
        status = 1;
        return;
    }

    dataByte = static_cast<uint8_t>(c);
    status = 0;
}

void Disk::openWrite()
{
    if (writeStream.is_open())
    {
        writeStream.close();
    }

    writeStream.clear();

    writeStream.open(basePath / nameAsString(), std::ios::binary | std::ios::trunc);

    status = writeStream ? 0 : 2;
}

void Disk::writeByte()
{
    if (!writeStream.is_open())
    {
        status = 2;
        return;
    }

    writeStream.put(static_cast<char>(dataByte));
    status = 0;
}

void Disk::closeFiles()
{
    if (readStream.is_open())
    {
        readStream.close();
    }

    if (writeStream.is_open())
    {
        writeStream.close();
    }

    status = 0;
}

void Disk::loadProgram()
{
    // Читаем NAME как текстовый .asm-файл (не бинарно - это исходник
    // ассемблера, не машинный код), собираем тем же Assembler, что
    // main.cpp использует для boot.asm, и кладём результат в RAM по
    // фиксированному адресу песочницы - дальше программа запускается
    // как обычно через CALL LOAD_ADDRESS (см. cmd_exec в boot.asm).

    std::ifstream sourceFile(basePath / nameAsString());

    if (!sourceFile)
    {
        status = 2;
        fileSize = 0;
        return;
    }

    std::stringstream buffer;
    buffer << sourceFile.rdbuf();

    std::vector<uint8_t> machineCode;

    try
    {
        machineCode = assembler.assemble(buffer.str());
    }
    catch (const std::exception&)
    {
        status = 2;
        fileSize = 0;
        return;
    }

    for (size_t i = 0; i < machineCode.size(); i++)
    {
        bus->write(
            LOAD_ADDRESS + static_cast<uint32_t>(i),
            machineCode[i]
        );
    }

    fileSize = static_cast<uint32_t>(machineCode.size());
    status = 0;
}

void Disk::deleteFile()
{
    std::error_code ec;

    bool removed = std::filesystem::remove(basePath / nameAsString(), ec);

    status = (!ec && removed) ? 0 : 2;
}
