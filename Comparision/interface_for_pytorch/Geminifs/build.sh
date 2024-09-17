#!/bin/bash -x
cd ..
rm -rf build/ cmake-build/ dist/ Geminifs.egg-info/
pip uninstall Geminifs
python setup.py install
