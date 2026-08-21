#pragma once

#include "Device.h"

#include <string>
#include <fstream>
#include <filesystem>

// Устройство "диск" - физически папка на компьютере хоста. Файлы
// разной длины не ложатся на модель "адрес=байт памяти", поэтому
// это командный порт (байтовые регистры + команда-триггер), как
// Timer/Keyboard, а не блок памяти вроде TextVRAM. См. ASSEMBLY.md,
// раздел "Disk".
class Disk : public Device
{
public:

    Disk(const std::string& folder);

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

private:

    std::filesystem::path basePath;

    uint8_t name[12];
    uint8_t status;
    uint8_t dataByte;
    uint32_t fileSize;

    std::filesystem::directory_iterator dirIt;
    std::ifstream readStream;
    std::ofstream writeStream;

    std::string nameAsString() const;

    void listFirst();
    void listNext();
    void skipToRegularFile();
    void populateNameFromIterator();

    void openRead();
    void readByte();

    void openWrite();
    void writeByte();

    void closeFiles();
};
