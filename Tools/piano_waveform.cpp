// Emits deterministic float samples for before/after waveform comparisons.
#include "../Sources/Audio/PianoDSP.h"
#include <cstdio>
#include <initializer_list>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    auto *piano = pr_piano_create(48000, 512);
    if (!piano) return 1;
    if (!pr_piano_load(piano, argv[1])) {
        std::fprintf(stderr, "%s\n", pr_piano_error(piano));
        pr_piano_destroy(piano);
        return 1;
    }
    float left[256], right[256];
    for (int pedal : {0, 64, 127}) for (int velocity : {30, 90}) {
        pr_piano_reset(piano);
        pr_piano_midi(piano, 0xb0, 64, pedal);
        for (int note = 48; note < 73; note += 4)
            pr_piano_midi(piano, 0x90, note, velocity);
        for (int block = 0; block < 200; ++block) {
            if (block == 40) for (int note = 48; note < 73; note += 4)
                pr_piano_midi(piano, 0x80, note, 0);
            if (block == 100) pr_piano_midi(piano, 0xb0, 64, 0);
            pr_piano_render(piano, left, right, 256);
            if (std::fwrite(left, sizeof(float), 256, stdout) != 256 ||
                std::fwrite(right, sizeof(float), 256, stdout) != 256) {
                pr_piano_destroy(piano);
                return 1;
            }
        }
    }
    pr_piano_destroy(piano);
}
