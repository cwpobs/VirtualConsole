#pragma once

#include "Device.h"
#include "Assembler.h"

#include <string>
#include <fstream>
#include <filesystem>
#include <vector>

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

    // Полный путь (basePath/currentDir на МОМЕНТ запуска), откуда был
    // загружен ТЕКУЩИЙ выполняющийся top-level процесс - то же самое
    // событие, что обновляет lastExecDisk (loadProgram/loadRaw), плюс
    // сама loadChildRun() при успешном запуске вложенного уровня (см.
    // ниже). Нужно loadChildRun() для резервного поиска дочернего
    // *.RUN "рядом с тем, кто его запускает" (например, C/TOOLS/
    // VIEW.MC естественно лежит рядом с C/TOOLS/FM.MC, которая его
    // запускает через exec_child() по F3) - без этого пришлось бы
    // либо копировать *.RUN в КАЖДУЮ папку, куда панель FM.MC может
    // забрести, либо держать его в одном специально оговорённом месте
    // (например, в корне диска) независимо от того, где на самом деле
    // лежит вызывающая программа. Пустой путь - ещё ни разу не
    // запускался.
    static std::filesystem::path lastExecDir;

private:

    // Адрес в RAM, куда LOAD (8) кладёт собранный код - та же
    // "песочница", что уже использует poke/run/exec (см. ASSEMBLY.md).
    static const uint32_t LOAD_ADDRESS = 0x00002000;

    // Отдельный адрес для LOAD_SHELL (10) - резидентное место
    // SHELL.ASM. Обязательно другой, чем LOAD_ADDRESS: shell.asm
    // живёт там постоянно, пока работает VM, а песочницу poke/run
    // затирает при каждой команде - если бы они делили один адрес,
    // poke переписывал бы код самого shell'а.
    //
    // Зазор LOAD_ADDRESS..SHELL_LOAD_ADDRESS - это весь размер
    // песочницы exec/run/.RUN. Изначально было 0x1000 (4 КиБ) -
    // этого хватало, пока все exec'нутые программы были маленькими,
    // но SNAKE.MC (первая по-настоящему большая программа, что
    // рукописная, что собранная мини-C компилятором) скомпилировалась
    // в 5146 байт и вылезла за эту границу, затерев начало
    // резидентного SHELL.ASM прямо во время своего исполнения -
    // отсюда разгон PC/HL без всякого участия клавиатуры. RAM - 4 МБ
    // с адреса 0 (MMIO - только с 0xF0000000, см. main.cpp), места
    // с большим запасом хватает - подняли зазор до ~120 КиБ.
    static const uint32_t SHELL_LOAD_ADDRESS = 0x00020000;

    // "Стек" песочниц для программ, запускаемых ИЗНУТРИ уже
    // выполняющейся программы (вложенный exec) - см. Мини-C builtin
    // exec_child() и SHELL.ASM::shell_exec_child, который решает,
    // какой из этих адресов использовать, по текущей глубине
    // вложенности (execDepth). Программа, вызвавшая exec_child(), сама
    // выполняется по LOAD_ADDRESS (глубина 1) - если бы дочернюю
    // программу грузили туда же, загрузка затёрла бы код, который в
    // этот момент как раз исполняется, поэтому у каждого следующего
    // уровня - СВОЙ адрес.
    //
    // RAM - 4 МиБ (0x00000000-0x003FFFFF, см. main.cpp), а
    // LOAD_ADDRESS..SHELL_LOAD_ADDRESS - только ~120 КиБ рядом с
    // резидентным SHELL.ASM. Экономить незачем - эти адреса лежат в
    // ОТДЕЛЬНОЙ, большой области намного выше SHELL_LOAD_ADDRESS, по
    // 256 КиБ на уровень (с большим запасом - самая большая программа
    // в проекте, FM.MC, весит около 20 КБ), и не мешают ни
    // LOAD_ADDRESS, ни SHELL_LOAD_ADDRESS.
    static const uint32_t EXEC_CHILD_DEPTH2_ADDRESS = 0x00100000;
    static const uint32_t EXEC_CHILD_DEPTH3_ADDRESS = 0x00140000;
    static const uint32_t EXEC_CHILD_DEPTH4_ADDRESS = 0x00180000;
    static const uint32_t EXEC_CHILD_DEPTH5_ADDRESS = 0x001C0000;

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

    // Переименование (REMEMBER_RENAME_FROM=20, RENAME=21, см.
    // ASSEMBLY.md, "Disk") - NAME хранит только ОДНО имя одновременно,
    // а переименованию нужны два (старое и новое) - REMEMBER_RENAME_FROM
    // копирует сюда текущий NAME (старое имя) ДО того, как программа
    // перезапишет NAME новым именем и пошлёт RENAME.
    uint8_t renameFrom[12];

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
    void makeDir();
    void rememberRenameFrom();
    void renameFile();
    void changeDir();
    void changeDirUp();
    void loadRaw(uint32_t targetAddress);
    void build();
    void loadChildRun(uint32_t targetAddress);

    // Читает .RUN (формат - см. build()): заголовок (таблица
    // релокаций) + машинный код в одном файле. Возвращает false, если
    // файл не открылся - используется и loadRaw(), и loadChildRun().
    // Ищет в currentDir - см. readRunFileFrom()/readRunFileAt() для
    // поиска по другой папке (резервный поиск, loadChildRun()).
    bool readRunFile(
        const std::string& fileName,
        std::vector<uint8_t>& code,
        std::vector<uint32_t>& relocations
    );

    // То же самое, но по явно заданной папке ОТНОСИТЕЛЬНО basePath
    // ЭТОГО диска (а не currentDir) - нужно loadChildRun() для
    // резервного поиска в КОРНЕ диска (см. ASSEMBLY.md, "LOAD_CHILD").
    bool readRunFileFrom(
        const std::filesystem::path& dir,
        const std::string& fileName,
        std::vector<uint8_t>& code,
        std::vector<uint32_t>& relocations
    );

    // То же самое, но по УЖЕ ПОЛНОМУ пути (basePath не примешивается) -
    // нужно loadChildRun() для резервного поиска через lastExecDir,
    // который может указывать на ДРУГОЙ диск (свой basePath) - в
    // отличие от readRunFileFrom(), где dir всегда относительно ЭТОГО
    // диска. readRunFile()/readRunFileFrom() - тонкие обёртки над этой
    // функцией.
    bool readRunFileAt(
        const std::filesystem::path& fullDir,
        const std::string& fileName,
        std::vector<uint8_t>& code,
        std::vector<uint32_t>& relocations
    );
};
