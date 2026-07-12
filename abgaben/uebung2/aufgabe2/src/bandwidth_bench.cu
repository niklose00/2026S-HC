// Speicherbandbreite & Latenz-Verstecken (HC Uebungsblatt 2, Aufgabe 2)
//
// Speicherintensiver Streaming-Kernel mit minimaler Rechenlast: b[i] = a[idx(i)] * c
// (1 Load, 1 Store, 1 Multiplikation -> arithmetische Intensitaet 0,125 FLOP/Byte).
// Gemessen wird die effektive Bandbreite fuer drei Zugriffsmuster auf a:
//
//   coalesced  idx = i                          (Stride 1, zusammenhaengend)
//   strided    idx = (i % m)*stride + (i / m)   (Transpose-Bijektion, Stride k;
//                                                deckt a genau einmal ab, keine
//                                                kuenstliche Cache-Wiederverwendung)
//   gather     idx = perm[i]                    (zufaellige Permutation)
//
// Ausserdem laesst sich ueber --bps (residente Bloecke pro SM) die Occupancy und
// damit die Zahl gleichzeitiger Warps variieren -- so wird sichtbar, dass die GPU
// Latenz ueber viele Warps versteckt.
//
// Effektive Bandbreite: 2 Arrays (a gelesen, b geschrieben) => 8*n Byte / t.
// (Bei gather kommt der Index-Strom hinzu; fuer den fairen Muster-Vergleich wird
//  die "nuetzliche" Bandbreite 8*n/t ausgewiesen, siehe Bericht.)

#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <vector>
#include <algorithm>
#include <random>
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

enum { MODE_COALESCED = 0, MODE_STRIDED = 1, MODE_GATHER = 2 };

// Ein Grid-Stride-Loop-Kernel je Muster. Der Grid-Stride-Loop entkoppelt die
// Zahl gestarteter Bloecke von n: mit weniger Bloecken sind weniger Warps
// resident (niedrigere Occupancy), decken aber via Schleife trotzdem ganz n ab.
template <int MODE>
__global__ void stream_kernel(const float *a, float *b, const int *perm,
                              int n, int stride, int m, float c)
{
    int gstride = gridDim.x * blockDim.x;
    for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += gstride) {
        int j;
        if (MODE == MODE_COALESCED)   j = i;
        else if (MODE == MODE_STRIDED) j = (i % m) * stride + (i / m);
        else                           j = perm[i];
        b[i] = a[j] * c;
    }
}

// Host-Referenz fuer den Index (fuer Korrektheitscheck)
static long long idx_of(int mode, long long i, int stride, int m, const int *perm)
{
    if (mode == MODE_COALESCED) return i;
    if (mode == MODE_STRIDED)   return (i % m) * (long long)stride + (i / m);
    return perm[i];
}

static void cpu_stream(int mode, const float *a, float *b, const int *perm,
                       int n, int stride, int m, float c, bool omp)
{
#ifdef _OPENMP
    #pragma omp parallel for schedule(static) if(omp)
#endif
    for (int i = 0; i < n; ++i) {
        long long j;
        if (mode == MODE_COALESCED)   j = i;
        else if (mode == MODE_STRIDED) j = (i % m) * (long long)stride + (i / m);
        else                           j = perm[i];
        b[i] = a[j] * c;
    }
    (void)omp;
}

static double median(std::vector<double> v)
{
    std::sort(v.begin(), v.end());
    return v[v.size() / 2];
}

static int mode_from_str(const std::string &s)
{
    if (s == "coalesced") return MODE_COALESCED;
    if (s == "strided")   return MODE_STRIDED;
    if (s == "gather")    return MODE_GATHER;
    return -1;
}

int main(int argc, char **argv)
{
    std::string mode = "coalesced";
    long long n = 1LL << 26;          // 67M Elemente => 256 MB je Array
    int stride = 1, block = 256, bps = 0, reps = 10;
    bool check = false, header = false;
    const float c = 1.000001f;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() { return std::string(argv[++i]); };
        if      (a == "--mode")   mode   = next();
        else if (a == "--n")      n      = atoll(next().c_str());
        else if (a == "--stride") stride = atoi(next().c_str());
        else if (a == "--block")  block  = atoi(next().c_str());
        else if (a == "--bps")    bps    = atoi(next().c_str()); // Bloecke/SM (0=voll)
        else if (a == "--reps")   reps   = atoi(next().c_str());
        else if (a == "--check")  check  = true;
        else if (a == "--header") header = true;
        else { fprintf(stderr, "unbekanntes Argument: %s\n", a.c_str()); return 1; }
    }

    bool isGpu = (mode == "coalesced" || mode == "strided" || mode == "gather");
    bool isCpu = (mode.rfind("cpu", 0) == 0); // "cpu-seq", "cpu-rand", "cpu-omp-seq", ...
    // CPU-Modi tragen das Muster als Suffix: cpu:seq / cpu:rand -- vereinfacht:
    // fuer die CPU messen wir sequentiell (coalesced) und zufaellig (gather).
    int gmode = isGpu ? mode_from_str(mode) : MODE_COALESCED;

    if (n <= 0) { fprintf(stderr, "n muss > 0 sein\n"); return 1; }
    if (stride < 1) { fprintf(stderr, "stride muss >= 1 sein\n"); return 1; }
    if (n % stride != 0) { fprintf(stderr, "n muss durch stride teilbar sein\n"); return 1; }
    int ni = (int)n;
    int m = ni / stride;

    // Host-Daten
    std::vector<float> h_a((size_t)ni), h_b((size_t)ni, 0.0f);
    for (int i = 0; i < ni; ++i) h_a[(size_t)i] = 1.0f + 1e-6f * (float)(i % 1000);

    // Zufalls-Permutation fuer gather (auch fuer CPU-random genutzt)
    std::vector<int> h_perm((size_t)ni);
    for (int i = 0; i < ni; ++i) h_perm[(size_t)i] = i;
    {
        std::mt19937 rng(12345);
        for (int i = ni - 1; i > 0; --i) {
            int j = (int)(rng() % (unsigned)(i + 1));
            std::swap(h_perm[(size_t)i], h_perm[(size_t)j]);
        }
    }

    double t_ms = 0.0;
    std::vector<double> times;
    double occ_pct = -1.0;
    int warpsPerSM = -1;

    if (isGpu) {
        cudaDeviceProp prop;
        CUDA_CHECK(cudaGetDeviceProperties(&prop, 0));
        double peak_gbs = 2.0 * prop.memoryClockRate * (prop.memoryBusWidth / 8) / 1.0e6;
        int maxWarpsPerSM = prop.maxThreadsPerMultiProcessor / 32;

        // maximale residente Bloecke/SM fuer diese Blockgroesse
        int maxBlocksPerSM = 0;
        CUDA_CHECK(cudaOccupancyMaxActiveBlocksPerMultiprocessor(
            &maxBlocksPerSM, stream_kernel<MODE_COALESCED>, block, 0));

        int wantBps = (bps > 0) ? bps : maxBlocksPerSM;
        int resBps  = std::min(wantBps, maxBlocksPerSM); // real resident
        int grid    = wantBps * prop.multiProcessorCount;
        warpsPerSM  = resBps * (block / 32);
        occ_pct     = 100.0 * (double)warpsPerSM / (double)maxWarpsPerSM;

        fprintf(stderr, "# GPU: %s, %d SMs, Peak-BW %.0f GB/s, maxBlocks/SM(%d)=%d, "
                        "Occupancy %.0f%%\n",
                prop.name, prop.multiProcessorCount, peak_gbs, block,
                maxBlocksPerSM, occ_pct);

        float *d_a, *d_b; int *d_perm;
        CUDA_CHECK(cudaMalloc(&d_a, (size_t)ni * sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_b, (size_t)ni * sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_perm, (size_t)ni * sizeof(int)));
        CUDA_CHECK(cudaMemcpy(d_a, h_a.data(), (size_t)ni * sizeof(float), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(d_perm, h_perm.data(), (size_t)ni * sizeof(int), cudaMemcpyHostToDevice));

        auto launch = [&]() {
            if (gmode == MODE_COALESCED) stream_kernel<MODE_COALESCED><<<grid, block>>>(d_a, d_b, d_perm, ni, stride, m, c);
            else if (gmode == MODE_STRIDED) stream_kernel<MODE_STRIDED><<<grid, block>>>(d_a, d_b, d_perm, ni, stride, m, c);
            else stream_kernel<MODE_GATHER><<<grid, block>>>(d_a, d_b, d_perm, ni, stride, m, c);
        };

        for (int w = 0; w < 3; ++w) launch();           // Warm-up
        CUDA_CHECK(cudaGetLastError());
        CUDA_CHECK(cudaDeviceSynchronize());

        cudaEvent_t ev0, ev1;
        CUDA_CHECK(cudaEventCreate(&ev0));
        CUDA_CHECK(cudaEventCreate(&ev1));
        for (int r = 0; r < reps; ++r) {
            CUDA_CHECK(cudaEventRecord(ev0));
            launch();
            CUDA_CHECK(cudaEventRecord(ev1));
            CUDA_CHECK(cudaEventSynchronize(ev1));
            float ms; CUDA_CHECK(cudaEventElapsedTime(&ms, ev0, ev1));
            times.push_back((double)ms);
        }
        CUDA_CHECK(cudaMemcpy(h_b.data(), d_b, (size_t)ni * sizeof(float), cudaMemcpyDeviceToHost));
        CUDA_CHECK(cudaFree(d_a)); CUDA_CHECK(cudaFree(d_b)); CUDA_CHECK(cudaFree(d_perm));
    } else if (isCpu) {
        // CPU-Muster ueber den Modusnamen: "seq" -> sequentiell (coalesced),
        // "rand" -> zufaellig (gather). "omp" schaltet OpenMP ein.
        bool omp = (mode.find("omp") != std::string::npos);
        int cmode = (mode.find("rand") != std::string::npos) ? MODE_GATHER : MODE_COALESCED;
#ifdef _OPENMP
        fprintf(stderr, "# CPU: %d Thread(s), Muster %s\n",
                omp ? omp_get_max_threads() : 1,
                cmode == MODE_GATHER ? "random" : "sequentiell");
#endif
        cpu_stream(cmode, h_a.data(), h_b.data(), h_perm.data(), ni, stride, m, c, omp);
        for (int r = 0; r < reps; ++r) {
            auto t0 = std::chrono::steady_clock::now();
            cpu_stream(cmode, h_a.data(), h_b.data(), h_perm.data(), ni, stride, m, c, omp);
            auto t1 = std::chrono::steady_clock::now();
            times.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
        }
        gmode = cmode;
    } else {
        fprintf(stderr, "unbekannter Modus: %s\n", mode.c_str());
        return 1;
    }
    t_ms = median(times);

    // Korrektheit
    std::string chk = "-";
    if (check) {
        int samples = 1024, bad = 0;
        for (int s = 0; s < samples; ++s) {
            long long i = (long long)s * ni / samples;
            long long j = idx_of(gmode, i, stride, m, h_perm.data());
            float ref = h_a[(size_t)j] * c;
            if (fabsf(h_b[(size_t)i] - ref) > 1e-3f * (fabsf(ref) + 1e-6f)) ++bad;
        }
        chk = bad ? "FAIL" : "ok";
        fprintf(stderr, "# check: %s (%d/%d abweichend)\n", chk.c_str(), bad, samples);
    }

    // Effektive Bandbreite: a gelesen + b geschrieben = 8*n Byte
    double gbs = 8.0 * (double)ni / (t_ms * 1e-3) / 1e9;
    if (header)
        printf("mode,n,stride,block,bps,warps_per_sm,occ_pct,time_ms,gb_s,check\n");
    printf("%s,%d,%d,%d,%d,%d,%.1f,%.4f,%.2f,%s\n",
           mode.c_str(), ni, stride, block, bps, warpsPerSM, occ_pct,
           t_ms, gbs, chk.c_str());
    return 0;
}
