#include "VmConfig.h"

#include <fstream>
#include <sstream>

namespace
{
    std::string trim(const std::string& s)
    {
        size_t start = s.find_first_not_of(" \t\r\n");
        if (start == std::string::npos)
        {
            return "";
        }

        size_t end = s.find_last_not_of(" \t\r\n");
        return s.substr(start, end - start + 1);
    }
}

VmConfig VmConfig::load(const std::string& path)
{
    VmConfig config;

    std::ifstream file(path);
    if (!file)
    {
        return config; // файла нет - значения по умолчанию (видеоконсоль)
    }

    std::string line;
    while (std::getline(file, line))
    {
        std::string trimmed = trim(line);

        if (trimmed.empty() || trimmed[0] == '#')
        {
            continue;
        }

        size_t eq = trimmed.find('=');
        if (eq == std::string::npos)
        {
            continue;
        }

        std::string key = trim(trimmed.substr(0, eq));
        std::string value = trim(trimmed.substr(eq + 1));

        if (key == "console")
        {
            config.useVideoConsole = (value != "text");
        }
        else if (key == "video_scale")
        {
            try
            {
                int scale = std::stoi(value);
                if (scale >= 1)
                {
                    config.videoConsoleScale = scale;
                }
            }
            catch (const std::exception&)
            {
                // невалидное значение - оставляем значение по умолчанию
            }
        }
    }

    return config;
}
