#!/bin/sh
set -eu

alr build
alr --chdir tests build
alr --chdir tests exec -- ./bin/pictlib_tests
