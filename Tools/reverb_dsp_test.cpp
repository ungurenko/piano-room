#include "../Sources/Audio/ReverbDSP.h"
#include <vector>
#include <cmath>
#include <cassert>
#include <cstdio>
#include <chrono>
#include <algorithm>
int main() {
    for(double rate:{44100.,48000.,96000.}) for(unsigned block:{64u,128u,256u,512u})  {
        auto* d=pr_reverb_create(rate,block);
        assert(d);
        PRReverbParameters p= {
            1,1,2.2f,1.f/3,18,.5f,1,.2f,1.2f
        };
        pr_reverb_set_parameters(d,p);
        pr_reverb_reset(d);
        std::vector<float> l(block),r(block),a(block),b(block);
        double energy=0,difference=0,late=0;
        for(unsigned k=0;k<unsigned(rate*5/block);++k) {
            std::fill(l.begin(),l.end(),0);
            std::fill(r.begin(),r.end(),0);
            if(!k)l[0]=r[0]=1;
            pr_reverb_process(d,l.data(),r.data(),a.data(),b.data(),block);
            for(unsigned i=0;i<block;++i) {
                assert(std::isfinite(a[i])&&std::isfinite(b[i]));
                energy+=a[i]*a[i]+b[i]*b[i];
                difference+=std::abs(a[i]-b[i]);
                if(k*block>rate*4)late+=a[i]*a[i]+b[i]*b[i];
            }
        }  assert(energy>1e-6&&difference>1e-5&&late<energy*.05);
        pr_reverb_reset(d);
        std::fill(l.begin(),l.end(),0);
        std::fill(r.begin(),r.end(),0);
        pr_reverb_process(d,l.data(),r.data(),a.data(),b.data(),block);
        for(float v:a)assert(v==0);
        p.enabled=0;
        pr_reverb_set_parameters(d,p);
        pr_reverb_reset(d);
        std::fill(l.begin(),l.end(),.25f);
        pr_reverb_process(d,l.data(),r.data(),a.data(),b.data(),block);
        for(float v:a)assert(v==.25f);
        pr_reverb_destroy(d);
    }
    auto*d=pr_reverb_create(48000,128);
    assert(d);
    PRReverbParameters p= {
        .35f,1,12,1,40,.4f,1,.85f,.55f
    };
    pr_reverb_set_parameters(d,p);
    pr_reverb_reset(d);
    std::vector<float>l(128),r(128),a(128),b(128);
    std::vector<double>timings;
    timings.reserve(10000);
    for(int k=0;k<10000;++k) {
        for(int i=0;i<128;++i)l[i]=r[i]=.15f*std::sin((k*128+i)*.037);
        if(k%17==0) {
            p.size=float(k%101)/100;
            p.preDelayMs=k%101;
            pr_reverb_set_parameters(d,p);
        }  auto t=std::chrono::steady_clock::now();
        pr_reverb_process(d,l.data(),r.data(),a.data(),b.data(),128);
        timings.push_back(std::chrono::duration<double,std::micro>(std::chrono::steady_clock::now()-t).count());
        for(float v:a)assert(std::isfinite(v)&&std::abs(v)<4);
    }  std::sort(timings.begin(),timings.end());
    printf("DSP Release: p99 %.1f us, maximum %.1f us; block deadline 2666.7 us\n",timings[9900],timings.back());
    assert(timings[9900]<2000);
    pr_reverb_destroy(d);
    assert(!pr_reverb_create(0,128));
    puts("Реверб DSP: частоты, блоки, затухание, стерео, reset и bypass — OK");
}
