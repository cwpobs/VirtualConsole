// DISKIO.MC - обёртки над Disk-регистрами, параметризованные diskId
// (0=C, 1=D) - тот же приём, что d_cmd/d_status/d_data/d_set_data в
// C/TOOLS/FM.MC, вынесенный в общую библиотеку (см. ASSEMBLY.md,
// "Мини-C", "#include"), чтобы новым программам (например, C/TOOLS/
// VIEW.MC) не пришлось копировать их заново. FM.MC не переведён на эту
// библиотеку - у него уже есть свои идентичные функции, менять
// работающий код без необходимости незачем.

const DISKIO_C_CMD = 0xF00007F2;
const DISKIO_C_STATUS = 0xF00007F3;
const DISKIO_C_DATA = 0xF00007F4;

const DISKIO_D_CMD = 0xF0000805;
const DISKIO_D_STATUS = 0xF0000806;
const DISKIO_D_DATA = 0xF0000807;

int diskioCName[12] = 0xF00007E6;
int diskioDName[12] = 0xF00007F9;

// Команды Disk, общие для обоих дисков (см. ASSEMBLY.md, "Disk").
const DISKIO_OPEN_READ = 3;
const DISKIO_READ_BYTE = 4;
const DISKIO_OPEN_WRITE = 5;
const DISKIO_WRITE_BYTE = 6;
const DISKIO_CLOSE = 7;
const DISKIO_CHDIR = 11;
const DISKIO_CHDIR_UP = 12;

int diskio_cmd(int diskId, int cmd) {
    if (diskId == 0) { poke(DISKIO_C_CMD, cmd); return 0; }
    poke(DISKIO_D_CMD, cmd);
    return 0;
}

int diskio_status(int diskId) {
    if (diskId == 0) { return peek(DISKIO_C_STATUS); }
    return peek(DISKIO_D_STATUS);
}

int diskio_data(int diskId) {
    if (diskId == 0) { return peek(DISKIO_C_DATA); }
    return peek(DISKIO_D_DATA);
}

int diskio_set_data(int diskId, int value) {
    if (diskId == 0) { poke(DISKIO_C_DATA, value); return 0; }
    poke(DISKIO_D_DATA, value);
    return 0;
}

int diskio_name_char(int diskId, int idx) {
    if (diskId == 0) { return diskioCName[idx]; }
    return diskioDName[idx];
}

int diskio_set_name_char(int diskId, int idx, int value) {
    if (diskId == 0) { diskioCName[idx] = value; return 0; }
    diskioDName[idx] = value;
    return 0;
}

// CHDIR/CHDIR_UP (см. ASSEMBLY.md, "Disk") - заходят/поднимаются в
// currentDir диска diskId. CHDIR читает целевую папку из NAME (заполнить
// через diskio_set_name_char ДО вызова) - тот же приём, что и у файловых
// команд выше. CHDIR_UP в корне - безопасный no-op (как в DOS), поэтому
// его можно звать заведомо больше раз, чем реальная глубина вложенности,
// чтобы гарантированно оказаться в корне (см. load_playlist()/
// load_mod_from_playlist() в PLAYER.MC).
int diskio_chdir(int diskId) {
    diskio_cmd(diskId, DISKIO_CHDIR);
    return 0;
}

int diskio_chdir_up(int diskId) {
    diskio_cmd(diskId, DISKIO_CHDIR_UP);
    return 0;
}
