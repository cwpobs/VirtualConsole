#include "SoundCard.h"

#include <algorithm>
#include <cmath>

#define NOMINMAX
#include <Windows.h>
#include <mmsystem.h>

#pragma comment(lib, "winmm.lib")

const uint16_t SoundCard::PERIOD_TABLE[36] = {
    856,808,762,720,678,640,604,570,538,508,480,453,
    428,404,381,360,339,320,302,285,269,254,240,226,
    214,202,190,180,170,160,151,143,135,127,120,113
};

SoundCard::SoundCard()
    : playing(false), paused(false), stopRequested(false)
{
    status = 3;         // песня ещё не загружена
    volume = 255;

    songLoaded = false;

    orderPos = 0;
    row = 0;
    currentTick = 0;
    speed = 6;
    tempo = 125;
    samplesRemainingInTick = 0;
    positionJumpPending = false;
    positionJumpTo = 0;
    patternBreakPending = false;
    patternBreakRow = 0;
}

SoundCard::~SoundCard()
{
    stop();
}

uint8_t SoundCard::read(uint32_t address)
{
    switch (address)
    {
    case REG_STATUS: return status;
    case REG_VOLUME: return volume;
    default: return 0;
    }
}

void SoundCard::write(uint32_t address, uint8_t value)
{
    switch (address)
    {
    case REG_COMMAND:
        switch (value)
        {
        case 1: play(); break;
        case 2: stop(); break;
        case 3: pause(); break;
        case 4: resume(); break;
        default: break;
        }
        return;

    case REG_VOLUME:
        volume = value;
        return;

    default:
        return;
    }
}

void SoundCard::loadSong(ModSong&& newSong)
{
    std::lock_guard<std::mutex> lock(songMutex);

    song = std::move(newSong);
    songLoaded = true;
    status = 0;

    resetSequencer();
}

void SoundCard::resetSequencer()
{
    for (int c = 0; c < 4; c++)
    {
        channels[c] = ChannelState();
    }

    orderPos = 0;
    row = 0;
    currentTick = 0;
    speed = 6;
    tempo = 125;
    samplesRemainingInTick = 0;
    positionJumpPending = false;
    positionJumpTo = 0;
    patternBreakPending = false;
    patternBreakRow = 0;
}

void SoundCard::play()
{
    if (!songLoaded)
    {
        status = 3;
        return;
    }

    if (playing)
    {
        if (paused)
        {
            paused = false;
            status = 1;
        }
        return;
    }

    // Поток от предыдущего сеанса мог уже сам завершиться (ошибка
    // waveOutOpen), но остаться незаджойненным - см. VideoCard::modeOn
    // про тот же приём и почему это обязательно.
    if (audioThread.joinable())
    {
        audioThread.join();
    }

    stopRequested = false;
    paused = false;
    playing = true;
    status = 1;

    audioThread = std::thread(&SoundCard::audioThreadMain, this);
}

void SoundCard::stop()
{
    stopRequested = true;

    if (audioThread.joinable())
    {
        audioThread.join();
    }

    playing = false;
    paused = false;
    status = songLoaded ? 0 : 3;
}

void SoundCard::pause()
{
    if (playing && !paused)
    {
        paused = true;
        status = 2;
    }
}

void SoundCard::resume()
{
    if (playing && paused)
    {
        paused = false;
        status = 1;
    }
}

double SoundCard::periodToFrequency(uint16_t period)
{
    if (period == 0)
    {
        return 0.0;
    }

    // Стандартное упрощение ProTracker/FastTracker - period 428
    // (нота C-2 в таблице finetune=0) соответствует эталонной частоте
    // сэмпла 8363 Гц, без поправки на finetune (см. ASSEMBLY.md,
    // "SoundCard").
    return 8363.0 * 428.0 / period;
}

uint16_t SoundCard::periodForSemitoneOffset(uint16_t basePeriod, int semitoneOffset)
{
    int bestIndex = 0;
    int bestDiff = INT32_MAX;

    for (int i = 0; i < 36; i++)
    {
        int diff = std::abs(static_cast<int>(PERIOD_TABLE[i]) - static_cast<int>(basePeriod));
        if (diff < bestDiff)
        {
            bestDiff = diff;
            bestIndex = i;
        }
    }

    int target = bestIndex + semitoneOffset;
    if (target < 0) target = 0;
    if (target > 35) target = 35;

    return PERIOD_TABLE[target];
}

void SoundCard::advanceRow()
{
    // orderPos уже гарантированно в границах (см. конец функции -
    // проверка идёт перед выходом, после того как мы решили, куда
    // двигаться ДАЛЬШЕ).
    uint8_t patternIndex = song.orderTable[orderPos];
    ModPattern& pattern = song.patterns[patternIndex];

    positionJumpPending = false;
    patternBreakPending = false;

    for (int c = 0; c < 4; c++)
    {
        ModCell& cell = pattern.cells[row][c];
        ChannelState& ch = channels[c];

        if (cell.sampleNumber != 0 && cell.sampleNumber < song.samples.size())
        {
            ch.sampleNumber = cell.sampleNumber;
            ch.volume = song.samples[cell.sampleNumber].volume;
        }

        if (cell.period != 0)
        {
            if (cell.effect == 0x3)
            {
                // Тон-портаменто НЕ перезапускает сэмпл - едет к цели
                // с текущей позиции (см. applyContinuousEffects).
                ch.portaTarget = cell.period;
                if (cell.param != 0)
                {
                    ch.portaSpeed = cell.param;
                }
            }
            else
            {
                ch.period = cell.period;
                ch.basePeriod = cell.period;
                ch.samplePos = 0.0;
                ch.playing = true;
                ch.sampleStep = periodToFrequency(cell.period) / SAMPLE_RATE;
            }
        }

        ch.effect = cell.effect;
        ch.effectParam = cell.param;

        switch (cell.effect)
        {
        case 0x0:
            if (cell.param != 0) ch.arpeggioParam = cell.param;
            break;
        case 0xA:
            if (cell.param != 0) ch.volSlideParam = cell.param;
            break;
        case 0xC:
            ch.volume = std::min<uint8_t>(64, cell.param);
            break;
        case 0xB:
            positionJumpPending = true;
            positionJumpTo = cell.param;
            break;
        case 0xD:
            patternBreakPending = true;
            patternBreakRow = ((cell.param >> 4) * 10) + (cell.param & 0x0F);
            if (patternBreakRow > 63) patternBreakRow = 0;
            break;
        case 0xF:
            if (cell.param < 32)
            {
                speed = (cell.param == 0) ? 1 : cell.param;
            }
            else
            {
                tempo = cell.param;
            }
            break;
        default:
            break;
        }
    }

    if (positionJumpPending)
    {
        orderPos = positionJumpTo;
        row = patternBreakPending ? patternBreakRow : 0;
    }
    else if (patternBreakPending)
    {
        orderPos = orderPos + 1;
        row = patternBreakRow;
    }
    else
    {
        row = row + 1;
        if (row >= 64)
        {
            row = 0;
            orderPos = orderPos + 1;
        }
    }

    if (orderPos >= song.songLength)
    {
        orderPos = song.restartPosition;
    }
    if (orderPos >= song.songLength || orderPos < 0)
    {
        orderPos = 0;   // подстраховка на случай кривого restartPosition
    }
}

void SoundCard::applyContinuousEffects(int tick)
{
    for (int c = 0; c < 4; c++)
    {
        ChannelState& ch = channels[c];

        switch (ch.effect)
        {
        case 0x0:   // arpeggio - крутится и на tick 0 (это база)
            if (ch.arpeggioParam != 0 && ch.basePeriod != 0)
            {
                int step = tick % 3;
                int offset = (step == 0) ? 0 : (step == 1 ? (ch.arpeggioParam >> 4) : (ch.arpeggioParam & 0x0F));
                uint16_t p = periodForSemitoneOffset(ch.basePeriod, offset);
                ch.sampleStep = periodToFrequency(p) / SAMPLE_RATE;
            }
            break;

        case 0x1:   // portamento up
            if (tick > 0)
            {
                int amount = ch.effectParam;
                if (amount != 0) ch.portaUpMemory = ch.effectParam;
                else amount = ch.portaUpMemory;

                int newPeriod = static_cast<int>(ch.period) - amount * 4;
                if (newPeriod < 113) newPeriod = 113;
                ch.period = static_cast<uint16_t>(newPeriod);
                ch.sampleStep = periodToFrequency(ch.period) / SAMPLE_RATE;
            }
            break;

        case 0x2:   // portamento down
            if (tick > 0)
            {
                int amount = ch.effectParam;
                if (amount != 0) ch.portaDownMemory = ch.effectParam;
                else amount = ch.portaDownMemory;

                int newPeriod = static_cast<int>(ch.period) + amount * 4;
                if (newPeriod > 856) newPeriod = 856;
                ch.period = static_cast<uint16_t>(newPeriod);
                ch.sampleStep = periodToFrequency(ch.period) / SAMPLE_RATE;
            }
            break;

        case 0x3:   // tone portamento - едет к portaTarget
            if (tick > 0 && ch.portaTarget != 0)
            {
                int amount = ch.portaSpeed * 4;
                int cur = ch.period;
                int target = ch.portaTarget;

                if (cur < target)
                {
                    cur = std::min(target, cur + amount);
                }
                else if (cur > target)
                {
                    cur = std::max(target, cur - amount);
                }

                ch.period = static_cast<uint16_t>(cur);
                ch.sampleStep = periodToFrequency(ch.period) / SAMPLE_RATE;
            }
            break;

        case 0xA:   // volume slide
            if (tick > 0)
            {
                int up = ch.volSlideParam >> 4;
                int down = ch.volSlideParam & 0x0F;

                if (up > 0)
                {
                    ch.volume = static_cast<uint8_t>(std::min(64, ch.volume + up));
                }
                else if (down > 0)
                {
                    ch.volume = static_cast<uint8_t>(std::max(0, ch.volume - down));
                }
            }
            break;

        default:
            break;
        }
    }
}

void SoundCard::advanceTick()
{
    if (currentTick == 0)
    {
        advanceRow();
    }

    applyContinuousEffects(currentTick);

    currentTick++;
    if (currentTick >= speed)
    {
        currentTick = 0;
    }

    double tickMs = 2500.0 / tempo;
    samplesRemainingInTick = static_cast<int>(SAMPLE_RATE * tickMs / 1000.0);
    if (samplesRemainingInTick < 1)
    {
        samplesRemainingInTick = 1;
    }
}

void SoundCard::renderSamples(int16_t* out, int frameCount)
{
    for (int i = 0; i < frameCount; i++)
    {
        if (samplesRemainingInTick <= 0)
        {
            advanceTick();
        }

        float leftF = 0.0f;
        float rightF = 0.0f;

        for (int c = 0; c < 4; c++)
        {
            ChannelState& ch = channels[c];

            if (!ch.playing || ch.sampleNumber == 0 || ch.sampleNumber >= song.samples.size())
            {
                continue;
            }

            ModSample& s = song.samples[ch.sampleNumber];
            if (s.data.empty())
            {
                continue;
            }

            int dataLen = static_cast<int>(s.data.size());
            bool hasLoop = s.repeatLength > 2;
            int loopEnd = static_cast<int>(s.repeatOffset + s.repeatLength);

            int pos = static_cast<int>(ch.samplePos);

            if (hasLoop && pos >= loopEnd)
            {
                int span = static_cast<int>(s.repeatLength);
                pos = static_cast<int>(s.repeatOffset) + ((pos - static_cast<int>(s.repeatOffset)) % span);
                ch.samplePos = pos;
            }
            else if (!hasLoop && pos >= dataLen)
            {
                ch.playing = false;
                continue;
            }

            if (pos < 0 || pos >= dataLen)
            {
                ch.playing = false;
                continue;
            }

            float sampleValue = s.data[pos] / 128.0f;
            sampleValue *= (ch.volume / 64.0f);

            // Классическая амижная панорама - каналы 0/3 налево, 1/2
            // направо (см. ASSEMBLY.md, "SoundCard").
            if (c == 0 || c == 3) leftF += sampleValue;
            else rightF += sampleValue;

            ch.samplePos += ch.sampleStep;
        }

        float masterVolume = volume / 255.0f;
        leftF *= masterVolume * 0.7f;    // 0.7 - запас, чтобы сумма каналов не клиппировала
        rightF *= masterVolume * 0.7f;

        int L = static_cast<int>(leftF * 32767.0f);
        int R = static_cast<int>(rightF * 32767.0f);
        L = std::clamp(L, -32768, 32767);
        R = std::clamp(R, -32768, 32767);

        out[i * 2] = static_cast<int16_t>(L);
        out[i * 2 + 1] = static_cast<int16_t>(R);

        samplesRemainingInTick--;
    }
}

void SoundCard::audioThreadMain()
{
    const int NUM_BUFFERS = 4;
    const int FRAMES_PER_BUFFER = 2048;

    WAVEFORMATEX wfx = {};
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = 2;
    wfx.nSamplesPerSec = SAMPLE_RATE;
    wfx.wBitsPerSample = 16;
    wfx.nBlockAlign = static_cast<WORD>(wfx.nChannels * wfx.wBitsPerSample / 8);
    wfx.nAvgBytesPerSec = wfx.nSamplesPerSec * wfx.nBlockAlign;

    HWAVEOUT hWaveOut = nullptr;
    MMRESULT openResult = waveOutOpen(&hWaveOut, WAVE_MAPPER, &wfx, 0, 0, CALLBACK_NULL);

    if (openResult != MMSYSERR_NOERROR)
    {
        // Нет звукового устройства на хосте (или headless-среда без
        // звука) - тихо выходим, без исключений (см. ASSEMBLY.md,
        // "SoundCard" про это поведение).
        playing = false;
        return;
    }

    std::vector<int16_t> bufferData[NUM_BUFFERS];
    WAVEHDR headers[NUM_BUFFERS] = {};

    for (int i = 0; i < NUM_BUFFERS; i++)
    {
        bufferData[i].assign(FRAMES_PER_BUFFER * 2, 0);
        headers[i].lpData = reinterpret_cast<LPSTR>(bufferData[i].data());
        headers[i].dwBufferLength = static_cast<DWORD>(bufferData[i].size() * sizeof(int16_t));
        waveOutPrepareHeader(hWaveOut, &headers[i], sizeof(WAVEHDR));
    }

    {
        std::lock_guard<std::mutex> lock(songMutex);
        resetSequencer();

        for (int i = 0; i < NUM_BUFFERS; i++)
        {
            renderSamples(bufferData[i].data(), FRAMES_PER_BUFFER);
            waveOutWrite(hWaveOut, &headers[i], sizeof(WAVEHDR));
        }
    }

    int nextBuffer = 0;

    while (!stopRequested)
    {
        if (headers[nextBuffer].dwFlags & WHDR_DONE)
        {
            if (!paused)
            {
                std::lock_guard<std::mutex> lock(songMutex);
                renderSamples(bufferData[nextBuffer].data(), FRAMES_PER_BUFFER);
            }
            else
            {
                std::fill(bufferData[nextBuffer].begin(), bufferData[nextBuffer].end(), 0);
            }

            waveOutWrite(hWaveOut, &headers[nextBuffer], sizeof(WAVEHDR));
            nextBuffer = (nextBuffer + 1) % NUM_BUFFERS;
        }
        else
        {
            Sleep(5);
        }
    }

    waveOutReset(hWaveOut);

    for (int i = 0; i < NUM_BUFFERS; i++)
    {
        waveOutUnprepareHeader(hWaveOut, &headers[i], sizeof(WAVEHDR));
    }

    waveOutClose(hWaveOut);

    playing = false;
}
