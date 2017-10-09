load("@protobuf_bzl//:protobuf.bzl", "cc_proto_library")

def envoy_package():
    native.package(default_visibility = ["//visibility:public"])

# Compute the final copts based on various options.
def envoy_copts(repository, test = False):
    return [
        "-Wall",
        "-Wextra",
        "-Werror",
        "-Wnon-virtual-dtor",
        "-Woverloaded-virtual",
        "-Wold-style-cast",
        "-std=c++0x",
    ] + select({
        # Bazel adds an implicit -DNDEBUG for opt.
        repository + "//bazel:opt_build": [] if test else ["-ggdb3"],
        repository + "//bazel:fastbuild_build": [],
        repository + "//bazel:dbg_build": ["-ggdb3"],
    }) + select({
        repository + "//bazel:disable_tcmalloc": [],
        "//conditions:default": ["-DTCMALLOC"],
    }) + select({
        repository + "//bazel:disable_signal_trace": [],
        "//conditions:default": ["-DENVOY_HANDLE_SIGNALS"],
    }) + select({
        # TCLAP command line parser needs this to support int64_t/uint64_t
        "@bazel_tools//tools/osx:darwin": ["-DHAVE_LONG_LONG"],
        "//conditions:default": [],
    }) + envoy_select_hot_restart(["-DENVOY_HOT_RESTART"], repository)

# Compute the final linkopts based on various options.
def envoy_linkopts():
    return select({
        # OSX provides system and stdc++ libraries dynamically, so they can't be linked statically.
        # Further, the system library transitively links common libraries (e.g., pthread).
        # TODO(zuercher): build id could be supported via "-sectcreate __TEXT __build_id <file>"
        # The file could should contain the current git SHA (or enough placeholder data to allow
        # it to be rewritten by tools/git_sha_rewriter.py).
        "@bazel_tools//tools/osx:darwin": [],
        "//conditions:default": [
            "-pthread",
            "-lrt",
            # Force MD5 hash in build. This is part of the workaround for
            # https://github.com/bazelbuild/bazel/issues/2805. Bazel actually
            # does this by itself prior to
            # https://github.com/bazelbuild/bazel/commit/724706ba4836c3366fc85b40ed50ccf92f4c3882.
            # Ironically, forcing it here so that in future releases we will
            # have the same behavior. When everyone is using an updated version
            # of Bazel, we can use linkopts to set the git SHA1 directly in the
            # --build-id and avoid doing the following.
            '-Wl,--build-id=md5',
            '-Wl,--hash-style=gnu',
            "-static-libstdc++",
            "-static-libgcc",
        ],
    })

# Compute the test linkopts based on various options.
def envoy_test_linkopts():
    return select({
        "@bazel_tools//tools/osx:darwin": [],

        # TODO(mattklein123): It's not great that we universally link against the following libs.
        # In particular, -latomic and -lrt are not needed on all platforms. Make this more granular.
        "//conditions:default": ["-pthread", "-latomic", "-lrt"],
    })

# References to Envoy external dependencies should be wrapped with this function.
def envoy_external_dep_path(dep):
    return "//external:%s" % dep

# Dependencies on tcmalloc_and_profiler should be wrapped with this function.
def tcmalloc_external_dep(repository):
    return select({
        repository + "//bazel:disable_tcmalloc": None,
        "//conditions:default": envoy_external_dep_path("tcmalloc_and_profiler"),
    })

# As above, but wrapped in list form for adding to dep lists. This smell seems needed as
# SelectorValue values have to match the attribute type. See
# https://github.com/bazelbuild/bazel/issues/2273.
def tcmalloc_external_deps(repository):
    return select({
        repository + "//bazel:disable_tcmalloc": [],
        "//conditions:default": [envoy_external_dep_path("tcmalloc_and_profiler")],
    })

# Transform the package path (e.g. include/envoy/common) into a path for
# exporting the package headers at (e.g. envoy/common). Source files can then
# include using this path scheme (e.g. #include "envoy/common/time.h").
def envoy_include_prefix(path):
    if path.startswith('source/') or path.startswith('include/'):
        return '/'.join(path.split('/')[1:])
    return None

# Envoy C++ library targets that need no transformations or additional dependencies before being
# passed to cc_library should be specified with this function. Note: this exists to ensure that
# all envoy targets pass through an envoy-declared skylark function where they can be modified
# before being passed to a native bazel function.
def envoy_basic_cc_library(name, **kargs):
    native.cc_library(name = name, **kargs)

# Envoy C++ library targets should be specified with this function.
def envoy_cc_library(name,
                     srcs = [],
                     hdrs = [],
                     copts = [],
                     visibility = None,
                     external_deps = [],
                     tcmalloc_dep = None,
                     repository = "",
                     linkstamp = None,
                     tags = [],
                     deps = [],
                     strip_include_prefix = None):
    if tcmalloc_dep:
        deps += tcmalloc_external_deps(repository)
    native.cc_library(
        name = name,
        srcs = srcs,
        hdrs = hdrs,
        copts = envoy_copts(repository) + copts,
        visibility = visibility,
        tags = tags,
        deps = deps + [envoy_external_dep_path(dep) for dep in external_deps] + [
            repository + "//include/envoy/common:base_includes",
            envoy_external_dep_path('spdlog'),
            envoy_external_dep_path('fmtlib'),
        ],
        include_prefix = envoy_include_prefix(PACKAGE_NAME),
        alwayslink = 1,
        linkstatic = 1,
        linkstamp = linkstamp,
        strip_include_prefix = strip_include_prefix,
   )

def _git_stamped_genrule(repository, name):
    # To workaround https://github.com/bazelbuild/bazel/issues/2805, we
    # do binary rewriting to replace the linker produced MD5 hash with the
    # version_generated.cc git SHA1 hash (truncated).
    rewriter = repository + "//tools:git_sha_rewriter.py"
    native.genrule(
        name = name + "_stamped",
        srcs = [name],
        outs = [name + ".stamped"],
        cmd = "cp $(location " + name + ") $@ && " +
              "chmod u+w $@ && " +
              "$(location " + rewriter + ") $@",
        tools = [rewriter],
    )

# Envoy C++ binary targets should be specified with this function.
def envoy_cc_binary(name,
                    srcs = [],
                    data = [],
                    testonly = 0,
                    visibility = None,
                    repository = "",
                    stamped = False,
                    deps = []):
    # Implicit .stamped targets to obtain builds with the (truncated) git SHA1.
    if stamped:
        _git_stamped_genrule(repository, name)
        _git_stamped_genrule(repository, name + ".stripped")
    native.cc_binary(
        name = name,
        srcs = srcs,
        data = data,
        copts = envoy_copts(repository),
        linkopts = envoy_linkopts(),
        testonly = testonly,
        linkstatic = 1,
        visibility = visibility,
        malloc = tcmalloc_external_dep(repository),
        # See above comment on MD5 hash, this is another "force MD5 stamps" to make sure our
        # rewriting is robust.
        stamp = 1,
        deps = deps,
    )

# Envoy C++ test targets should be specified with this function.
def envoy_cc_test(name,
                  srcs = [],
                  data = [],
                  # List of pairs (Bazel shell script target, shell script args)
                  repository = "",
                  external_deps = [],
                  deps = [],
                  tags = [],
                  args = [],
                  coverage = True,
                  local = False,
                  linkopts = []):
    test_lib_tags = []
    if coverage:
      test_lib_tags.append("coverage_test_lib")
    envoy_cc_test_library(
        name = name + "_lib",
        srcs = srcs,
        data = data,
        external_deps = external_deps,
        deps = deps,
        repository = repository,
        tags = test_lib_tags,
    )
    native.cc_test(
        name = name,
        copts = envoy_copts(repository, test = True),
        linkopts = linkopts + envoy_test_linkopts(),
        linkstatic = 1,
        malloc = tcmalloc_external_dep(repository),
        deps = [
            ":" + name + "_lib",
            repository + "//test:main"
        ],
        # from https://github.com/google/googletest/blob/6e1970e2376c14bf658eb88f655a054030353f9f/googlemock/src/gmock.cc#L51
        # 2 - by default, mocks act as StrictMocks.
        args = args + ["--gmock_default_mock_behavior=2"],
        tags = tags + ["coverage_test"],
        local = local,
    )

# Envoy C++ test related libraries (that want gtest, gmock) should be specified
# with this function.
def envoy_cc_test_library(name,
                          srcs = [],
                          hdrs = [],
                          data = [],
                          external_deps = [],
                          deps = [],
                          repository = "",
                          tags = []):
    native.cc_library(
        name = name,
        srcs = srcs,
        hdrs = hdrs,
        data = data,
        copts = envoy_copts(repository, test = True),
        testonly = 1,
        deps = deps + [envoy_external_dep_path(dep) for dep in external_deps] + [
            envoy_external_dep_path('googletest'),
            repository + "//test/test_common:printers_includes",
        ],
        tags = tags,
        alwayslink = 1,
        linkstatic = 1,
    )

# Envoy Python test binaries should be specified with this function.
def envoy_py_test_binary(name,
                         external_deps = [],
                         deps = [],
                         **kargs):
    native.py_binary(
        name = name,
        deps = deps + [envoy_external_dep_path(dep) for dep in external_deps],
        **kargs
    )

# Envoy C++ mock targets should be specified with this function.
def envoy_cc_mock(name, **kargs):
    envoy_cc_test_library(name = name, **kargs)

# Envoy shell tests that need to be included in coverage run should be specified with this function.
def envoy_sh_test(name,
                  srcs = [],
                  data = [],
                  **kargs):
  test_runner_cc = name + "_test_runner.cc"
  native.genrule(
      name = name + "_gen_test_runner",
      srcs = srcs,
      outs = [test_runner_cc],
      cmd = "$(location //bazel:gen_sh_test_runner.sh) $(SRCS) >> $@",
      tools = ["//bazel:gen_sh_test_runner.sh"],
  )
  envoy_cc_test_library(
      name = name + "_lib",
      srcs = [test_runner_cc],
      data = srcs + data,
      tags = ["coverage_test_lib"],
      deps = ["//test/test_common:environment_lib"],
  )
  native.sh_test(
      name = name,
      srcs = ["//bazel:sh_test_wrapper.sh"],
      data = srcs + data,
      args = srcs,
      **kargs
  )

def _proto_header(proto_path):
  if proto_path.endswith(".proto"):
      return proto_path[:-5] + "pb.h"
  return None

# Envoy proto targets should be specified with this function.
def envoy_proto_library(name, srcs = [], deps = [], external_deps = []):
    internal_name = name + "_internal"
    cc_proto_library(
        name = internal_name,
        srcs = srcs,
        default_runtime = "//external:protobuf",
        protoc = "//external:protoc",
        deps = deps + [envoy_external_dep_path(dep) for dep in external_deps],
        linkstatic = 1,
    )
    # We can't use include_prefix directly in cc_proto_library, since it
    # confuses protoc. Instead, we create a shim cc_library that performs the
    # remap of .pb.h location to Envoy canonical header paths.
    native.cc_library(
        name = name,
        hdrs = [_proto_header(s) for s in srcs if _proto_header(s)],
        include_prefix = envoy_include_prefix(PACKAGE_NAME),
        deps = [internal_name],
        linkstatic = 1,
    )

# Envoy proto descriptor targets should be specified with this function.
# This is used for testing only.
def envoy_proto_descriptor(name, out, srcs = [], external_deps = []):
    input_files = ["$(location " + src + ")" for src in srcs]
    include_paths = [".", PACKAGE_NAME]

    if "http_api_protos" in external_deps:
        srcs.append("@googleapis//:http_api_protos_src")
        include_paths.append("external/googleapis")

    if "well_known_protos" in external_deps:
        srcs.append("@protobuf_bzl//:well_known_protos")
        include_paths.append("external/protobuf_bzl/src")

    options = ["--include_imports"]
    options.extend(["-I" + include_path for include_path in include_paths])
    options.append("--descriptor_set_out=$@")

    cmd = "$(location //external:protoc) " + " ".join(options + input_files)
    native.genrule(
        name = name,
        srcs = srcs,
        outs = [out],
        cmd = cmd,
        tools = ["//external:protoc"],
    )

# Selects the given values if hot restart is enabled in the current build.
def envoy_select_hot_restart(xs, repository = ""):
    return select({
        repository + "//bazel:disable_hot_restart": [],
        "@bazel_tools//tools/osx:darwin": [],
        "//conditions:default": xs,
    })
