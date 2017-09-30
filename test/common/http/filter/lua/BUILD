licenses(["notice"])  # Apache 2

load(
    "//bazel:envoy_build_system.bzl",
    "envoy_cc_test",
    "envoy_package",
)

envoy_package()

envoy_cc_test(
    name = "lua_filter_test",
    srcs = ["lua_filter_test.cc"],
    linkopts = ["-ldl"],
    deps = [
        "//source/common/http/filter/lua:lua_filter_lib",
        "//test/test_common:utility_lib",
    ],
)
