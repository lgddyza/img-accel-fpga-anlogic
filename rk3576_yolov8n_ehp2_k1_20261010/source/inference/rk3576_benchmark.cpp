// RK3576 YOLOv8n RKOPT smoke test. Requires librknnrt and OpenCV 4.
// Build on board: g++ -O3 -std=c++17 rk3576_benchmark.cpp -I. -o rk3576_benchmark
//                 $(pkg-config --cflags --libs opencv4) -lrknnrt

#include "rknn_api.h"

#include <opencv2/opencv.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using Clock = std::chrono::steady_clock;
constexpr int kSize = 640;
int g_classes = 6;
const char* kNames[6] = {"Alligator crack", "Longitudinal crack", "Oblique crack",
                         "Pothole", "Repair", "Transverse crack"};

struct Detection {
  int cls;
  float score, x1, y1, x2, y2;
};

struct Prepared {
  cv::Mat rgb;
  float scale;
  int left, top;
};

Prepared prepare(const cv::Mat& original) {
  cv::Mat gray;
  if (original.channels() == 1) gray = original;
  else cv::cvtColor(original, gray, cv::COLOR_BGR2GRAY);
  float scale = std::min(float(kSize) / gray.cols, float(kSize) / gray.rows);
  int nw = std::lround(gray.cols * scale), nh = std::lround(gray.rows * scale);
  int left = (kSize - nw) / 2, top = (kSize - nh) / 2;
  cv::Mat resized, canvas(kSize, kSize, CV_8UC1, cv::Scalar(114)), rgb;
  cv::resize(gray, resized, cv::Size(nw, nh), 0, 0, cv::INTER_LINEAR);
  resized.copyTo(canvas(cv::Rect(left, top, nw, nh)));
  cv::cvtColor(canvas, rgb, cv::COLOR_GRAY2RGB);
  return {rgb, scale, left, top};
}

float overlap(const Detection& a, const Detection& b) {
  float w = std::max(0.0f, std::min(a.x2, b.x2) - std::max(a.x1, b.x1));
  float h = std::max(0.0f, std::min(a.y2, b.y2) - std::max(a.y1, b.y1));
  float inter = w * h;
  float area_a = (a.x2 - a.x1) * (a.y2 - a.y1);
  float area_b = (b.x2 - b.x1) * (b.y2 - b.y1);
  return inter / std::max(area_a + area_b - inter, 1e-9f);
}

std::vector<Detection> decode(const std::vector<rknn_output>& out,
                              const std::vector<rknn_tensor_attr>& attrs, bool int8_output,
                              const cv::Size& source, const Prepared& prep,
                              float threshold = 0.10f) {
  std::vector<Detection> candidates;
  auto value = [&](int output, int offset) -> float {
    if (!int8_output) return static_cast<const float*>(out[output].buf)[offset];
    int8_t q = static_cast<const int8_t*>(out[output].buf)[offset];
    return (int(q) - attrs[output].zp) * attrs[output].scale;
  };
  for (int branch = 0; branch < 3; ++branch) {
    int reg = 3 * branch, cls = reg + 1, sum = reg + 2;
    int grid = 80 >> branch, area = grid * grid;
    float stride = float(kSize) / grid;
    for (int pos = 0; pos < area; ++pos) {
      if (value(sum, pos) < threshold) continue;
      int best = 0;
      float score = value(cls, pos);
      for (int c = 1; c < g_classes; ++c) {
        float current = value(cls, c * area + pos);
        if (current > score) { score = current; best = c; }
      }
      if (score < threshold) continue;
      float dist[4];
      for (int side = 0; side < 4; ++side) {
        float max_logit = -1e30f;
        for (int bin = 0; bin < 16; ++bin)
          max_logit = std::max(max_logit, value(reg, (side * 16 + bin) * area + pos));
        float total = 0, weighted = 0;
        for (int bin = 0; bin < 16; ++bin) {
          float p = std::exp(value(reg, (side * 16 + bin) * area + pos) - max_logit);
          total += p;
          weighted += bin * p;
        }
        dist[side] = weighted / total;
      }
      float cx = (pos % grid) + 0.5f, cy = (pos / grid) + 0.5f;
      candidates.push_back({best, score,
                            (cx - dist[0]) * stride, (cy - dist[1]) * stride,
                            (cx + dist[2]) * stride, (cy + dist[3]) * stride});
    }
  }
  std::sort(candidates.begin(), candidates.end(),
            [](const Detection& a, const Detection& b) { return a.score > b.score; });
  std::vector<Detection> kept;
  for (auto d : candidates) {
    bool suppress = false;
    for (const auto& k : kept) {
      if (d.cls == k.cls && overlap(d, k) > 0.45f) { suppress = true; break; }
    }
    if (suppress) continue;
    kept.push_back(d);
    if (kept.size() == 300) break;
  }
  for (auto& d : kept) {
    d.x1 = std::clamp((d.x1 - prep.left) / prep.scale, 0.0f, float(source.width));
    d.x2 = std::clamp((d.x2 - prep.left) / prep.scale, 0.0f, float(source.width));
    d.y1 = std::clamp((d.y1 - prep.top) / prep.scale, 0.0f, float(source.height));
    d.y2 = std::clamp((d.y2 - prep.top) / prep.scale, 0.0f, float(source.height));
  }
  return kept;
}

double milliseconds(Clock::time_point a, Clock::time_point b) {
  return std::chrono::duration<double, std::milli>(b - a).count();
}

#ifndef ROAD_LIBRARY
int main(int argc, char** argv) {
  if (argc < 3) {
    std::cerr << "Usage: " << argv[0] << " model.rknn image.jpg [repeat=200] [confidence=0.1] [core=auto|all|01] [output=i8|float] [cv_threads=1]\n";
    return 2;
  }
  int repeat = argc > 3 ? std::stoi(argv[3]) : 200;
  float confidence = argc > 4 ? std::stof(argv[4]) : 0.10f;
  std::string core = argc > 5 ? argv[5] : "auto";
  bool int8_output = argc <= 6 || std::string(argv[6]) != "float";
  int cv_threads = argc > 7 ? std::stoi(argv[7]) : 1;
  cv::setNumThreads(cv_threads);
  cv::Mat original = cv::imread(argv[2], cv::IMREAD_GRAYSCALE);
  if (original.empty()) throw std::runtime_error("Cannot read image");
  std::ifstream model_file(argv[1], std::ios::binary);
  if (!model_file) throw std::runtime_error("Cannot read RKNN model");
  std::vector<char> model((std::istreambuf_iterator<char>(model_file)), {});
  rknn_context ctx = 0;
  int ret = rknn_init(&ctx, model.data(), model.size(), 0, nullptr);
  if (ret != 0) throw std::runtime_error("rknn_init failed: " + std::to_string(ret));
  if (core != "auto") {
    rknn_core_mask mask = core == "all" ? RKNN_NPU_CORE_ALL : RKNN_NPU_CORE_0_1;
    if (rknn_set_core_mask(ctx, mask) != 0) throw std::runtime_error("Unsupported NPU core mask");
  }
  rknn_input_output_num io{};
  if (rknn_query(ctx, RKNN_QUERY_IN_OUT_NUM, &io, sizeof(io)) != 0 ||
      io.n_input != 1 || io.n_output != 9)
    throw std::runtime_error("Expected 1 input and 9 RKOPT outputs");
  std::cout << "Input tensors: " << io.n_input << ", output tensors: " << io.n_output << "\n";
  std::vector<rknn_tensor_attr> attrs(io.n_output);
  for (uint32_t i = 0; i < io.n_output; ++i) {
    auto& attr = attrs[i];
    attr.index = i;
    if (rknn_query(ctx, RKNN_QUERY_OUTPUT_ATTR, &attr, sizeof(attr)) != 0)
      throw std::runtime_error("Output query failed");
    std::cout << "output[" << i << "] dims=";
    for (uint32_t j = 0; j < attr.n_dims; ++j) std::cout << attr.dims[j] << (j + 1 == attr.n_dims ? "" : "x");
    std::cout << " type=" << attr.type << " zp=" << attr.zp << " scale=" << attr.scale << "\n";
  }
  g_classes = attrs[1].dims[1];
  if (g_classes != 1 && g_classes != 6)
    throw std::runtime_error("Expected 1 or 6 classes in RKOPT output");
  double pre_total = 0, set_total = 0, run_total = 0, get_total = 0, post_total = 0;
  std::vector<double> total_samples;
  std::vector<Detection> final_detections;
  for (int iteration = -20; iteration < repeat; ++iteration) {
    auto t0 = Clock::now();
    Prepared prep = prepare(original);
    auto t1 = Clock::now();
    rknn_input input{};
    input.index = 0;
    input.buf = prep.rgb.data;
    input.size = prep.rgb.total() * prep.rgb.elemSize();
    input.type = RKNN_TENSOR_UINT8;
    input.fmt = RKNN_TENSOR_NHWC;
    if (rknn_inputs_set(ctx, 1, &input) != 0)
      throw std::runtime_error("NPU input failed");
    auto t_set = Clock::now();
    if (rknn_run(ctx, nullptr) != 0)
      throw std::runtime_error("NPU run failed");
    auto t_run = Clock::now();
    std::vector<rknn_output> outputs(9);
    for (uint32_t i = 0; i < 9; ++i) { outputs[i].index = i; outputs[i].want_float = !int8_output; }
    if (rknn_outputs_get(ctx, 9, outputs.data(), nullptr) != 0)
      throw std::runtime_error("Output retrieval failed");
    auto t2 = Clock::now();
    final_detections = decode(outputs, attrs, int8_output, original.size(), prep, confidence);
    rknn_outputs_release(ctx, 9, outputs.data());
    auto t3 = Clock::now();
    if (iteration >= 0) {
      pre_total += milliseconds(t0, t1);
      set_total += milliseconds(t1, t_set);
      run_total += milliseconds(t_set, t_run);
      get_total += milliseconds(t_run, t2);
      post_total += milliseconds(t2, t3);
      total_samples.push_back(milliseconds(t0, t3));
    }
  }
  rknn_destroy(ctx);
  double total = pre_total + set_total + run_total + get_total + post_total;
  std::sort(total_samples.begin(), total_samples.end());
  double p95 = total_samples[std::min(total_samples.size() - 1,
                                      size_t(std::ceil(total_samples.size() * 0.95) - 1))];
  std::cout << "repeat=" << repeat << " confidence=" << confidence << " core=" << core
            << " output=" << (int8_output ? "i8" : "float") << " cv_threads=" << cv_threads
            << " preprocess_ms=" << pre_total / repeat
            << " input_set_ms=" << set_total / repeat
            << " npu_run_ms=" << run_total / repeat
            << " output_get_ms=" << get_total / repeat
            << " postprocess_ms=" << post_total / repeat
            << " total_ms=" << total / repeat
            << " total_p95_ms=" << p95
            << " sequential_fps=" << 1000.0 * repeat / total << "\n";
  std::cout << "detections=" << final_detections.size() << "\n";
  for (size_t i = 0; i < std::min(final_detections.size(), size_t(20)); ++i) {
    const auto& d = final_detections[i];
    std::cout << (g_classes == 1 ? "Crack" : kNames[d.cls]) << " score=" << d.score << " box="
              << d.x1 << "," << d.y1 << "," << d.x2 << "," << d.y2 << "\n";
  }
}
#endif
