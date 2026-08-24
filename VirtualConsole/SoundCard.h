#pragma once

#include "Device.h"

#include <atomic>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

// Разобранный .mod-файл (см. ModLoader - парсинг формата целиком там,
// SoundCard только ПРОИГРЫВАЕТ уже готовую структуру). Индексация
// сэмплов - 1..31 (как в самом формате MOD), samples[0] не используется.
struct ModSample
{
    std::vector<int8_t> data;
    uint32_t repeatOffset = 0;   // в байтах
    uint32_t repeatLength = 0;   // в байтах; <= 2 значит "без повтора"
    uint8_t volume = 0;          // 0-64, громкость сэмпла по умолчанию
};

struct ModCell
{
    uint16_t period = 0;
    uint8_t sampleNumber = 0;
    uint8_t effect = 0;
    uint8_t param = 0;
};

struct ModPattern
{
    ModCell cells[64][4];
};

struct ModSong
{
    std::vector<ModSample> samples;    // 32 элемента, индекс 0 не используется
    std::vector<ModPattern> patterns;
    std::vector<uint8_t> orderTable;
    uint8_t songLength = 0;
    uint8_t restartPosition = 0;
};

// Звуковая карта: проигрывает уже разобранную ProTracker-песню
// (ModSong, см. ModLoader.h - разбор формата MOD спрятан там же, где
// PngLoader прячет разбор PNG). Секвенсор+микшер+вывод звука (winmm)
// целиком живут в отдельном std::thread, независимом от цикла CPU -
// та же причина, что у VideoCard: tick() устройства вызывается на
// КАЖДОЕ обращение к шине, любая тяжёлая работа там повторила бы баг
// с Keyboard. SoundCard не переопределяет tick(). См. ASSEMBLY.md,
// раздел "SoundCard".
class SoundCard : public Device
{
public:

    SoundCard();
    ~SoundCard() override;

    uint8_t read(uint32_t address) override;
    void write(uint32_t address, uint8_t value) override;

    // Переносит владение разобранной песней (см. ModLoader::load) -
    // останавливает текущее воспроизведение, сбрасывает секвенсор в
    // начало и переводит устройство в состояние "готово".
    void loadSong(ModSong&& song);

private:

    static const uint32_t REG_COMMAND = 0;
    static const uint32_t REG_STATUS = 1;
    static const uint32_t REG_VOLUME = 2;

    // Регистры визуализации (read-only) - зеркала внутреннего состояния
    // секвенсора, обновляются раз за тик в updateVisualizationRegisters()
    // (см. advanceTick()/resetSequencer()). Читаются с CPU-потока без
    // блокировки songMutex - поэтому именно std::atomic, тем же приёмом,
    // что уже есть у volume. См. ASSEMBLY.md, "SoundCard".
    static const uint32_t REG_CHANNEL0_VOLUME = 3;
    static const uint32_t REG_CHANNEL1_VOLUME = 4;
    static const uint32_t REG_CHANNEL2_VOLUME = 5;
    static const uint32_t REG_CHANNEL3_VOLUME = 6;
    static const uint32_t REG_ROW = 7;
    static const uint32_t REG_ORDER_POS = 8;

    // Регистры "запроса ячейки паттерна" - выбор (PATTERN_ROW_SELECT/
    // PATTERN_CHANNEL_SELECT, оба write-only) + четыре read-only поля
    // ячейки в ТЕКУЩЕМ играющем паттерне (см. getQueryCell() ниже) -
    // нужны PLAYER.MC для "едущих блоков" (живой просмотр нот/сэмплов/
    // эффектов, см. ASSEMBLY.md, "SoundCard"/"Плейлист"). В отличие от
    // REG_CHANNEL*_VOLUME/REG_ROW/REG_ORDER_POS выше, это НЕ зеркала,
    // обновляемые аудио-потоком раз за тик - каждое чтение вычисляет
    // ответ заново по queryRow/queryChannel, поэтому обычные (не
    // atomic) поля вполне достаточны: и запись, и чтение происходят из
    // одного и того же CPU-потока, как и у любого другого write-only/
    // read-only регистра на этой шине.
    static const uint32_t REG_PATTERN_ROW_SELECT = 9;       // write: строка в текущем паттерне, 0-63
    static const uint32_t REG_PATTERN_CHANNEL_SELECT = 10;  // write: канал, 0-3
    static const uint32_t REG_PATTERN_NOTE = 11;            // read: индекс ноты 0-35 (см. PERIOD_TABLE), 255 = нет ноты
    static const uint32_t REG_PATTERN_SAMPLE = 12;          // read: номер сэмпла 0-31 (0 = нет)
    static const uint32_t REG_PATTERN_EFFECT = 13;          // read: номер эффекта 0-15
    static const uint32_t REG_PATTERN_PARAM = 14;           // read: параметр эффекта 0-255

    static const int SAMPLE_RATE = 44100;

    // Стандартная таблица periods ProTracker (finetune = 0, 3 октавы,
    // 36 нот) - нужна, чтобы по текущему period найти "ближайшую
    // ноту" и посчитать period для соседних полутонов (арпеджио,
    // тон-портаменто). См. ASSEMBLY.md, "SoundCard".
    static const uint16_t PERIOD_TABLE[36];

    struct ChannelState
    {
        uint8_t sampleNumber = 0;
        double samplePos = 0.0;
        double sampleStep = 0.0;
        uint16_t period = 0;
        uint16_t basePeriod = 0;
        uint16_t portaTarget = 0;
        uint8_t portaSpeed = 0;
        uint8_t volume = 0;
        uint8_t volSlideParam = 0;
        uint8_t arpeggioParam = 0;
        uint8_t portaUpMemory = 0;
        uint8_t portaDownMemory = 0;
        uint8_t effect = 0;
        uint8_t effectParam = 0;
        bool playing = false;
    };

    uint8_t status;
    std::atomic<uint8_t> volume;   // читается из аудио-потока в renderSamples

    // Зеркала для регистров визуализации (см. REG_CHANNEL*_VOLUME/REG_ROW/
    // REG_ORDER_POS выше) - обновляются updateVisualizationRegisters().
    std::atomic<uint8_t> channelVolumeAtomic[4]{};
    std::atomic<uint8_t> rowAtomic{0};
    std::atomic<uint8_t> orderPosAtomic{0};

    ModSong song;
    bool songLoaded;
    std::mutex songMutex;   // защищает song/songLoaded от гонки LOAD во время PLAY

    // Выбор для REG_PATTERN_NOTE/SAMPLE/EFFECT/PARAM (см. getQueryCell()
    // ниже) - обычные поля, не atomic (см. комментарий у REG_PATTERN_*
    // выше про то, почему этого достаточно).
    uint8_t queryRow = 0;
    uint8_t queryChannel = 0;

    // Состояние секвенсора - трогается только аудио-потоком, пока он
    // жив; play()/stop() синхронизируются через playRequested/stopRequested.
    ChannelState channels[4];
    int orderPos;
    int row;
    int currentTick;
    uint8_t speed;
    uint16_t tempo;
    int samplesRemainingInTick;
    bool positionJumpPending;
    int positionJumpTo;
    bool patternBreakPending;
    int patternBreakRow;

    std::thread audioThread;
    std::atomic<bool> playing;
    std::atomic<bool> paused;
    std::atomic<bool> stopRequested;

    void play();
    void stop();
    void pause();
    void resume();

    void resetSequencer();
    void updateVisualizationRegisters();
    void advanceRow();
    void applyContinuousEffects(int tick);
    void advanceTick();
    void renderSamples(int16_t* out, int frameCount);
    static double periodToFrequency(uint16_t period);
    static uint16_t periodForSemitoneOffset(uint16_t basePeriod, int semitoneOffset);

    // См. REG_PATTERN_* выше - для "едущих блоков" PLAYER.MC. Читают
    // song/orderPosAtomic под songMutex (song заменяется целиком в
    // loadSong(), см. её комментарий) - возвращают "пустую" ячейку
    // (ModCell{}, period=0) для любого некорректного состояния (песня
    // не загружена, currentRow/queryChannel вне диапазона и т.п.), а не
    // бросают/падают - тот же стиль, что и у остальных read-регистров
    // этой шины (ASSEMBLY.md, "SoundCard": "статус=..." вместо ошибок).
    ModCell getQueryCell();
    uint8_t queryNoteIndex();

    void audioThreadMain();
};
