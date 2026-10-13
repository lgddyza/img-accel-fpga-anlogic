// Shared library for asynchronous detection of reconstructed GREY8 video frames.
// g++ -O3 -std=c++17 -fPIC -shared rk3576_infer.cpp -I. -o libroad_infer.so \
//   $(pkg-config --cflags --libs opencv4) -lrknnrt
#define ROAD_LIBRARY
#include "rk3576_benchmark.cpp"

#include <cstring>

namespace {
rknn_context context = 0;
std::vector<rknn_tensor_attr> attributes;
std::string last_error;
}

extern "C" {
struct RoadBox {
  int cls;
  float score, x1, y1, x2, y2;
};

const char* road_error() { return last_error.c_str(); }

int road_init(const char* path) {
  try {
    if (context) throw std::runtime_error("Already initialized");
    cv::setNumThreads(1);
    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("Cannot open model");
    std::vector<char> bytes((std::istreambuf_iterator<char>(file)), {});
    if (rknn_init(&context, bytes.data(), bytes.size(), 0, nullptr))
      throw std::runtime_error("rknn_init failed");
    if (rknn_set_core_mask(context, RKNN_NPU_CORE_0_1))
      throw std::runtime_error("Cannot set NPU core mask 0_1");
    rknn_input_output_num io{};
    if (rknn_query(context, RKNN_QUERY_IN_OUT_NUM, &io, sizeof(io)) ||
        io.n_input != 1 || io.n_output != 9)
      throw std::runtime_error("Expected one input and nine RKOPT outputs");
    attributes.resize(9);
    for (int i = 0; i < 9; ++i) {
      attributes[i].index = i;
      if (rknn_query(context, RKNN_QUERY_OUTPUT_ATTR, &attributes[i], sizeof(attributes[i])))
        throw std::runtime_error("Output attribute query failed");
    }
    g_classes = attributes[1].dims[1];
    if (g_classes != 1 && g_classes != 6)
      throw std::runtime_error("Expected one or six classes");
    return 0;
  } catch (const std::exception& e) {
    last_error = e.what();
    if (context) { rknn_destroy(context); context = 0; }
    return -1;
  }
}

int road_detect(const unsigned char* gray, int width, int height,
                float confidence, RoadBox* boxes, int capacity) {
  try {
    if (!context || !gray || width <= 0 || height <= 0 || capacity < 0)
      throw std::runtime_error("Invalid detector state or frame");
    cv::Mat original(height, width, CV_8UC1, const_cast<unsigned char*>(gray));
    Prepared prep = prepare(original);
    rknn_input input{};
    input.index = 0;
    input.buf = prep.rgb.data;
    input.size = prep.rgb.total() * prep.rgb.elemSize();
    input.type = RKNN_TENSOR_UINT8;
    input.fmt = RKNN_TENSOR_NHWC;
    if (rknn_inputs_set(context, 1, &input) || rknn_run(context, nullptr))
      throw std::runtime_error("RKNN inference failed");
    std::vector<rknn_output> outputs(9);
    for (int i = 0; i < 9; ++i) { outputs[i].index = i; outputs[i].want_float = 0; }
    if (rknn_outputs_get(context, 9, outputs.data(), nullptr))
      throw std::runtime_error("RKNN output retrieval failed");
    std::vector<Detection> found;
    try {
      found = decode(outputs, attributes, true, original.size(), prep, confidence);
    } catch (...) {
      rknn_outputs_release(context, 9, outputs.data());
      throw;
    }
    rknn_outputs_release(context, 9, outputs.data());
    int count = std::min(int(found.size()), capacity);
    for (int i = 0; i < count; ++i)
      boxes[i] = {found[i].cls, found[i].score, found[i].x1,
                  found[i].y1, found[i].x2, found[i].y2};
    return count;
  } catch (const std::exception& e) {
    last_error = e.what();
    return -1;
  }
}

void road_close() {
  if (context) { rknn_destroy(context); context = 0; }
  attributes.clear();
}
}
