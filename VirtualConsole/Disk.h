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

    // Текущая папка диска (меняется командой cd) - для устройств вроде
    // PngLoader/MapLoader/ModLoader, которым нужно резолвить СВОИ
    // файлы относительно того же места, откуда пользователь запустил
    // программу через exec, а не всегда от корня диска.
    std::filesystem::path getCurrentPath() const { return basePath / currentDir; }

    // Какой диск (C или D) последним отдал LOAD в исполняемую
    // песочницу (0x00002000) - см. loadProgram(). Общий на оба
    // экземпляра Disk (статический член класса, не поля объекта) -
    // используется PngLoader/MapLoader/ModLoader, чтобы резолвить
    // СВОИ файлы относительно того диска, с которого реально был
    // запущен через exec текущий .asm, а не всегда с диска C.
    // nullptr - если exec ещё ни разу не запускался (тогда загрузчики
    // по умолчанию используют диск C).
    static Disk* lastExecDisk;

private:

    // Адрес в RAM, куда LOAD (8) кладёт собранный код - та же
    // "песочница", что уже использует poke/run/exec (см. ASSEMBLY.md).
    static const uint32_t LOAD_ADDRESS = 0x00002000;

    // Отдельный адрес для LOAD_SHELL (10) - резидентное место
    // SHELL.ASM. Обязательно другой, чем LOAD_ADDRESS: shell.asm
    // живёт там постоянно, пока работает VM, а песочницу poke/run
    // затирает при каждой команде - если бы они делили один адрес,
    // poke переписывал бы код самого shell'а.
    static const uint32_t SHELL_LOAD_ADDRESS = 0x00003000;

    std::filesystem::path basePath;

    // Текущая папка относительно basePath (пусто = корень диска).
    // v1 - один уровень вложенности (см. ASSEMBLY.md, "Disk"): CHDIR
    // просто добавляет имя, CHDIR_UP берёт parent_path().
    std::filesystem::path currentDir;

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
    void populateNameFromIterator();

    void openRead();
    void readByte();

    void openWrite();
    void writeByte();

    void closeFiles();

    void loadProgram(uint32_t targetAddress);
    void deleteFile();
    void changeDir();
    void changeDirUp();
    void loadRaw();
    void build();
};
