# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@rules_python//python:defs.bzl", "py_binary", "py_library", "py_test")
load("//third_party/python:requirements.bzl", "requirement")

package(default_visibility = ["//visibility:public"])

py_library(
    name = "mem",
    srcs = ["mem.py"],
    deps = [
        "//util/design:secded_gen",
        requirement("pyelftools"),
    ],
)

py_binary(
    name = "gen_vivado_mem_image",
    srcs = ["gen_vivado_mem_image.py"],
    deps = [":mem"],
)

py_test(
    name = "gen_vivado_mem_image_test",
    srcs = ["gen_vivado_mem_image_test.py"],
    deps = [":gen_vivado_mem_image"],
)

py_binary(
    name = "scramble_image",
    srcs = ["scramble_image.py"],
    deps = [
        ":mem",
        "//util/design:prince",
        "//util/design:secded_gen",
        requirement("hjson"),
        requirement("pycryptodome"),
    ],
)
