#pragma once

#include "Device.h"
#include "Assembler.h"

#include <string>
#include <fstream>
#include <filesystem>

class Bus;

// Устройство "диск" - физически папка на компьютере хоста. Файлы
// разной длины не ложатся на модель "адрес=байт памяти", поэтому
// это командный порт (байтовые регистры + команда-триггер), как
// Timer/Keyboard, а не блок памяти вроде TextVRAM. См. ASSEMBLY.md,
// раздел "Disk".
class Disk : public Device
{
public:

    // bus нужен только для команды LOAD (собрать .asm-файл и
    // записать код в RAM) - остальные команды (LIST/OPEN/READ/WRITE)
    // работают только с файловой системой и его не используют.
    Disk(const std::string& folder, Bus* bus);

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

private:

    // Адрес в RAM, куда LOAD кладёт собранный код - та же
    // "песочница", что уже использует poke/run (см. ASSEMBLY.md).
    static const uint32_t LOAD_ADDRESS = 0x00002000;

    std::filesystem::path basePath;
    Bus* bus;
    Assembler assembler;

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

    void loadProgram();
    void deleteFile();
};
