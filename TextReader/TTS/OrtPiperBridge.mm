#include "OrtPiperBridge.h"

#include "../../ThirdParty/onnxruntime.xcframework/macos-arm64_x86_64/onnxruntime.framework/Headers/onnxruntime_c_api.h"

#include <cstring>
#include <memory>
#include <string>
#include <vector>

namespace {
constexpr OrtLoggingLevel kLogLevel = ORT_LOGGING_LEVEL_WARNING;
constexpr GraphOptimizationLevel kGraphOptimizationLevel = ORT_ENABLE_BASIC;
constexpr OrtAllocatorType kArenaAllocator = OrtArenaAllocator;
constexpr OrtMemType kDefaultMemType = OrtMemTypeDefault;

char *CopyCString(const char *value) {
    if (value == nullptr) {
        return nullptr;
    }

    const size_t length = std::strlen(value) + 1;
    auto *copy = static_cast<char *>(std::malloc(length));
    if (copy != nullptr) {
        std::memcpy(copy, value, length);
    }
    return copy;
}

char *CopyStatusMessage(const OrtApi *api, OrtStatus *status) {
    if (status == nullptr) {
        return nullptr;
    }

    const char *message = api != nullptr ? api->GetErrorMessage(status) : "Unknown ONNX Runtime error";
    char *copy = CopyCString(message != nullptr ? message : "Unknown ONNX Runtime error");
    if (api != nullptr) {
        api->ReleaseStatus(status);
    }
    return copy;
}

void SetErrorMessage(char **errorMessage, char *message) {
    if (errorMessage == nullptr) {
        std::free(message);
        return;
    }

    if (*errorMessage != nullptr) {
        std::free(*errorMessage);
    }
    *errorMessage = message;
}

void SetErrorMessage(char **errorMessage, const std::string &message) {
    SetErrorMessage(errorMessage, CopyCString(message.c_str()));
}

struct SessionOptionsReleaser {
    const OrtApi *api = nullptr;
    void operator()(OrtSessionOptions *options) const {
        if (api != nullptr && options != nullptr) {
            api->ReleaseSessionOptions(options);
        }
    }
};

struct MemoryInfoReleaser {
    const OrtApi *api = nullptr;
    void operator()(OrtMemoryInfo *info) const {
        if (api != nullptr && info != nullptr) {
            api->ReleaseMemoryInfo(info);
        }
    }
};

struct ValueReleaser {
    const OrtApi *api = nullptr;
    void operator()(OrtValue *value) const {
        if (api != nullptr && value != nullptr) {
            api->ReleaseValue(value);
        }
    }
};

struct TensorShapeReleaser {
    const OrtApi *api = nullptr;
    void operator()(OrtTensorTypeAndShapeInfo *info) const {
        if (api != nullptr && info != nullptr) {
            api->ReleaseTensorTypeAndShapeInfo(info);
        }
    }
};

bool LoadSessionIO(class TROrtPiperSession *session, char **errorMessage);

}  // namespace

struct TROrtPiperSession {
    const OrtApi *api = nullptr;
    OrtEnv *env = nullptr;
    OrtSession *session = nullptr;
    std::vector<std::string> inputNames;
    std::vector<std::string> outputNames;

    ~TROrtPiperSession() {
        if (api != nullptr && session != nullptr) {
            api->ReleaseSession(session);
            session = nullptr;
        }
        if (api != nullptr && env != nullptr) {
            api->ReleaseEnv(env);
            env = nullptr;
        }
    }
};

namespace {

bool LoadSessionIO(TROrtPiperSession *session, char **errorMessage) {
    if (session == nullptr || session->api == nullptr || session->session == nullptr) {
        SetErrorMessage(errorMessage, "Invalid ONNX Runtime session handle.");
        return false;
    }

    OrtAllocator *allocator = nullptr;
    if (OrtStatus *status = session->api->GetAllocatorWithDefaultOptions(&allocator)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(session->api, status));
        return false;
    }

    size_t inputCount = 0;
    if (OrtStatus *status = session->api->SessionGetInputCount(session->session, &inputCount)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(session->api, status));
        return false;
    }

    size_t outputCount = 0;
    if (OrtStatus *status = session->api->SessionGetOutputCount(session->session, &outputCount)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(session->api, status));
        return false;
    }

    session->inputNames.clear();
    session->inputNames.reserve(inputCount);
    for (size_t index = 0; index < inputCount; ++index) {
        char *name = nullptr;
        if (OrtStatus *status = session->api->SessionGetInputName(session->session, index, allocator, &name)) {
            SetErrorMessage(errorMessage, CopyStatusMessage(session->api, status));
            return false;
        }
        session->inputNames.emplace_back(name != nullptr ? name : "");
        if (name != nullptr) {
            (void)session->api->AllocatorFree(allocator, name);
        }
    }

    session->outputNames.clear();
    session->outputNames.reserve(outputCount);
    for (size_t index = 0; index < outputCount; ++index) {
        char *name = nullptr;
        if (OrtStatus *status = session->api->SessionGetOutputName(session->session, index, allocator, &name)) {
            SetErrorMessage(errorMessage, CopyStatusMessage(session->api, status));
            return false;
        }
        session->outputNames.emplace_back(name != nullptr ? name : "");
        if (name != nullptr) {
            (void)session->api->AllocatorFree(allocator, name);
        }
    }

    return true;
}

}  // namespace

extern "C" TROrtPiperSession *TROrtPiperSessionCreate(const char *modelPathUTF8,
                                                       char **errorMessage) {
    if (errorMessage != nullptr) {
        *errorMessage = nullptr;
    }

    if (modelPathUTF8 == nullptr || modelPathUTF8[0] == '\0') {
        SetErrorMessage(errorMessage, "Model path is empty.");
        return nullptr;
    }

    const OrtApiBase *apiBase = OrtGetApiBase();
    if (apiBase == nullptr) {
        SetErrorMessage(errorMessage, "OrtGetApiBase() returned null.");
        return nullptr;
    }

    const OrtApi *api = apiBase->GetApi(ORT_API_VERSION);
    if (api == nullptr) {
        SetErrorMessage(errorMessage, "GetApi(ORT_API_VERSION) returned null.");
        return nullptr;
    }

    auto session = std::make_unique<TROrtPiperSession>();
    session->api = api;

    if (OrtStatus *status = api->CreateEnv(kLogLevel, "TextReaderTTS", &session->env)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return nullptr;
    }

    OrtSessionOptions *rawOptions = nullptr;
    if (OrtStatus *status = api->CreateSessionOptions(&rawOptions)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return nullptr;
    }
    std::unique_ptr<OrtSessionOptions, SessionOptionsReleaser> options(rawOptions, SessionOptionsReleaser{api});

    if (OrtStatus *status = api->SetIntraOpNumThreads(options.get(), 1)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return nullptr;
    }
    if (OrtStatus *status = api->SetInterOpNumThreads(options.get(), 1)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return nullptr;
    }
    if (OrtStatus *status = api->SetSessionGraphOptimizationLevel(options.get(), kGraphOptimizationLevel)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return nullptr;
    }

    if (OrtStatus *status = api->CreateSession(session->env, modelPathUTF8, options.get(), &session->session)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return nullptr;
    }

    if (!LoadSessionIO(session.get(), errorMessage)) {
        return nullptr;
    }

    return session.release();
}

extern "C" void TROrtPiperSessionDestroy(TROrtPiperSession *session) {
    delete session;
}

extern "C" bool TROrtPiperSessionCopyIO(TROrtPiperSession *session,
                                         TROrtCStringArray *inputNames,
                                         TROrtCStringArray *outputNames,
                                         char **errorMessage) {
    if (errorMessage != nullptr) {
        *errorMessage = nullptr;
    }

    if (session == nullptr || inputNames == nullptr || outputNames == nullptr) {
        SetErrorMessage(errorMessage, "Invalid arguments while copying ONNX session IO names.");
        return false;
    }

    inputNames->items = nullptr;
    inputNames->count = 0;
    outputNames->items = nullptr;
    outputNames->count = 0;

    auto makeArray = [](const std::vector<std::string> &names, TROrtCStringArray *target, char **errorMessage) -> bool {
        if (names.empty()) {
            target->items = nullptr;
            target->count = 0;
            return true;
        }

        auto **items = static_cast<char **>(std::calloc(names.size(), sizeof(char *)));
        if (items == nullptr) {
            SetErrorMessage(errorMessage, "Failed to allocate IO name array.");
            return false;
        }

        for (size_t index = 0; index < names.size(); ++index) {
            items[index] = CopyCString(names[index].c_str());
            if (items[index] == nullptr) {
                for (size_t cleanup = 0; cleanup < index; ++cleanup) {
                    std::free(items[cleanup]);
                }
                std::free(items);
                SetErrorMessage(errorMessage, "Failed to copy ONNX IO name.");
                return false;
            }
        }

        target->items = items;
        target->count = names.size();
        return true;
    };

    if (!makeArray(session->inputNames, inputNames, errorMessage)) {
        return false;
    }
    if (!makeArray(session->outputNames, outputNames, errorMessage)) {
        TROrtCStringArrayFree(*inputNames);
        inputNames->items = nullptr;
        inputNames->count = 0;
        return false;
    }

    return true;
}

extern "C" bool TROrtPiperSessionSynthesize(TROrtPiperSession *session,
                                             const int64_t *inputIDs,
                                             size_t inputIDCount,
                                             float noiseScale,
                                             float lengthScale,
                                             float noiseW,
                                             bool includeSID,
                                             int64_t sid,
                                             TROrtFloatArray *outputWaveform,
                                             char **errorMessage) {
    if (errorMessage != nullptr) {
        *errorMessage = nullptr;
    }

    if (outputWaveform == nullptr) {
        SetErrorMessage(errorMessage, "Output waveform pointer is null.");
        return false;
    }
    outputWaveform->data = nullptr;
    outputWaveform->count = 0;

    if (session == nullptr || session->api == nullptr || session->session == nullptr) {
        SetErrorMessage(errorMessage, "ONNX Runtime session is not initialized.");
        return false;
    }
    if (inputIDs == nullptr || inputIDCount == 0) {
        SetErrorMessage(errorMessage, "Piper input ids are empty.");
        return false;
    }
    if (session->outputNames.empty()) {
        SetErrorMessage(errorMessage, "ONNX model does not expose any outputs.");
        return false;
    }

    const OrtApi *api = session->api;

    OrtMemoryInfo *rawMemoryInfo = nullptr;
    if (OrtStatus *status = api->CreateCpuMemoryInfo(kArenaAllocator, kDefaultMemType, &rawMemoryInfo)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return false;
    }
    std::unique_ptr<OrtMemoryInfo, MemoryInfoReleaser> memoryInfo(rawMemoryInfo, MemoryInfoReleaser{api});

    std::vector<int64_t> ids(inputIDs, inputIDs + inputIDCount);
    std::vector<int64_t> lengths = {static_cast<int64_t>(inputIDCount)};
    std::vector<float> scales = {noiseScale, lengthScale, noiseW};
    std::vector<int64_t> sidValues = {sid};

    const std::vector<int64_t> idsShape = {1, static_cast<int64_t>(inputIDCount)};
    const std::vector<int64_t> lengthsShape = {1};
    const std::vector<int64_t> scalesShape = {3};
    const std::vector<int64_t> sidShape = {1};

    OrtValue *rawInputIDsValue = nullptr;
    if (OrtStatus *status = api->CreateTensorWithDataAsOrtValue(memoryInfo.get(), ids.data(),
                                                                ids.size() * sizeof(int64_t), idsShape.data(), idsShape.size(),
                                                                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &rawInputIDsValue)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return false;
    }
    std::unique_ptr<OrtValue, ValueReleaser> inputIDsValue(rawInputIDsValue, ValueReleaser{api});

    OrtValue *rawLengthsValue = nullptr;
    if (OrtStatus *status = api->CreateTensorWithDataAsOrtValue(memoryInfo.get(), lengths.data(),
                                                                lengths.size() * sizeof(int64_t), lengthsShape.data(), lengthsShape.size(),
                                                                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &rawLengthsValue)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return false;
    }
    std::unique_ptr<OrtValue, ValueReleaser> lengthsValue(rawLengthsValue, ValueReleaser{api});

    OrtValue *rawScalesValue = nullptr;
    if (OrtStatus *status = api->CreateTensorWithDataAsOrtValue(memoryInfo.get(), scales.data(),
                                                                scales.size() * sizeof(float), scalesShape.data(), scalesShape.size(),
                                                                ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &rawScalesValue)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return false;
    }
    std::unique_ptr<OrtValue, ValueReleaser> scalesValue(rawScalesValue, ValueReleaser{api});

    std::unique_ptr<OrtValue, ValueReleaser> sidValue(nullptr, ValueReleaser{api});
    if (includeSID) {
        OrtValue *rawSIDValue = nullptr;
        if (OrtStatus *status = api->CreateTensorWithDataAsOrtValue(memoryInfo.get(), sidValues.data(),
                                                                    sidValues.size() * sizeof(int64_t), sidShape.data(), sidShape.size(),
                                                                    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &rawSIDValue)) {
            SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
            return false;
        }
        sidValue.reset(rawSIDValue);
    }

    std::vector<const char *> runInputNames;
    std::vector<const OrtValue *> runInputValues;
    runInputNames.reserve(session->inputNames.size());
    runInputValues.reserve(session->inputNames.size());

    for (const auto &inputName : session->inputNames) {
        const OrtValue *matchedValue = nullptr;

        if (inputName == "input" || inputName == "input_ids") {
            matchedValue = inputIDsValue.get();
        } else if (inputName == "input_lengths") {
            matchedValue = lengthsValue.get();
        } else if (inputName == "scales") {
            matchedValue = scalesValue.get();
        } else if (inputName == "sid") {
            if (sidValue.get() == nullptr) {
                SetErrorMessage(errorMessage, "The model requires `sid`, but no speaker id tensor was created.");
                return false;
            }
            matchedValue = sidValue.get();
        } else {
            SetErrorMessage(errorMessage, std::string("Unsupported ONNX input name: ") + inputName);
            return false;
        }

        runInputNames.push_back(inputName.c_str());
        runInputValues.push_back(matchedValue);
    }

    if (runInputNames.empty()) {
        SetErrorMessage(errorMessage, "The ONNX model does not expose any recognized inputs.");
        return false;
    }

    const char *outputName = session->outputNames.front().c_str();
    OrtValue *rawOutputValue = nullptr;
    if (OrtStatus *status = api->Run(session->session, nullptr,
                                     runInputNames.data(), runInputValues.data(), runInputValues.size(),
                                     &outputName, 1, &rawOutputValue)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return false;
    }
    std::unique_ptr<OrtValue, ValueReleaser> outputValue(rawOutputValue, ValueReleaser{api});

    OrtTensorTypeAndShapeInfo *rawShape = nullptr;
    if (OrtStatus *status = api->GetTensorTypeAndShape(outputValue.get(), &rawShape)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return false;
    }
    std::unique_ptr<OrtTensorTypeAndShapeInfo, TensorShapeReleaser> shapeInfo(rawShape, TensorShapeReleaser{api});

    ONNXTensorElementDataType elementType = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED;
    if (OrtStatus *status = api->GetTensorElementType(shapeInfo.get(), &elementType)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return false;
    }
    if (elementType != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
        SetErrorMessage(errorMessage, "The ONNX model output is not float32 waveform data.");
        return false;
    }

    size_t sampleCount = 0;
    if (OrtStatus *status = api->GetTensorShapeElementCount(shapeInfo.get(), &sampleCount)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return false;
    }
    if (sampleCount == 0) {
        SetErrorMessage(errorMessage, "The ONNX model returned an empty waveform.");
        return false;
    }

    void *rawSamples = nullptr;
    if (OrtStatus *status = api->GetTensorMutableData(outputValue.get(), &rawSamples)) {
        SetErrorMessage(errorMessage, CopyStatusMessage(api, status));
        return false;
    }
    if (rawSamples == nullptr) {
        SetErrorMessage(errorMessage, "The ONNX model returned a null waveform pointer.");
        return false;
    }

    auto *copiedSamples = static_cast<float *>(std::malloc(sampleCount * sizeof(float)));
    if (copiedSamples == nullptr) {
        SetErrorMessage(errorMessage, "Failed to allocate output waveform buffer.");
        return false;
    }

    std::memcpy(copiedSamples, rawSamples, sampleCount * sizeof(float));
    outputWaveform->data = copiedSamples;
    outputWaveform->count = sampleCount;
    return true;
}

extern "C" void TROrtCStringArrayFree(TROrtCStringArray array) {
    if (array.items == nullptr) {
        return;
    }

    for (size_t index = 0; index < array.count; ++index) {
        std::free(array.items[index]);
    }
    std::free(array.items);
}

extern "C" void TROrtFloatArrayFree(TROrtFloatArray array) {
    std::free(array.data);
}

extern "C" void TROrtFreeCString(char *string) {
    std::free(string);
}
