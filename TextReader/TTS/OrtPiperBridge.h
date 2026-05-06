#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TROrtPiperSession TROrtPiperSession;

typedef struct TROrtCStringArray {
    char * _Nullable * _Nullable items;
    size_t count;
} TROrtCStringArray;

typedef struct TROrtFloatArray {
    float * _Nullable data;
    size_t count;
} TROrtFloatArray;

TROrtPiperSession * _Nullable TROrtPiperSessionCreate(const char * _Nonnull modelPathUTF8,
                                                     char * _Nullable * _Nullable errorMessage);
void TROrtPiperSessionDestroy(TROrtPiperSession * _Nullable session);

bool TROrtPiperSessionCopyIO(TROrtPiperSession * _Nonnull session,
                             TROrtCStringArray * _Nonnull inputNames,
                             TROrtCStringArray * _Nonnull outputNames,
                             char * _Nullable * _Nullable errorMessage);

bool TROrtPiperSessionSynthesize(TROrtPiperSession * _Nonnull session,
                                 const int64_t * _Nonnull inputIDs,
                                 size_t inputIDCount,
                                 float noiseScale,
                                 float lengthScale,
                                 float noiseW,
                                 bool includeSID,
                                 int64_t sid,
                                 TROrtFloatArray * _Nonnull outputWaveform,
                                 char * _Nullable * _Nullable errorMessage);

void TROrtCStringArrayFree(TROrtCStringArray array);
void TROrtFloatArrayFree(TROrtFloatArray array);
void TROrtFreeCString(char * _Nullable string);

#ifdef __cplusplus
}
#endif
