# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@rules_python//python:defs.bzl", "py_library")
load("//third_party/python:requirements.bzl", "requirement")

package(default_visibility = ["//visibility:public"])

py_library(
    name = "parse_helpers",
    srcs = ["parse_helpers.py"],
    deps = [requirement("pyyaml")],
)
