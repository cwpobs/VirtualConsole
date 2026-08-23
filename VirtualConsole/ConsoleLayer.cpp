#include "ConsoleLayer.h"

ConsoleLayer::ConsoleLayer()
    : visible(true)
{
}

uint8_t ConsoleLayer::read(uint32_t address)
{
    return isVisible() ? 1 : 0;
}

void ConsoleLayer::write(uint32_t address, uint8_t value)
{
    setVisible(value != 0);
}

void ConsoleLayer::setVisible(bool value)
{
    visible = value;
}

bool ConsoleLayer::isVisible() const
{
    return visible;
}
