# CMake Helpers

Collection of utility scripts and functions to help with CMake-based software builds at Tiqi.

## TiqiCommon.cmake

CMake module providing utility functions to assist in CMake-base workflows for Tiqi projects.
See embedded module documentation for details about the usage.

## Documentation

See [Github Pages](https://tiqi-group.github.io/CMake-Helpers).

### Building the Documentation

Sphinx builds the documentation.
The [sphinxcontrib-moderncmakedomain](https://pypi.org/project/sphinxcontrib-moderncmakedomain/) package is needed.
It can be installed using pip:
```sh
pip install sphinxcontrib-moderncmakedomain
```
After that you can create the html documentation using
```sh
sphinx-build -M html Help/ _build
```

