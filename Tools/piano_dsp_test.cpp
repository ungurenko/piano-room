#include "../Sources/Audio/PianoDSP.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <new>
#include <vector>
static std::atomic<bool> realtime{false};
static std::atomic<unsigned> allocations{0};
void *operator new(std::size_t n) {
    if (realtime.load())
        ++allocations;
    if (void *p = std::malloc(n))
        return p;
    throw std::bad_alloc();
}
void operator delete(void *p) noexcept { std::free(p); }
void *operator new[](std::size_t n) { return ::operator new(n); }
void operator delete[](void *p) noexcept { ::operator delete(p); }
static void check(bool ok, const char *what) {
    if (!ok) {
        std::cerr << "FAIL: " << what << "\n";
        std::exit(1);
    }
}
static void put16(std::ofstream &f, unsigned n) {
    char b[] = {char(n), char(n >> 8)};
    f.write(b, 2);
}
static void put32(std::ofstream &f, unsigned n) {
    put16(f, n);
    put16(f, n >> 16);
}
static void wav(const std::filesystem::path &p, int value) {
    std::ofstream f(p, std::ios::binary);
    unsigned frames = 44100 * 3;
    f.write("RIFF", 4);
    put32(f, 36 + frames * 4);
    f.write("WAVEfmt ", 8);
    put32(f, 16);
    put16(f, 1);
    put16(f, 2);
    put32(f, 44100);
    put32(f, 44100 * 4);
    put16(f, 4);
    put16(f, 16);
    f.write("data", 4);
    put32(f, frames * 4);
    for (unsigned i = 0; i < frames; ++i) {
        put16(f, value);
        put16(f, value / 2);
    }
}
static double render(PRPianoDSP *p, unsigned frames) {
    std::vector<float> l(frames), r(frames);
    realtime = true;
    pr_piano_render(p, l.data(), r.data(), frames);
    realtime = false;
    double sum = 0;
    for (unsigned i = 0; i < frames; ++i) {
        check(std::isfinite(l[i]) && std::isfinite(r[i]), "finite stereo");
        sum += std::abs(l[i]);
    }
    return sum / frames;
}
static void write(const std::filesystem::path &p, const std::string &s) { std::ofstream(p) << s; }
int main(int argc, char **argv) {
    auto folder = std::filesystem::temp_directory_path() / "piano-room-dsp-tests";
    std::filesystem::create_directories(folder);
    wav(folder / "quiet.wav", 4000);
    wav(folder / "loud.wav", 12000);
    auto sfz = folder / "test.sfz";
    for (double rate : {44100., 48000., 96000.})
        for (unsigned block : {64u, 128u, 256u, 512u}) {
            auto *p = pr_piano_create(rate, 4096);
            check(p, "create");
            write(sfz, "<control> set_cc70=0\n<curve> curve_index=11 v000=0 v064=0.5 "
                       "v127=1\n<region> sample=quiet.wav lokey=60 hikey=60 lovel=1 hivel=63 "
                       "sustain_cc=90 ampeg_release=0.02 ampeg_releasecc64=1 "
                       "ampeg_release_curvecc64=11 ampeg_dynamic=1\n<region> sample=loud.wav "
                       "lokey=60 hikey=60 lovel=64 hivel=127 sustain_cc=90 ampeg_release=0.02 "
                       "ampeg_releasecc64=1 ampeg_release_curvecc64=11 ampeg_dynamic=1\n");
            check(pr_piano_load(p, sfz.c_str()), pr_piano_error(p));
            check(pr_piano_midi(p, 0x90, 60, 30), "queue on");
            double quiet = render(p, block);
            check(quiet > 0, "quiet plays");
            pr_piano_reset(p);
            pr_piano_midi(p, 0x90, 60, 90);
            double loud = render(p, block);
            check(loud > quiet * 5, "velocity layers");
            pr_piano_midi(p, 0xb0, 64, 127);
            pr_piano_midi(p, 0x80, 60, 0);
            for (int n = 0; n < 4; ++n)
                render(p, block);
            check(render(p, block) > 0, "pedal long release");
            pr_piano_midi(p, 0xb0, 64, 0);
            render(p, block);
            render(p, unsigned(rate * .03));
            check(render(p, block) == 0, "dynamic pedal release ends");
            pr_piano_midi(p, 0x90, 60, 100);
            render(p, block);
            pr_piano_midi(p, 0xb0, 120, 0);
            check(render(p, block) == 0, "all sounds off");
            bool overflow = false;
            for (int n = 0; n < 5000; ++n)
                if (!pr_piano_midi(p, 0x90, 60, 100))
                    overflow = true;
            check(overflow, "overflow detected");
            check(render(p, block) == 0, "overflow panic");
            pr_piano_reset(p);
            pr_piano_midi(p, 0x90, 60, 127);
            std::array<float, 512> l{}, r{};
            realtime = true;
            pr_piano_render(p, l.data(), r.data(), block);
            realtime = false;
            check(std::abs(l[block - 1] / r[block - 1] - 2) < .001, "stereo channels preserved");
            write(sfz, "<region> sample=quiet.wav unsupported_audio=5\n");
            check(!pr_piano_load(p, sfz.c_str()), "unknown opcode fails");
            check(*pr_piano_error(p), "error supplied");
            write(sfz, "<region> sample=missing.wav\n");
            check(!pr_piano_load(p, sfz.c_str()), "missing sample fails");
            pr_piano_destroy(p);
        }
    // Standard sustain holds key-up until CC64 is released; explicit alternate sustain leaves CC64
    // for envelope modulation.
    write(sfz, "<control> set_cc70=127\n<region> sample=quiet.wav locc70=64 sustain_cc=64 "
               "ampeg_release=0.01\n<region> sample=loud.wav hicc70=63 sustain_cc=64 "
               "ampeg_release=0.01\n");
    auto *p = pr_piano_create(48000, 4096);
    check(pr_piano_load(p, sfz.c_str()), pr_piano_error(p));
    pr_piano_midi(p, 0x90, 60, 127);
    pr_piano_midi(p, 0xb0, 64, 127);
    pr_piano_midi(p, 0x80, 60, 0);
    check(render(p, 4096) > .1, "controller defaults/hold");
    pr_piano_midi(p, 0xb0, 64, 0);
    render(p, 4096);
    check(render(p, 256) == 0, "sustain release");
    pr_piano_destroy(p);
    write(
        sfz,
        "<control> set_cc67=0 set_cc70=0\n<region> sample=quiet.wav locc64=0 hicc64=63 hicc67=63 "
        "hicc70=63 amp_veltrack=0\n<region> sample=loud.wav locc64=64 locc67=0 hicc67=63 hicc70=63 "
        "amp_veltrack=0\n<region> sample=loud.wav locc67=64 amp_veltrack=0 loop_mode=one_shot\n");
    p = pr_piano_create(48000, 4096);
    check(pr_piano_load(p, sfz.c_str()), pr_piano_error(p));
    pr_piano_midi(p, 0x90, 60, 100);
    double normal = render(p, 256);
    pr_piano_reset(p);
    pr_piano_midi(p, 0xb0, 64, 127);
    pr_piano_midi(p, 0x90, 60, 100);
    check(render(p, 256) > normal * 2.9, "CC64 selects separate pedal recording");
    pr_piano_reset(p);
    pr_piano_midi(p, 0xb0, 67, 127);
    pr_piano_midi(p, 0x90, 60, 100);
    render(p, 256);
    pr_piano_midi(p, 0x80, 60, 0);
    check(render(p, 4096) > normal * 2.9, "CC67 branch and one-shot persists");
    pr_piano_reset(p);
    pr_piano_midi(p, 0xb0, 70, 127);
    pr_piano_midi(p, 0x90, 60, 100);
    check(render(p, 256) == 0, "CC70 excludes ordinary samples");
    pr_piano_destroy(p);
    // Constant +1 in signed 24-bit PCM: truncating to 16 bits would turn this into silence.
    const unsigned char flac24[] = {
        102, 76,  97,  67,  0,   0,   0,   34,  16,  0,   16,  0,  0,   0,  13,  0,   0,
        13,  11,  184, 1,   112, 0,   0,   0,   128, 150, 83,  38, 129, 25, 103, 116, 177,
        139, 30,  29,  14,  142, 246, 220, 208, 132, 0,   0,   40, 32,  0,  0,   0,   114,
        101, 102, 101, 114, 101, 110, 99,  101, 32,  108, 105, 98, 70,  76, 65,  67,  32,
        49,  46,  53,  46,  48,  32,  50,  48,  50,  53,  48,  50, 49,  49, 0,   0,   0,
        0,   255, 248, 106, 12,  0,   127, 246, 0,   0,   0,   1,  104, 78};
    {
        std::ofstream f(folder / "precision.flac", std::ios::binary);
        f.write(reinterpret_cast<const char *>(flac24), sizeof(flac24));
    }
    write(sfz, "<region> sample=precision.flac amp_veltrack=0\n");
    p = pr_piano_create(48000, 4096);
    check(pr_piano_load(p, sfz.c_str()), pr_piano_error(p));
    pr_piano_midi(p, 0x90, 60, 127);
    check(std::abs(render(p, 64) - 1.0 / 8388608) < 1e-12, "FLAC retains all 24 bits");
    pr_piano_destroy(p);
    // Signed full-range WAV values must retain historical normalization exactly.
    for (int value : {-32768, -1, 1, 32767}) {
        wav(folder / "range.wav", value);
        write(sfz, "<region> sample=range.wav amp_veltrack=0\n");
        p = pr_piano_create(44100, 4096);
        check(pr_piano_load(p, sfz.c_str()), pr_piano_error(p));
        pr_piano_midi(p, 0x90, 60, 127);
        float left[64], right[64];
        realtime = true;
        pr_piano_render(p, left, right, 64);
        realtime = false;
        check(left[32] == float(value) / float(INT16_MAX), "signed WAV16 normalization");
        check(right[32] == float(value / 2) / float(INT16_MAX), "WAV16 stereo normalization");
        pr_piano_destroy(p);
    }
    check(allocations.load() == 0, "render performs no allocation");
    std::cout << "PASS generated WAV/SFZ: 3 sample rates x 4 blocks, velocity/CC/dynamic "
                 "release/stereo/reset/overflow/strict load; render allocations=0\n";
    for (int a = 1; a < argc; ++a) {
        auto *real = pr_piano_create(48000, 4096);
        auto begin = std::chrono::steady_clock::now();
        check(pr_piano_load(real, argv[a]), pr_piano_error(real));
        auto loaded = std::chrono::steady_clock::now();
        double worst = 0, peak = 0;
        std::vector<double> timings;
        timings.reserve(2000);
        std::vector<float> l(256), r(256);
        for (int n = 0; n < 16; ++n)
            pr_piano_midi(real, 0x90, 40 + n * 3, n % 2 ? 90 : 30);
        pr_piano_midi(real, 0xb0, 64, 64);
        for (int b = 0; b < 2000; ++b) {
            if (b == 200)
                for (int n = 0; n < 16; ++n)
                    pr_piano_midi(real, 0x80, 40 + n * 3, 0);
            if (b == 400)
                pr_piano_midi(real, 0xb0, 64, 127);
            if (b == 1000)
                pr_piano_midi(real, 0xb0, 64, 0);
            auto t = std::chrono::steady_clock::now();
            realtime = true;
            pr_piano_render(real, l.data(), r.data(), 256);
            realtime = false;
            double took =
                std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - t)
                    .count();
            timings.push_back(took);
            worst = std::max(worst, took);
            for (unsigned i = 0; i < 256; ++i) {
                check(std::isfinite(l[i]) && std::isfinite(r[i]), "real finite");
                peak = std::max(peak, double(std::max(std::abs(l[i]), std::abs(r[i]))));
            }
        }
        check(peak > 0, "real produces sound");
        check(allocations.load() == 0, "real render allocation free");
        std::sort(timings.begin(), timings.end());
        check(timings[1980] < 256.0 / 48000 * 1e6, "p99 render meets the 256-frame deadline");
        std::cout << "REAL " << argv[a]
                  << " load=" << std::chrono::duration<double>(loaded - begin).count()
                  << "s worst256=" << worst << "us p99=" << timings[1980] << "us peak=" << peak
                  << "\n";
        for (int pedal : {0, 64, 127})
            for (int velocity : {30, 90}) {
                pr_piano_reset(real);
                pr_piano_midi(real, 0xb0, 64, pedal);
                pr_piano_midi(real, 0x90, 60, velocity);
                double energy = 0;
                for (int onset = 0; onset < 96; ++onset)
                    energy += render(real, 256);
                check(energy > 0, "real pedal/velocity branch");
            }
        pr_piano_reset(real);
        pr_piano_midi(real, 0xb0, 67, 127);
        pr_piano_midi(real, 0x90, 60, 90);
        double softEnergy = 0;
        for (int onset = 0; onset < 96; ++onset)
            softEnergy += render(real, 256);
        check(softEnergy > 0, "real soft pedal branch");
        pr_piano_destroy(real);
    }
    std::filesystem::remove_all(folder);
}
