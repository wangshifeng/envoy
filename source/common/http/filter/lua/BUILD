licenses(["notice"])  # Apache 2

load(
    "//bazel:envoy_build_system.bzl",
    "envoy_cc_library",
    "envoy_package",
)

envoy_package()

envoy_cc_library(
    name = "lua_filter_lib",
    srcs = ["lua_filter.cc"],
    hdrs = ["lua_filter.h"],
    external_deps = [
        #"luajit",
    ],
    deps = [
        "//include/envoy/http:filter_interface",
        "//source/common/lua:lua_lib",
        #"//source/common/common:assert_lib",
    ],
)
