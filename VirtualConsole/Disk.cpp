#include "Disk.h"
#include "Bus.h"
#include "Compiler.h"

#include <cctype>
#include <sstream>

Disk* Disk::lastExecDisk = nullptr;

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
        case 8: loadProgram(LOAD_ADDRESS); break;
        case 9: deleteFile(); break;
        case 10: loadProgram(SHELL_LOAD_ADDRESS); break;
        case 11: changeDir(); break;
        case 12: changeDirUp(); break;
        case 13: loadRaw(LOAD_ADDRESS); break;
        case 14: build(); break;
        case 15: loadChildRun(EXEC_CHILD_DEPTH2_ADDRESS); break;
        case 16: loadChildRun(EXEC_CHILD_DEPTH3_ADDRESS); break;
        case 17: loadChildRun(EXEC_CHILD_DEPTH4_ADDRESS); break;
        case 18: loadChildRun(EXEC_CHILD_DEPTH5_ADDRESS); break;
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

    dirIt = std::filesystem::directory_iterator(basePath / currentDir, ec);

    if (ec)
    {
        status = 2;
        return;
    }

    populateNameFromIterator();
}

void Disk::listNext()
{
    if (dirIt != std::filesystem::directory_iterator())
    {
        std::error_code ec;
        dirIt.increment(ec);
    }

    populateNameFromIterator();
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

    // Папки перечисляем вместе с файлами (не только is_regular_file),
    // отмечая их хвостовым "/" в NAME - так dir сразу отличает папку
    // от файла (GAMES/ vs GAMES), без новых регистров на устройстве.
    if (dirIt->is_directory() && fileName.size() < 12)
    {
        fileName += '/';
    }

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

    readStream.open(basePath / currentDir / nameAsString(), std::ios::binary);

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

    writeStream.open(basePath / currentDir / nameAsString(), std::ios::binary | std::ios::trunc);

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

void Disk::loadProgram(uint32_t targetAddress)
{
    // Читаем NAME как текстовый .asm-файл (не бинарно - это исходник
    // ассемблера, не машинный код), собираем тем же Assembler, что
    // main.cpp использует для boot.asm, и кладём результат в RAM по
    // targetAddress (LOAD_ADDRESS для exec/поке-программ,
    // SHELL_LOAD_ADDRESS для резидентного SHELL.ASM). Ассемблер
    // резолвит метки относительно targetAddress (origin) - иначе
    // JMP/CALL на метки резолвились бы так, будто код лежит на
    // адресе 0.

    std::ifstream sourceFile(basePath / currentDir / nameAsString());

    if (!sourceFile)
    {
        status = 2;
        fileSize = 0;
        return;
    }

    if (targetAddress == LOAD_ADDRESS)
    {
        // Именно песочница exec/poke+run (не SHELL_LOAD_ADDRESS -
        // загрузка самого SHELL.ASM при старте VM тут ни при чём) -
        // запоминаем, какой диск реально запустил текущую программу,
        // чтобы PngLoader/MapLoader/ModLoader резолвили СВОИ файлы
        // относительно него же, а не всегда относительно диска C
        // (см. Disk.h, lastExecDisk).
        lastExecDisk = this;
    }

    std::stringstream buffer;
    buffer << sourceFile.rdbuf();

    std::vector<uint8_t> machineCode;

    try
    {
        machineCode = assembler.assemble(buffer.str(), targetAddress);
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
            targetAddress + static_cast<uint32_t>(i),
            machineCode[i]
        );
    }

    fileSize = static_cast<uint32_t>(machineCode.size());
    status = 0;
}

void Disk::deleteFile()
{
    std::error_code ec;

    bool removed = std::filesystem::remove(basePath / currentDir / nameAsString(), ec);

    status = (!ec && removed) ? 0 : 2;
}

void Disk::changeDir()
{
    std::error_code ec;

    std::filesystem::path target = basePath / currentDir / nameAsString();

    if (!std::filesystem::is_directory(target, ec) || ec)
    {
        status = 2;
        return;
    }

    currentDir /= nameAsString();
    status = 0;
}

void Disk::changeDirUp()
{
    // Уже в корне - тихо ничего не делаем (как в DOS).
    currentDir = currentDir.parent_path();
    status = 0;
}

void Disk::loadRaw(uint32_t targetAddress)
{
    // В отличие от loadProgram - NAME здесь уже ГОТОВЫЙ машинный код
    // (см. build() ниже), не текстовый исходник - копируем байты как
    // есть, без ассемблера. targetAddress здесь всегда LOAD_ADDRESS -
    // обычный запуск (см. SHELL.ASM, cmd_autorun/cmd_exec_run), КУДА
    // .RUN и был собран (build() всегда использует origin =
    // LOAD_ADDRESS), поэтому байты можно копировать как есть, без
    // релокации. Запуск ИЗНУТРИ уже выполняющейся программы (Мини-C
    // exec_child(), см. FM.MC) идёт через ОТДЕЛЬНЫЙ loadChildRun() -
    // там адрес другой (CHILD_LOAD_ADDRESS), и внутренние
    // JMP/CALL/LDA/STA программы на свои же метки/переменные нужно
    // сдвигать (см. loadChildRun() ниже, ASSEMBLY.md - "LOAD_CHILD").

    std::ifstream file(basePath / currentDir / nameAsString(), std::ios::binary);

    if (!file)
    {
        status = 2;
        fileSize = 0;
        return;
    }

    // Тот же диск, что и loadProgram() отмечает при LOAD - программа,
    // запущенная из .RUN, тоже должна резолвить свои PNG/карты/.mod
    // относительно правильного диска (см. Disk.h, lastExecDisk).
    lastExecDisk = this;

    std::vector<uint8_t> data(
        (std::istreambuf_iterator<char>(file)),
        std::istreambuf_iterator<char>()
    );

    for (size_t i = 0; i < data.size(); i++)
    {
        bus->write(targetAddress + static_cast<uint32_t>(i), data[i]);
    }

    fileSize = static_cast<uint32_t>(data.size());
    status = 0;
}

void Disk::loadChildRun(uint32_t targetAddress)
{
    // Команды 15-18 (LOAD_CHILD, по одной на каждый уровень
    // вложенности - см. SHELL.ASM::shell_exec_child) - запускают NAME
    // (уже готовый .RUN, собранный build() под LOAD_ADDRESS) ИЗНУТРИ
    // уже выполняющейся программы, по targetAddress (одному из
    // EXEC_CHILD_DEPTHn_ADDRESS, см. Мини-C exec_child(), FM.MC).
    // Простое копирование байт как в loadRaw() тут не годится: все
    // внутренние JMP/CALL/LDA/STA программы на свои же метки/
    // переменные - это абсолютные адреса, вычисленные под
    // LOAD_ADDRESS, а код физически окажется по targetAddress - без
    // сдвига они указывали бы не туда. Поэтому читаем ещё и
    // <стем>.REL - таблицу смещений таких адресов, которую build()
    // сохраняет рядом с .RUN (см. build(), Assembler::assemble()), и
    // патчим их на разницу (targetAddress - LOAD_ADDRESS) прямо в
    // буфере перед записью в RAM.

    std::string runName = nameAsString();

    std::ifstream runFile(basePath / currentDir / runName, std::ios::binary);

    if (!runFile)
    {
        status = 2;
        fileSize = 0;
        return;
    }

    std::vector<uint8_t> data(
        (std::istreambuf_iterator<char>(runFile)),
        std::istreambuf_iterator<char>()
    );

    size_t dot = runName.find_last_of('.');
    std::string stem = (dot == std::string::npos) ? runName : runName.substr(0, dot);

    std::ifstream relFile(basePath / currentDir / (stem + ".REL"), std::ios::binary);

    if (!relFile)
    {
        // .RUN собран до появления релокации (или .REL удалён) - без
        // таблицы смещений безопасно запустить как дочернюю программу
        // нельзя, нужно пересобрать через build().
        status = 2;
        fileSize = 0;
        return;
    }

    uint32_t relocationCount = 0;
    relFile.read(reinterpret_cast<char*>(&relocationCount), sizeof(relocationCount));

    std::vector<uint32_t> relocations(relocationCount);
    relFile.read(
        reinterpret_cast<char*>(relocations.data()),
        static_cast<std::streamsize>(relocationCount) * sizeof(uint32_t)
    );

    int64_t delta = static_cast<int64_t>(targetAddress) - static_cast<int64_t>(LOAD_ADDRESS);

    for (uint32_t offset : relocations)
    {
        if (static_cast<uint64_t>(offset) + 4 > data.size())
        {
            continue;   // защита от повреждённого/рассогласованного .REL
        }

        uint32_t address =
            static_cast<uint32_t>(data[offset]) |
            (static_cast<uint32_t>(data[offset + 1]) << 8) |
            (static_cast<uint32_t>(data[offset + 2]) << 16) |
            (static_cast<uint32_t>(data[offset + 3]) << 24);

        address = static_cast<uint32_t>(static_cast<int64_t>(address) + delta);

        data[offset] = static_cast<uint8_t>(address & 0xFF);
        data[offset + 1] = static_cast<uint8_t>((address >> 8) & 0xFF);
        data[offset + 2] = static_cast<uint8_t>((address >> 16) & 0xFF);
        data[offset + 3] = static_cast<uint8_t>((address >> 24) & 0xFF);
    }

    lastExecDisk = this;

    for (size_t i = 0; i < data.size(); i++)
    {
        bus->write(targetAddress + static_cast<uint32_t>(i), data[i]);
    }

    fileSize = static_cast<uint32_t>(data.size());
    status = 0;
}

void Disk::build()
{
    // Ассемблирует NAME (текстовый .asm - как loadProgram) и пишет
    // результат НЕ в RAM, а в новый файл на диске: то же имя, но
    // расширение заменено на .RUN (или дописано, если расширения не
    // было). Собирается с тем же origin (LOAD_ADDRESS), что и обычный
    // exec, - иначе метки в .RUN резолвились бы не туда, куда его
    // потом кладёт loadRaw().

    std::ifstream sourceFile(basePath / currentDir / nameAsString());

    if (!sourceFile)
    {
        status = 2;
        fileSize = 0;
        return;
    }

    std::stringstream buffer;
    buffer << sourceFile.rdbuf();

    std::string sourceText = buffer.str();

    // Расширение .MC (регистронезависимо) - сначала прогоняем через
    // компилятор мини-C, получаем ASM-текст и отдаём его тому же
    // ассемблеру, что и обычный .ASM - см. Compiler.h/ASSEMBLY.md,
    // "Мини-C".
    {
        std::string nameUpper = nameAsString();
        for (char& c : nameUpper) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));

        if (nameUpper.size() >= 3 && nameUpper.substr(nameUpper.size() - 3) == ".MC")
        {
            try
            {
                Compiler compiler;
                sourceText = compiler.compile(sourceText);
            }
            catch (const std::exception&)
            {
                status = 2;
                fileSize = 0;
                return;
            }
        }
    }

    std::vector<uint8_t> machineCode;
    std::vector<uint32_t> relocations;

    try
    {
        machineCode = assembler.assemble(sourceText, LOAD_ADDRESS, &relocations);
    }
    catch (const std::exception&)
    {
        status = 2;
        fileSize = 0;
        return;
    }

    std::string sourceName = nameAsString();
    size_t dot = sourceName.find_last_of('.');
    std::string stem = (dot == std::string::npos) ? sourceName : sourceName.substr(0, dot);
    std::string outputName = stem + ".RUN";

    std::ofstream outFile(basePath / currentDir / outputName, std::ios::binary | std::ios::trunc);

    if (!outFile)
    {
        status = 2;
        fileSize = 0;
        return;
    }

    outFile.write(reinterpret_cast<const char*>(machineCode.data()), machineCode.size());

    // Таблица релокаций рядом с .RUN - список смещений (относительно
    // начала машинного кода), где лежат 4-байтные адреса, полученные
    // из МЕТКИ (не числового литерала) - нужна, чтобы Disk::
    // loadChildRun() (команда 15) могла корректно запустить эту же
    // программу по ДРУГОМУ адресу (CHILD_LOAD_ADDRESS), сдвинув такие
    // адреса на разницу - см. Assembler::assemble(), ASSEMBLY.md,
    // "LOAD_CHILD". Формат: 4 байта - количество смещений (uint32 LE),
    // затем сами смещения по 4 байта (uint32 LE).
    std::ofstream relFile(basePath / currentDir / (stem + ".REL"), std::ios::binary | std::ios::trunc);

    if (relFile)
    {
        uint32_t count = static_cast<uint32_t>(relocations.size());
        relFile.write(reinterpret_cast<const char*>(&count), sizeof(count));
        relFile.write(reinterpret_cast<const char*>(relocations.data()), relocations.size() * sizeof(uint32_t));
    }

    fileSize = static_cast<uint32_t>(machineCode.size());
    status = 0;
}
