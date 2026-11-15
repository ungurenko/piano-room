#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PRReverbDSP PRReverbDSP;

typedef struct {
    float mix;
    int enabled;
    float decaySeconds;
    float size;
    float preDelayMs;
    float tone;
    float width;
    float modulation;
    float early;
} PRReverbParameters;

PRReverbDSP* pr_reverb_create(double sampleRate, unsigned maxFrames);
void pr_reverb_destroy(PRReverbDSP* dsp);
void pr_reverb_set_parameters(PRReverbDSP* dsp, PRReverbParameters parameters);
void pr_reverb_reset(PRReverbDSP* dsp);
void pr_reverb_process(PRReverbDSP* dsp, const float* left, const float* right,
                       float* outputLeft, float* outputRight, unsigned frames);

#ifdef __cplusplus
}
#endif
