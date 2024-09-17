#!/bin/bash -x

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 {1|0}"
    exit 1
fi
case $1 in
    1)
        echo "Installing..."
        python interface_for_pytorch/setup.py install
        ;;
    0)
        echo "Uninstalling..."
        python interface_for_pytorch/setup.py uninstall
        rm -rf interface_for_pytorch/build/ interface_for_pytorch/cmake-build/ interface_for_pytorch/dist/ interface_for_pytorch/Geminifs.egg-info/
        ;;
    *)
        echo "Invalid argument. Use 1 for install or 0 for uninstall."
        exit 1
        ;;
esac
