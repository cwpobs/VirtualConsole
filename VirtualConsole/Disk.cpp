#include "Disk.h"
#include "Bus.h"
#include "Compiler.h"

#include <cctype>
#include <sstream>

Disk* Disk::lastExecDisk = nullptr;
std::filesystem::path Disk::lastExecDir;

namespace
{
    std::string trimForInclude(const std::string& s)
    {
        size_t start = s.find_first_not_of(" \t\r\n");
        if (start == std::string::npos) return "";
        size_t end = s.find_last_not_of(" \t\r\n");
        return s.substr(start, end - start + 1);
    }
}

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
        case 19: makeDir(); break;
        case 20: rememberRenameFrom(); break;
        case 21: renameFile(); break;
        case 22: readErrorByte(); break;
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
        lastExecDir = basePath / currentDir;
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

void Disk::makeDir()
{
    // MKDIR (19) - создаёт папку NAME в текущей папке (F7 в FM.MC, см.
    // ASSEMBLY.md, "Disk"). create_directory() возвращает false (без
    // ec), если папка с таким именем уже есть - тот же STATUS=2, что и
    // прочие отказы здесь, отдельно не различаем "уже есть" от
    // "невалидное имя".
    std::error_code ec;

    bool created = std::filesystem::create_directory(basePath / currentDir / nameAsString(), ec);

    status = (!ec && created) ? 0 : 2;
}

void Disk::rememberRenameFrom()
{
    // REMEMBER_RENAME_FROM (20) - просто запоминает текущий NAME (F2 в
    // FM.MC уже написал туда СТАРОЕ имя перед этой командой) - RENAME
    // (21) читает его отсюда, когда NAME уже перезаписан НОВЫМ именем.
    for (int i = 0; i < 12; i++)
    {
        renameFrom[i] = name[i];
    }
    status = 0;
}

void Disk::renameFile()
{
    // RENAME (21) - переименовывает renameFrom (старое имя, см.
    // rememberRenameFrom() выше) в текущий NAME (новое имя), оба - в
    // ТЕКУЩЕЙ папке.
    std::string oldName;
    for (int i = 0; i < 12 && renameFrom[i] != 0; i++)
    {
        oldName += static_cast<char>(renameFrom[i]);
    }

    std::error_code ec;
    std::filesystem::rename(basePath / currentDir / oldName, basePath / currentDir / nameAsString(), ec);

    status = ec ? 2 : 0;
}

void Disk::readErrorByte()
{
    // READ_ERROR_BYTE (22) - отдаёт lastBuildError (см. build()) байт
    // за байтом через тот же регистр DATA (14), что и READ_BYTE - и с
    // той же конвенцией STATUS==1 значит "конец" (тут - конец текста
    // ошибки, а не файла). Позволяет шеллу напечатать РЕАЛЬНЫЙ текст
    // ошибки компилятора/ассемблера после неудачного BUILD, а не
    // просто "ничего не произошло" (см. cmd_build_c/d в SHELL.ASM).
    if (buildErrorPos >= lastBuildError.size())
    {
        status = 1;
        return;
    }

    dataByte = static_cast<uint8_t>(lastBuildError[buildErrorPos]);
    buildErrorPos++;
    status = 0;
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

bool Disk::readRunFile(
    const std::string& fileName,
    std::vector<uint8_t>& code,
    std::vector<uint32_t>& relocations)
{
    return readRunFileFrom(currentDir, fileName, code, relocations);
}

bool Disk::readRunFileFrom(
    const std::filesystem::path& dir,
    const std::string& fileName,
    std::vector<uint8_t>& code,
    std::vector<uint32_t>& relocations)
{
    return readRunFileAt(basePath / dir, fileName, code, relocations);
}

bool Disk::readRunFileAt(
    const std::filesystem::path& fullDir,
    const std::string& fileName,
    std::vector<uint8_t>& code,
    std::vector<uint32_t>& relocations)
{
    // Общий формат .RUN (см. build() ниже): сначала заголовок -
    // таблица релокаций (4 байта - количество N, uint32 LE, затем N *
    // 4 байта смещений, uint32 LE каждое - те самые смещения, что
    // возвращает Assembler::assemble() третьим параметром), сразу за
    // ним - сам машинный код. Раньше таблица релокаций лежала в
    // отдельном файле ИМЯ.REL - теперь один файл, один формат.
    //
    // В отличие от readRunFileFrom() - fullDir здесь УЖЕ полный путь
    // (не примешивается к basePath ЭТОГО диска) - нужно для
    // lastExecDir, который может указывать на ДРУГОЙ диск (свой
    // basePath), см. loadChildRun().

    std::ifstream file(fullDir / fileName, std::ios::binary);

    if (!file)
    {
        return false;
    }

    uint32_t relocationCount = 0;
    file.read(reinterpret_cast<char*>(&relocationCount), sizeof(relocationCount));

    relocations.assign(relocationCount, 0);
    if (relocationCount > 0)
    {
        file.read(
            reinterpret_cast<char*>(relocations.data()),
            static_cast<std::streamsize>(relocationCount) * sizeof(uint32_t)
        );
    }

    code.assign(
        (std::istreambuf_iterator<char>(file)),
        std::istreambuf_iterator<char>()
    );

    return true;
}

void Disk::loadRaw(uint32_t targetAddress)
{
    // В отличие от loadProgram - NAME здесь уже ГОТОВЫЙ машинный код
    // (см. build() ниже), не текстовый исходник - копируем байты как
    // есть, без ассемблера. targetAddress здесь всегда LOAD_ADDRESS -
    // обычный запуск (см. SHELL.ASM, cmd_autorun/cmd_exec_run), КУДА
    // .RUN и был собран (build() всегда использует origin =
    // LOAD_ADDRESS), поэтому релокация не нужна (дельта 0) - таблица
    // релокаций из заголовка файла тут просто игнорируется. Запуск
    // ИЗНУТРИ уже выполняющейся программы (Мини-C exec_child(), см.
    // FM.MC) идёт через ОТДЕЛЬНЫЙ loadChildRun() - там адрес другой
    // (EXEC_CHILD_DEPTHn_ADDRESS), и внутренние JMP/CALL/LDA/STA
    // программы на свои же метки/переменные нужно сдвигать (см.
    // loadChildRun() ниже, ASSEMBLY.md - "LOAD_CHILD").

    std::vector<uint8_t> code;
    std::vector<uint32_t> relocations;

    if (!readRunFile(nameAsString(), code, relocations))
    {
        status = 2;
        fileSize = 0;
        return;
    }

    // Тот же диск, что и loadProgram() отмечает при LOAD - программа,
    // запущенная из .RUN, тоже должна резолвить свои PNG/карты/.mod
    // относительно правильного диска (см. Disk.h, lastExecDisk).
    lastExecDisk = this;
    lastExecDir = basePath / currentDir;

    for (size_t i = 0; i < code.size(); i++)
    {
        bus->write(targetAddress + static_cast<uint32_t>(i), code[i]);
    }

    fileSize = static_cast<uint32_t>(code.size());
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
    // сдвига они указывали бы не туда. Поэтому используем таблицу
    // релокаций из заголовка .RUN (см. readRunFile(), build()) и
    // патчим смещённые адреса на разницу (targetAddress - LOAD_ADDRESS)
    // прямо в буфере перед записью в RAM.

    std::vector<uint8_t> code;
    std::vector<uint32_t> relocations;

    if (!readRunFile(nameAsString(), code, relocations))
    {
        // Не нашли в ТЕКУЩЕЙ папке (у FM.MC currentDir постоянно
        // меняется вслед за панелями) - резервный поиск, в два шага:
        //
        // 1) Там, откуда был загружен ТЕКУЩИЙ выполняющийся top-level
        //    процесс (lastExecDir - тот же трекинг, что уже используют
        //    PngLoader/MapLoader/ModLoader для СВОИХ файлов, см.
        //    Disk.h). Общая утилита (например, C/TOOLS/VIEW.MC)
        //    естественно лежит РЯДОМ с программой, которая её
        //    запускает через exec_child() (C/TOOLS/FM.MC) - достаточно
        //    собрать её один раз в той же папке, никуда специально не
        //    копировать и не класть в оговорённое заранее место.
        // 2) В КОРНЕ диска - запасной вариант, если по каким-то
        //    причинам утилита лежит не рядом с вызывающей программой.
        //
        // Обычный LOAD_RAW (loadRaw() выше, не через exec_child) в
        // этом не нуждается - там NAME всегда готовится вызывающим
        // кодом непосредственно перед командой, в ТЕКУЩЕЙ папке. См.
        // ASSEMBLY.md, "LOAD_CHILD".
        bool foundNearby = !lastExecDir.empty() &&
            readRunFileAt(lastExecDir, nameAsString(), code, relocations);

        if (!foundNearby && !readRunFileFrom(std::filesystem::path(), nameAsString(), code, relocations))
        {
            status = 2;
            fileSize = 0;
            return;
        }
    }

    int64_t delta = static_cast<int64_t>(targetAddress) - static_cast<int64_t>(LOAD_ADDRESS);

    for (uint32_t offset : relocations)
    {
        if (static_cast<uint64_t>(offset) + 4 > code.size())
        {
            continue;   // защита от повреждённого/рассогласованного заголовка
        }

        uint32_t address =
            static_cast<uint32_t>(code[offset]) |
            (static_cast<uint32_t>(code[offset + 1]) << 8) |
            (static_cast<uint32_t>(code[offset + 2]) << 16) |
            (static_cast<uint32_t>(code[offset + 3]) << 24);

        address = static_cast<uint32_t>(static_cast<int64_t>(address) + delta);

        code[offset] = static_cast<uint8_t>(address & 0xFF);
        code[offset + 1] = static_cast<uint8_t>((address >> 8) & 0xFF);
        code[offset + 2] = static_cast<uint8_t>((address >> 16) & 0xFF);
        code[offset + 3] = static_cast<uint8_t>((address >> 24) & 0xFF);
    }

    lastExecDisk = this;
    // lastExecDir НЕ трогаем здесь (в отличие от lastExecDisk) - в
    // отличие от диска (которым родитель и вложенный потомок часто
    // делят), "папка запуска" обязана остаться папкой ВЕРХНЕУРОВНЕВОЙ
    // программы (см. loadProgram()/loadRaw() выше, где lastExecDir
    // выставляется) на всё время её работы: если перезаписать её здесь
    // на currentDir (где сейчас панель FM.MC, а не где лежит сама
    // FM.MC), резервный поиск LOAD_CHILD в следующий раз будет искать
    // *.RUN не там - ровно такой баг уже был здесь (после первого
    // успешного запуска VIEW.MC из НЕ-своей папки F3 переставала
    // находить VIEW.RUN, пока currentDir снова не окажется в её
    // собственной папке).

    for (size_t i = 0; i < code.size(); i++)
    {
        bus->write(targetAddress + static_cast<uint32_t>(i), code[i]);
    }

    fileSize = static_cast<uint32_t>(code.size());
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

    lastBuildError.clear();
    buildErrorPos = 0;

    std::ifstream sourceFile(basePath / currentDir / nameAsString());

    if (!sourceFile)
    {
        lastBuildError = "исходный файл не найден";
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
            // #include "ИМЯ.MC" - подключаемые библиотеки. Ищутся ВСЕГДА на
            // диске C, в DEV/LIB (буквальный путь "C/DEV/LIB/...", не через
            // basePath/currentDir этого Disk - библиотеки не зависят от
            // того, с какого диска реально собирается программа). Строка
            // с #include заменяется на пустую (не удаляется), чтобы номера
            // строк ОСТАЛЬНОГО кода файла не сдвинулись - см. ASSEMBLY.md,
            // "Мини-C". Имя библиотеки резолвится как обычный host-путь
            // через ifstream, до всякого реального лексера Mini-C - оно НЕ
            // проходит через 12-байтный NAME-регистр протокол Disk, поэтому
            // не ограничено форматом 8.3, в отличие от имён .MC/.RUN.
            std::vector<std::string> libSources;
            std::istringstream in(sourceText);
            std::ostringstream stripped;
            std::string line;
            bool includeError = false;

            while (std::getline(in, line))
            {
                std::string trimmed = trimForInclude(line);
                if (trimmed.rfind("#include", 0) == 0)
                {
                    size_t q1 = trimmed.find('"');
                    size_t q2 = (q1 == std::string::npos) ? std::string::npos
                                                            : trimmed.find('"', q1 + 1);
                    if (q1 == std::string::npos || q2 == std::string::npos)
                    {
                        includeError = true;
                        break;
                    }
                    std::string libName = trimmed.substr(q1 + 1, q2 - q1 - 1);
                    std::ifstream libFile(std::filesystem::path("C") / "DEV" / "LIB" / libName);
                    if (!libFile)
                    {
                        includeError = true;
                        break;
                    }
                    std::stringstream libBuf;
                    libBuf << libFile.rdbuf();
                    libSources.push_back(libBuf.str());
                    stripped << "\n";
                }
                else
                {
                    stripped << line << "\n";
                }
            }

            if (includeError)
            {
                lastBuildError = "ошибка #include - библиотека не найдена или "
                    "строка с #include повреждена";
                status = 2;
                fileSize = 0;
                return;
            }

            sourceText = stripped.str();

            try
            {
                Compiler compiler;
                sourceText = compiler.compile(sourceText, libSources);
            }
            catch (const std::exception& e)
            {
                lastBuildError = e.what();
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
    catch (const std::exception& e)
    {
        lastBuildError = e.what();
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

    // Заголовок .RUN - таблица релокаций (см. readRunFile()): список
    // смещений (относительно начала машинного кода, идущего сразу за
    // заголовком), где лежат 4-байтные адреса, полученные из МЕТКИ (не
    // числового литерала) - нужна, чтобы Disk::loadChildRun() (команды
    // 15-18) могла корректно запустить эту же программу по ДРУГОМУ
    // адресу, сдвинув такие адреса на разницу - см.
    // Assembler::assemble(), ASSEMBLY.md, "LOAD_CHILD". Формат: 4 байта
    // - количество смещений (uint32 LE), затем сами смещения по 4
    // байта (uint32 LE) - один файл, без отдельного .REL.
    uint32_t relocationCount = static_cast<uint32_t>(relocations.size());
    outFile.write(reinterpret_cast<const char*>(&relocationCount), sizeof(relocationCount));
    outFile.write(reinterpret_cast<const char*>(relocations.data()), relocations.size() * sizeof(uint32_t));

    outFile.write(reinterpret_cast<const char*>(machineCode.data()), machineCode.size());

    // SIZE - сколько байт реально записано в файл (заголовок + код),
    // в отличие от loadRaw()/loadChildRun(), где SIZE - размер только
    // самого кода, загруженного в RAM (см. ASSEMBLY.md, "BUILD").
    fileSize = static_cast<uint32_t>(sizeof(relocationCount) + relocations.size() * sizeof(uint32_t) + machineCode.size());
    status = 0;
}
