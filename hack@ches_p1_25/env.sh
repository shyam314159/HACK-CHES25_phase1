#!/bin/bash
# Environment setup for Hack@CHES'25 OpenTitan competition

# Set up OpenTitan environment variables
export REPO_TOP=$(pwd)
export PATH=$PATH:$REPO_TOP/util

# Bazel setup
export BAZEL_VERSION=6.2.1

# Python setup
export PYTHONPATH=$REPO_TOP:$PYTHONPATH

echo "Environment set up for OpenTitan Hack@CHES'25"
echo "REPO_TOP: $REPO_TOP"
echo "Bazel version required: $BAZEL_VERSION"