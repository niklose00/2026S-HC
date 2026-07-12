// SIMT & Warp-Divergenz Benchmark (HC Uebungsblatt 2, Aufgabe 1)
//
// Rechenintensiver Kernel mit minimalem Speicherbedarf: jeder Thread bearbeitet
// genau ein Element und iteriert darauf eine FMA-Kette x = x*a_p + b_p ueber k
// Iterationen. Die Konstanten (a_p, b_p) haengen vom Pfad-Index p ab; ueber den
// Divergenzgrad d wird gesteuert, wie viele verschiedene Pfade innerhalb eines
// Warps auftreten. Die Gesamtarbeit ist fuer alle d identisch (jeder Thread
// macht exakt k FMAs) -- gemessen wird also reine Divergenz-Serialisierung.
//
// Modi:
//   gpu-intra        p = threadIdx.x % d        -> d Pfade INNERHALB jedes Warps
//   gpu-warpuniform  p = (threadIdx.x / 32) % d -> gleiche Verzweigung, aber
//                                                  warp-einheitlich (Kontrolle)
//   cpu              p = i % d, single-threaded
//   cpu-omp          p = i % d, OpenMP ueber alle Kerne
//
// FLOP-Zaehlung: 1 FMA = 2 FLOPs  =>  GFLOP/s = 2*k*n / t

#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <vector>
#include <algorithm>
#include <chrono>
#include <string>
#ifdef _OPENMP
#include <omp.h>
#endif

#define CUDA_CHECK(call)                                                        \
    do {                                                                        \
        cudaError_t err_ = (call);                                              \
        if (err_ != cudaSuccess) {                                              \
            fprintf(stderr, "CUDA-Fehler %s:%d: %s\n", __FILE__, __LINE__,      \
                    cudaGetErrorString(err_));                                  \
            exit(1);                                                            \
        }                                                                       \
    } while (0)

static const int BLOCK = 256;
static const int MAX_PATHS = 32;

// Pfadspezifische Konstanten: |a| < 1 haelt die Iteration beschraenkt
// (Fixpunkt b/(1-a)), unterschiedliche Werte pro Pfad verhindern, dass der
// Compiler die switch-Cases zusammenlegt, und machen die Pfadwahl im
// Korrektheitscheck sichtbar.
__host__ __device__ inline float path_a(int p) { return 0.50f + 0.01f * (float)p; }
__host__ __device__ inline float path_b(int p) { return 1.00f + 0.10f * (float)p; }

// Eine k-Iterationen-FMA-Kette mit zur Compilezeit fixierten Konstanten:
// pro switch-Case entsteht eine eigene Schleife mit eigenen Immediates.
template <int P>
__device__ __forceinline__ float chain(float x, int k)
{
    const float a = path_a(P);
    const float b = path_b(P);
    for (int i = 0; i < k; ++i)
        x = fmaf(x, a, b);
    return x;
}

#define CASE_CHAIN(P) case P: x = chain<P>(x, k); break;

__global__ void bench_kernel(const float *in, float *out, int n, int k, int d,
                             int warpUniform)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    int p = warpUniform ? (int)((threadIdx.x / 32u) % (unsigned)d)
                        : (int)(threadIdx.x % (unsigned)d);

    float x = in[i];
    switch (p) {
        CASE_CHAIN(0)  CASE_CHAIN(1)  CASE_CHAIN(2)  CASE_CHAIN(3)
        CASE_CHAIN(4)  CASE_CHAIN(5)  CASE_CHAIN(6)  CASE_CHAIN(7)
        CASE_CHAIN(8)  CASE_CHAIN(9)  CASE_CHAIN(10) CASE_CHAIN(11)
        CASE_CHAIN(12) CASE_CHAIN(13) CASE_CHAIN(14) CASE_CHAIN(15)
        CASE_CHAIN(16) CASE_CHAIN(17) CASE_CHAIN(18) CASE_CHAIN(19)
        CASE_CHAIN(20) CASE_CHAIN(21) CASE_CHAIN(22) CASE_CHAIN(23)
        CASE_CHAIN(24) CASE_CHAIN(25) CASE_CHAIN(26) CASE_CHAIN(27)
        CASE_CHAIN(28) CASE_CHAIN(29) CASE_CHAIN(30) CASE_CHAIN(31)
    }
    out[i] = x;
}

// CPU-Referenz derselben Kette (Konstanten zur Laufzeit -- numerisch identisch
// bis auf FMA-Rundung, fuer den Toleranzvergleich ausreichend).
static float chain_ref(float x, int k, int p)
{
    float a = path_a(p), b = path_b(p);
    for (int i = 0; i < k; ++i)
        x = x * a + b;
    return x;
}

// Pfad-Index, den Element i im jeweiligen Modus nimmt (spiegelt die
// Kernel-Logik mit blockDim = BLOCK).
static int path_of(const std::string &mode, long long i, int d)
{
    int t = (int)(i % BLOCK);
    if (mode == "gpu-intra")       return t % d;
    if (mode == "gpu-warpuniform") return (t / 32) % d;
    return (int)(i % d); // cpu, cpu-omp
}

static void cpu_bench(const std::string &mode, const float *in, float *out,
                      int n, int k, int d)
{
    bool omp = (mode == "cpu-omp");
#ifdef _OPENMP
    #pragma omp parallel for schedule(static) if(omp)
#endif
    for (int i = 0; i < n; ++i) {
        int p = (int)(i % d);
        float x = in[i];
        switch (p) {
            // gleiche Struktur wie im Kernel: pro Case eigene Schleife
            #define CASE_REF(P) case P: { const float a = path_a(P), b = path_b(P); \
                for (int j = 0; j < k; ++j) x = x * a + b; } break;
            CASE_REF(0)  CASE_REF(1)  CASE_REF(2)  CASE_REF(3)
            CASE_REF(4)  CASE_REF(5)  CASE_REF(6)  CASE_REF(7)
            CASE_REF(8)  CASE_REF(9)  CASE_REF(10) CASE_REF(11)
            CASE_REF(12) CASE_REF(13) CASE_REF(14) CASE_REF(15)
            CASE_REF(16) CASE_REF(17) CASE_REF(18) CASE_REF(19)
            CASE_REF(20) CASE_REF(21) CASE_REF(22) CASE_REF(23)
            CASE_REF(24) CASE_REF(25) CASE_REF(26) CASE_REF(27)
            CASE_REF(28) CASE_REF(29) CASE_REF(30) CASE_REF(31)
            #undef CASE_REF
        }
        out[i] = x;
    }
    (void)omp;
}

static double median(std::vector<double> v)
{
    std::sort(v.begin(), v.end());
    return v[v.size() / 2];
}

int main(int argc, char **argv)
{
    std::string mode = "gpu-intra";
    long long n = 1LL << 24;
    int k = 4096, d = 1, reps = 10;
    bool check = false, header = false;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() { return std::string(argv[++i]); };
        if      (a == "--mode")   mode  = next();
        else if (a == "--n")      n     = atoll(next().c_str());
        else if (a == "--k")      k     = atoi(next().c_str());
        else if (a == "--d")      d     = atoi(next().c_str());
        else if (a == "--reps")   reps  = atoi(next().c_str());
        else if (a == "--check")  check = true;
        else if (a == "--header") header = true;
        else { fprintf(stderr, "unbekanntes Argument: %s\n", a.c_str()); return 1; }
    }
    if (d < 1 || d > MAX_PATHS) { fprintf(stderr, "d muss in [1,32] liegen\n"); return 1; }
    if (n > (1LL << 31) - 1)    { fprintf(stderr, "n zu gross\n"); return 1; }
    int ni = (int)n;

    std::vector<float> in((size_t)ni), out((size_t)ni, 0.0f);
    for (int i = 0; i < ni; ++i)
        in[(size_t)i] = 0.01f * (float)(i % 97);

    double t_ms = 0.0;
    std::vector<double> times;

    if (mode == "gpu-intra" || mode == "gpu-warpuniform") {
        int warpUniform = (mode == "gpu-warpuniform") ? 1 : 0;
        cudaDeviceProp prop;
        CUDA_CHECK(cudaGetDeviceProperties(&prop, 0));
        fprintf(stderr, "# GPU: %s, %d SMs, %.0f MHz\n",
                prop.name, prop.multiProcessorCount, prop.clockRate / 1000.0);

        float *d_in, *d_out;
        CUDA_CHECK(cudaMalloc(&d_in,  (size_t)ni * sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_out, (size_t)ni * sizeof(float)));
        CUDA_CHECK(cudaMemcpy(d_in, in.data(), (size_t)ni * sizeof(float),
                              cudaMemcpyHostToDevice));

        int grid = (ni + BLOCK - 1) / BLOCK;

        for (int w = 0; w < 3; ++w) // Warm-up: Context/JIT/Taktboost
            bench_kernel<<<grid, BLOCK>>>(d_in, d_out, ni, k, d, warpUniform);
        CUDA_CHECK(cudaDeviceSynchronize());

        cudaEvent_t ev0, ev1;
        CUDA_CHECK(cudaEventCreate(&ev0));
        CUDA_CHECK(cudaEventCreate(&ev1));
        for (int r = 0; r < reps; ++r) {
            CUDA_CHECK(cudaEventRecord(ev0));
            bench_kernel<<<grid, BLOCK>>>(d_in, d_out, ni, k, d, warpUniform);
            CUDA_CHECK(cudaEventRecord(ev1));
            CUDA_CHECK(cudaEventSynchronize(ev1));
            float ms;
            CUDA_CHECK(cudaEventElapsedTime(&ms, ev0, ev1));
            times.push_back((double)ms);
        }
        CUDA_CHECK(cudaMemcpy(out.data(), d_out, (size_t)ni * sizeof(float),
                              cudaMemcpyDeviceToHost));
        CUDA_CHECK(cudaFree(d_in));
        CUDA_CHECK(cudaFree(d_out));
    } else if (mode == "cpu" || mode == "cpu-omp") {
#ifdef _OPENMP
        fprintf(stderr, "# CPU: %d OpenMP-Threads verfuegbar\n", omp_get_max_threads());
#endif
        cpu_bench(mode, in.data(), out.data(), ni, k, d); // Warm-up
        for (int r = 0; r < reps; ++r) {
            auto t0 = std::chrono::steady_clock::now();
            cpu_bench(mode, in.data(), out.data(), ni, k, d);
            auto t1 = std::chrono::steady_clock::now();
            times.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
        }
    } else {
        fprintf(stderr, "unbekannter Modus: %s\n", mode.c_str());
        return 1;
    }
    t_ms = median(times);

    // Korrektheit: Stichproben gegen skalare Referenz (prueft insbesondere,
    // dass jedes Element den richtigen Pfad genommen hat)
    std::string chk = "-";
    if (check) {
        int samples = 1024, bad = 0;
        for (int s = 0; s < samples; ++s) {
            long long i = (long long)s * ni / samples;
            float ref = chain_ref(in[(size_t)i], k, path_of(mode, i, d));
            float got = out[(size_t)i];
            float tol = 1e-4f * (fabsf(ref) + 1e-6f);
            if (fabsf(got - ref) > tol) {
                if (bad < 5)
                    fprintf(stderr, "# CHECK-FEHLER i=%lld ref=%g got=%g\n",
                            i, ref, got);
                ++bad;
            }
        }
        chk = bad ? "FAIL" : "ok";
        fprintf(stderr, "# check: %s (%d/%d Stichproben abweichend)\n",
                chk.c_str(), bad, samples);
    }

    double gflops = 2.0 * (double)k * (double)ni / (t_ms * 1e-3) / 1e9;
    if (header)
        printf("mode,n,k,d,time_ms,gflops,check\n");
    printf("%s,%d,%d,%d,%.4f,%.2f,%s\n", mode.c_str(), ni, k, d, t_ms, gflops,
           chk.c_str());
    return 0;
}
