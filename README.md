# cppconv

Cppconv is a tool for converting C and C++ code to D. It was used to
generate the bindings for Qt in [DQt](https://github.com/tim-dlang/dqt).
Currently, the converter is still a work in progress. It contains
some special cases for Qt and manual changes to the resulting D files
are necessary. Depending on the use case, one of the [alternatives](#Alternatives)
could be better.

See [docs/cppconv.md](docs/cppconv.md) for some documentation.
The program cppconv can be built with dub and used directly, but for
existing projects there is also build.d, which downloads the source
code for the projects and runs cppconv with the correct parameters.

The converter uses a parser for C/C++ generated with
[DParserGen](https://github.com/tim-dlang/dparsergen).
It tries to convert conditional compilation with the preprocessor into
equivalent D code using `version` or `static if`. Unfortunately
the number of combinations can get very large depending on settings,
so the converter can easily run out of memory.

## License

Boost Software License, Version 1.0. See file [LICENSE_1_0.txt](LICENSE_1_0.txt).

## Alternatives

There are different alternatives to use C/C++ headers from D or convert
them to D code:

* https://dlang.org/spec/importc.html
* https://github.com/jacob-carlborg/dstep
* https://github.com/Syniurge/Calypso
* https://github.com/atilaneves/dpp
* https://github.com/Superbelko/ohmygentool
* https://github.com/dkorpel/ctod
