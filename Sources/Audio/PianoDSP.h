#ifndef PR_PIANO_DSP_H
#define PR_PIANO_DSP_H
#ifdef __cplusplus
extern "C" {
#endif
/* Owns one normalized SFZ instrument. create/load/reset/destroy require the audio
 * engine to be stopped. One thread produces MIDI, one audio thread renders.
 * render never allocates, takes a lock, loads a sample, or clips its output.
 * maxFrames is a host capacity hint; rendering does not need temporary buffers.
 * load failures leave a silent sampler and a diagnostic from pr_piano_error. */
typedef struct PRPianoDSP PRPianoDSP;
PRPianoDSP *pr_piano_create(double sampleRate, unsigned maxFrames);
int pr_piano_load(PRPianoDSP *, const char *sfzPath);
const char *pr_piano_error(PRPianoDSP *);
void pr_piano_destroy(PRPianoDSP *);
void pr_piano_reset(PRPianoDSP *);
int pr_piano_midi(PRPianoDSP *, unsigned char status, unsigned char d1, unsigned char d2);
void pr_piano_render(PRPianoDSP *, float *left, float *right, unsigned frames);
#ifdef __cplusplus
}
#endif
#endif
