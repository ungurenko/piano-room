#include "PianoDSP.h"
#include "../../ThirdParty/SFZPlayer/SampleBuffer.h"
#include "../../ThirdParty/SFZPlayer/WAVReader.h"
#define DR_FLAC_IMPLEMENTATION
#define DR_FLAC_NO_OGG
#include "../../ThirdParty/dr_flac/dr_flac.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <regex>
#include <stdexcept>
#include <vector>

namespace {
constexpr unsigned Voices = 512, Queue = 4096;
static_assert(std::atomic<unsigned>::is_always_lock_free && std::atomic<bool>::is_always_lock_free,
              "Audio queue requires lock-free atomics");
struct Sample {
    std::vector<float> pcm;
    unsigned channels = 0;
    double rate = 0;
    size_t frames = 0;
};
struct Region {
    unsigned sample = ~0u;
    int lo = 0, hi = 127, vl = 0, vh = 127, key = 60, group = 0, poly = 0;
    std::array<int, 128> ccLo{}, ccHi;
    float gain = 1, pan = 0, veltrack = 100, attack = 0, release = 0, shape = -6, releaseMod = 0,
          offTime = .006f;
    int releaseCC = 64, releaseCurve = -1, sustainCC = 64;
    bool dynamic = false, oneShot = false, releaseTrigger = false, flatVelocity = false;
    Region() { ccHi.fill(127); }
};
struct Voice {
    const Region *r = nullptr;
    double pos = 0, step = 1;
    float gainL = 0, gainR = 0, env = 0, releaseStart = 0;
    double elapsed = 0, releaseDuration = 0;
    int note = 0, channel = 0;
    bool down = false, held = false, releasing = false;
    uint64_t serial = 0;
};
struct Event {
    unsigned char s, a, b;
};
float value(const std::string &s) {
    size_t used = 0;
    float f = std::stof(s, &used);
    if (used != s.size() || !std::isfinite(f))
        throw std::runtime_error("Invalid number: " + s);
    return f;
}
int integer(const std::string &s, int low, int high) {
    float f = value(s);
    if (f < low || f > high || f != std::floor(f))
        throw std::runtime_error("Invalid integer: " + s);
    return int(f);
}
} // namespace
struct PRPianoDSP {
    double rate;
    unsigned maxFrames;
    std::string error;
    std::vector<Sample> samples;
    std::vector<Region> regions;
    std::array<std::array<float, 128>, 128> curves{};
    std::array<bool, 128> hasCurve{};
    std::array<unsigned char, 128> defaults{}, cc{};
    std::array<unsigned char, 128> noteVelocity{};
    std::array<Voice, Voices> voices{};
    std::array<Event, Queue> events{};
    std::atomic<unsigned> read{0}, write{0};
    std::atomic<bool> panic{false};
    uint64_t serial = 0;
    float bend = 0;
    PRPianoDSP(double r, unsigned m) : rate(r), maxFrames(m) {
        defaults[7] = defaults[11] = 127;
        cc = defaults;
    }
    float curve(int number, int controller) const {
        const float x = cc[controller] / 127.f;
        if (number < 0)
            return x;
        if (hasCurve[number])
            return curves[number][cc[controller]];
        if (number == 4)
            return x * x;
        return x; // Undefined custom curves are rejected before the sampler becomes playable.
    }
    float releaseTime(const Region &r) const {
        return std::clamp(r.release + r.releaseMod * curve(r.releaseCurve, r.releaseCC), .001f,
                          120.f);
    }
    bool matches(const Region &r, int note, int vel) const {
        if (note < r.lo || note > r.hi || vel < r.vl || vel > r.vh)
            return false;
        for (int i = 0; i < 128; ++i)
            if (cc[i] < r.ccLo[i] || cc[i] > r.ccHi[i])
                return false;
        return true;
    }
    void release(Voice &v, double duration = -1) {
        v.down = false;
        v.held = false;
        v.releasing = true;
        v.releaseStart = v.env;
        v.elapsed = 0;
        v.releaseDuration = duration < 0 ? releaseTime(*v.r) : duration;
    }
    void start(const Region &r, int note, int vel, int channel) {
        if (r.poly == 1)
            for (auto &v : voices)
                if (v.r && v.note == note && v.channel == channel && v.r->group == r.group &&
                    !v.releasing)
                    release(v, r.offTime);
        Voice *target = nullptr;
        for (auto &v : voices)
            if (!v.r) {
                target = &v;
                break;
            }
        if (!target)
            target = &*std::min_element(
                voices.begin(), voices.end(),
                [](const Voice &a, const Voice &b) { return a.serial < b.serial; });
        *target = Voice{};
        auto &v = *target;
        v.r = &r;
        v.note = note;
        v.channel = channel;
        v.down = true;
        v.serial = ++serial;
        v.step = samples[r.sample].rate / rate * std::pow(2., (note - r.key + bend) / 12.);
        float velocity = vel / 127.f;
        if (r.flatVelocity)
            velocity = vel <= 63 ? velocity * 127.f / 63.f : 1.f;
        const float gain = r.gain * std::pow(std::max(.00001f, velocity),
                                             (r.flatVelocity ? 1.f : 2.f) * r.veltrack / 100.f);
        // SFZ pan is a balance control: centered stereo keeps both microphones unchanged.
        v.gainL = gain * std::sqrt(1.f - std::max(0.f, r.pan));
        v.gainR = gain * std::sqrt(1.f + std::min(0.f, r.pan));
        v.env = r.attack > 0 ? 0 : 1;
    }
    void midi(Event e) {
        const int kind = e.s & 0xf0, ch = e.s & 15;
        if (kind == 0xb0) {
            if (e.a == 120 || e.a == 123) {
                for (auto &v : voices)
                    if (v.r && v.channel == ch) {
                        if (e.a == 120)
                            v.r = nullptr;
                        else
                            release(v);
                    }
                return;
            }
            if (cc[e.a] == e.b)
                return; // Repeated controller values must not restart an active release tail.
            cc[e.a] = e.b;
            for (auto &v : voices)
                if (v.r) {
                    if (v.held && v.r->sustainCC == e.a && e.b < 64)
                        release(v);
                    else if (v.releasing && v.r->dynamic && v.r->releaseCC == e.a)
                        release(v);
                }
        } else if (kind == 0x90 && e.b) {
            for (const auto &r : regions)
                if (!r.releaseTrigger && matches(r, e.a, e.b))
                    start(r, e.a, e.b, ch);
            noteVelocity[e.a] = e.b;
        } else if (kind == 0x80 || (kind == 0x90 && !e.b)) {
            int velocity = noteVelocity[e.a];
            bool had = false;
            for (auto &v : voices)
                if (v.r && v.note == e.a && v.channel == ch && v.down) {
                    had = true;
                    v.down = false;
                    if (v.r->oneShot)
                        continue;
                    if (cc[v.r->sustainCC] >= 64)
                        v.held = true;
                    else
                        release(v);
                }
            if (had)
                for (const auto &r : regions)
                    if (r.releaseTrigger && matches(r, e.a, velocity))
                        start(r, e.a, velocity, ch);
        } else if (kind == 0xe0) {
            float old = bend;
            bend = ((int(e.a) | (int(e.b) << 7)) - 8192) / 8192.f * 2;
            for (auto &v : voices)
                if (v.r)
                    v.step *= std::pow(2., (bend - old) / 12.);
        }
    }
};
static Sample loadSample(const std::filesystem::path &path) {
    Sample s;
    if (path.extension() == ".flac" || path.extension() == ".FLAC") {
        std::unique_ptr<drflac, void (*)(drflac *)> f(drflac_open_file(path.c_str(), nullptr),
                                                      [](drflac *p) { drflac_close(p); });
        if (!f || f->channels < 1 || f->channels > 2 || !f->totalPCMFrameCount ||
            f->totalPCMFrameCount > 100000000)
            throw std::runtime_error("Invalid FLAC: " + path.string());
        s.channels = f->channels;
        s.rate = f->sampleRate;
        s.frames = f->totalPCMFrameCount;
        s.pcm.resize((s.frames + 4) * s.channels);
        // Decode directly to float; IEEE float preserves every 24-bit PCM value.
        if (drflac_read_pcm_frames_f32(f.get(), s.frames, s.pcm.data()) != s.frames)
            throw std::runtime_error("Truncated FLAC: " + path.string());
    } else {
        WAVReader reader(path.string());
        if (!reader.valid() || reader.num_channels < 1 || reader.num_channels > 2 ||
            reader.num_samples <= 0 || reader.num_samples > 100000000)
            throw std::runtime_error("Invalid WAV: " + path.string());
        SampleBuffer b(reader.num_channels, reader.num_samples, reader.bits_per_sample,
                       SampleBuffer::Little, SampleBuffer::Interleaved);
        if (!reader.read_samples_into(0, reader.num_samples, &b))
            throw std::runtime_error("Truncated WAV: " + path.string());
        s.channels = reader.num_channels;
        s.rate = reader.sample_rate;
        s.frames = reader.num_samples;
        s.pcm.resize((s.frames + 4) * s.channels);
        for (size_t i = 0; i < s.frames; ++i)
            for (unsigned c = 0; c < s.channels; ++c)
                s.pcm[i * s.channels + c] = b.read_sample(b.channel_start(c) + i * b.stride);
    }
    if (s.rate < 8000 || s.rate > 384000)
        throw std::runtime_error("Invalid sample rate");
    return s;
}
extern "C" PRPianoDSP *pr_piano_create(double rate, unsigned frames) {
    if (!std::isfinite(rate) || rate < 8000 || rate > 384000 || !frames)
        return nullptr;
    try {
        return new PRPianoDSP(rate, frames);
    } catch (...) {
        return nullptr;
    }
}
extern "C" const char *pr_piano_error(PRPianoDSP *p) {
    return p ? p->error.c_str() : "Invalid sampler";
}
extern "C" void pr_piano_destroy(PRPianoDSP *p) { delete p; }
extern "C" void pr_piano_reset(PRPianoDSP *p) {
    if (!p)
        return;
    for (auto &v : p->voices)
        v.r = nullptr;
    p->cc = p->defaults;
    p->noteVelocity.fill(0);
    p->bend = 0;
    p->read.store(0);
    p->write.store(0);
    p->panic.store(false);
}
extern "C" int pr_piano_load(PRPianoDSP *p, const char *path) {
    if (!p || !path)
        return 0;
    pr_piano_reset(p);
    p->regions.clear();
    p->samples.clear();
    p->hasCurve.fill(false);
    p->error.clear();
    p->defaults.fill(0);
    p->defaults[7] = p->defaults[11] = 127;
    try {
        std::ifstream file(path);
        if (!file)
            throw std::runtime_error("SFZ file not found");
        std::string text((std::istreambuf_iterator<char>(file)), {});
        text = std::regex_replace(text, std::regex("//[^\\r\\n]*"), "");
        // Values end at the next opcode or section, preserving spaces in sample names.
        std::regex token("<([^>]+)>|([A-Za-z_][A-Za-z_0-9]*)\\s*=\\s*([^<]*?)(?=\\s+[A-Za-z_][A-Za-"
                         "z_0-9]*\\s*=|\\s*<|$)");
        std::string section;
        Region region;
        bool have = false;
        int curveIndex = -1;
        std::map<int, float> points;
        std::map<std::string, unsigned> loaded;
        auto flushCurve = [&] {
            if (curveIndex < 0) {
                if (!points.empty())
                    throw std::runtime_error("Curve missing index");
                return;
            }
            if (points.empty())
                throw std::runtime_error("Empty curve");
            auto &curve = p->curves[curveIndex];
            for (int i = 0; i < 128; ++i) {
                auto hi = points.lower_bound(i);
                if (hi == points.begin())
                    curve[i] = hi->second;
                else if (hi == points.end())
                    curve[i] = std::prev(hi)->second;
                else {
                    auto lo = std::prev(hi);
                    curve[i] = lo->second + (hi->second - lo->second) * (i - lo->first) /
                                                float(hi->first - lo->first);
                }
            }
            p->hasCurve[curveIndex] = true;
            points.clear();
            curveIndex = -1;
        };
        auto flushRegion = [&] {
            if (!have)
                return;
            if (region.lo > region.hi || region.vl > region.vh)
                throw std::runtime_error("Reversed region bounds");
            p->regions.push_back(region);
            have = false;
        };
        size_t consumed = 0;
        for (std::sregex_iterator it(text.begin(), text.end(), token), end; it != end; ++it) {
            const auto &m = *it;
            std::string gap = text.substr(consumed, m.position() - consumed);
            if (gap.find_first_not_of(" \t\r\n") != std::string::npos)
                throw std::runtime_error("Unsupported SFZ syntax: " + gap.substr(0, 80));
            consumed = m.position() + m.length();
            if (m[1].matched) {
                flushRegion();
                flushCurve();
                section = m[1];
                if (section == "region") {
                    region = Region{};
                    have = true;
                } else if (section != "control" && section != "curve")
                    throw std::runtime_error("Unsupported section: " + section);
                continue;
            }
            const std::string key = m[2];
            std::string val = m[3];
            val.erase(val.find_last_not_of(" \t\r\n") + 1);
            if (section == "control") {
                if (key.rfind("set_cc", 0) != 0)
                    throw std::runtime_error("Unsupported control: " + key);
                p->defaults[integer(key.substr(6), 0, 127)] = integer(val, 0, 127);
                continue;
            }
            if (section == "curve") {
                if (key == "curve_index")
                    curveIndex = integer(val, 0, 127);
                else if (key[0] == 'v')
                    points[integer(key.substr(1), 0, 127)] = value(val);
                else
                    throw std::runtime_error("Unsupported curve: " + key);
                continue;
            }
            if (!have)
                throw std::runtime_error("Opcode outside region: " + key);
            if (key == "sample") {
                auto full = std::filesystem::path(path).parent_path() / val;
                auto name = full.lexically_normal().string();
                auto found = loaded.find(name);
                if (found == loaded.end()) {
                    region.sample = unsigned(p->samples.size());
                    p->samples.push_back(loadSample(full));
                    loaded[name] = region.sample;
                } else
                    region.sample = found->second;
            } else if (key == "lokey")
                region.lo = integer(val, 0, 127);
            else if (key == "hikey")
                region.hi = integer(val, 0, 127);
            else if (key == "pitch_keycenter")
                region.key = integer(val, 0, 127);
            else if (key == "lovel")
                region.vl = integer(val, 0, 127);
            else if (key == "hivel")
                region.vh = integer(val, 0, 127);
            else if (key.rfind("locc", 0) == 0)
                region.ccLo[integer(key.substr(4), 0, 127)] = integer(val, 0, 127);
            else if (key.rfind("hicc", 0) == 0)
                region.ccHi[integer(key.substr(4), 0, 127)] = integer(val, 0, 127);
            else if (key == "group")
                region.group = integer(val, 0, 100000);
            else if (key == "note_polyphony")
                region.poly = integer(val, 1, 1);
            else if (key == "off_time")
                region.offTime = std::clamp(value(val), .001f, 120.f);
            else if (key == "volume")
                region.gain = std::pow(10.f, std::clamp(value(val), -144.f, 24.f) / 20);
            else if (key == "pan")
                region.pan = std::clamp(value(val) / 100.f, -1.f, 1.f);
            else if (key == "amp_veltrack")
                region.veltrack = std::clamp(value(val), 0.f, 100.f);
            else if (key == "ampeg_attack")
                region.attack = std::clamp(value(val), 0.f, 120.f);
            else if (key == "ampeg_release")
                region.release = std::clamp(value(val), 0.f, 120.f);
            else if (key == "ampeg_release_shape")
                region.shape = std::clamp(value(val), -12.f, 12.f);
            else if (key == "ampeg_dynamic")
                region.dynamic = integer(val, 0, 1);
            else if (key == "sustain_cc")
                region.sustainCC = integer(val, 0, 127);
            else if (key == "amp_velcurve_63") {
                if (value(val) != 1)
                    throw std::runtime_error("Unsupported velocity curve");
                region.flatVelocity = true;
            } else if (key.rfind("ampeg_release_curvecc", 0) == 0) {
                region.releaseCC = integer(key.substr(21), 0, 127);
                region.releaseCurve = integer(val, 0, 127);
            } else if (key.rfind("ampeg_release_oncc", 0) == 0) {
                region.releaseCC = integer(key.substr(18), 0, 127);
                region.releaseMod = value(val);
            } else if (key.rfind("ampeg_releasecc", 0) == 0) {
                region.releaseCC = integer(key.substr(15), 0, 127);
                region.releaseMod = value(val);
            } else if (key == "loop_mode") {
                if (val == "one_shot")
                    region.oneShot = true;
                else if (val != "no_loop")
                    throw std::runtime_error("Unsupported loop mode: " + val);
            } else if (key == "trigger") {
                if (val == "release")
                    region.releaseTrigger = true;
                else if (val != "attack")
                    throw std::runtime_error("Unsupported trigger: " + val);
            } else
                throw std::runtime_error("Unsupported audio opcode: " + key);
        }
        if (text.substr(consumed).find_first_not_of(" \r\n\t") != std::string::npos)
            throw std::runtime_error("Unparsed SFZ content");
        flushRegion();
        flushCurve();
        if (p->regions.empty() || p->samples.empty())
            throw std::runtime_error("No playable samples");
        for (const auto &r : p->regions) {
            if (r.sample >= p->samples.size())
                throw std::runtime_error("Region missing sample");
            if (r.releaseCurve >= 0 && !p->hasCurve[r.releaseCurve] && r.releaseCurve != 4)
                throw std::runtime_error("Undefined release curve");
        }
        p->cc = p->defaults;
        return 1;
    } catch (const std::exception &e) {
        p->error = e.what();
        p->regions.clear();
        p->samples.clear();
        return 0;
    }
}
extern "C" int pr_piano_midi(PRPianoDSP *p, unsigned char s, unsigned char a, unsigned char b) {
    if (!p || a > 127 || b > 127)
        return 0;
    unsigned w = p->write.load(std::memory_order_relaxed), next = (w + 1) % Queue;
    if (next == p->read.load(std::memory_order_acquire)) {
        p->panic.store(true, std::memory_order_release);
        return 0;
    }
    p->events[w] = {s, a, b};
    p->write.store(next, std::memory_order_release);
    return 1;
}
extern "C" void pr_piano_render(PRPianoDSP *p, float *l, float *r, unsigned frames) {
    if (!l || !r)
        return;
    std::fill_n(l, frames, 0);
    std::fill_n(r, frames, 0);
    if (!p)
        return;
    if (p->panic.exchange(false, std::memory_order_acq_rel)) {
        for (auto &v : p->voices)
            v.r = nullptr;
        p->read.store(p->write.load(std::memory_order_acquire), std::memory_order_release);
        return;
    }
    unsigned rd = p->read.load(std::memory_order_relaxed),
             wr = p->write.load(std::memory_order_acquire);
    while (rd != wr) {
        p->midi(p->events[rd]);
        rd = (rd + 1) % Queue;
    }
    p->read.store(rd, std::memory_order_release);
    for (auto &v : p->voices)
        if (v.r) {
            const auto &reg = *v.r;
            const auto &s = p->samples[reg.sample];
            for (unsigned f = 0; f < frames; ++f) {
                size_t index = size_t(v.pos);
                if (index >= s.frames) {
                    v.r = nullptr;
                    break;
                }
                if (v.releasing) {
                    v.elapsed += 1 / p->rate;
                    double t = v.elapsed / v.releaseDuration;
                    if (t >= 1) {
                        v.r = nullptr;
                        break;
                    }
                    float k = reg.shape;
                    v.env = v.releaseStart *
                            (std::abs(k) < .0001
                                 ? float(1 - t)
                                 : float((std::exp(k * t) - std::exp(k)) / (1 - std::exp(k))));
                } else if (v.env < 1) {
                    v.env = std::min(1.f, v.env + float(1 / (reg.attack * p->rate)));
                }
                float frac = float(v.pos - index);
                auto interpolate = [&](unsigned channel) {
                    auto at = [&](int64_t frame) {
                        return s
                            .pcm[size_t(std::clamp<int64_t>(frame, 0, s.frames - 1)) * s.channels +
                                 channel];
                    };
                    const float a = at(int64_t(index) - 1), b = at(index), c = at(index + 1),
                                d = at(index + 2);
                    return b +
                           .5f * frac *
                               (c - a +
                                frac * (2 * a - 5 * b + 4 * c - d + frac * (3 * (b - c) + d - a)));
                };
                float left = interpolate(0), right = s.channels == 2 ? interpolate(1) : left;
                l[f] += left * v.env * v.gainL;
                r[f] += right * v.env * v.gainR;
                v.pos += v.step;
            }
        }
}
