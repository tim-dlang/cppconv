# Usage

The tool cppconv, built with dub, analyzes C and C++ code and tries to
produce equivalent D code.

The repository also contains the tool build.d, which downloads the
source code for existing projects and runs cppconv to convert them to D.
Currently it has a small sample project and projects for generating
bindings to Qt.

## Preprocessor

Normal C and C++ code is first processed by the preprocessor, which
can for example replace macros and remove code with special directives
like `#if`. D does not use a preprocessor, so the converted code
needs to use different features. A built-in preprocessor is used in
cppconv, which works a bit different from a normal preprocessor.
Macros don't need to have single value, but can have different values
or be undefined depending on conditions. Later all possible values
for macros are processed when using the macros in code or for
conditional compilation. The resulting D code can then use `version`
or `static if` statements for conditional compilation. Some macros
can be translated to enums or mixins.

The built-in preprocessor has some custom directives, which are
documented below. They are normally used in a special header, which
is processed before the normal code. One example is the file
projects/qt5/prefixinclude.h, which sets some macros for generating
the bindings for Qt.

### `#addincludepath "path"`
Add another include path. It can be used inside `#if` blocks,
so the include path is e.g. only used on one platform.

### `#unknown NAME`
Mark macro NAME as defined, but with an unknown value.

### `#lockdefine NAME`
Ignore any further directives for macro NAME. This is used when a
library defines a macro, but a different define should be used when
converting the source code.

### `#regex_undef "REGEX"`
Marks all macros matching the regular expression as undefined.

### `#alias NAME EXPR`
Declare a macro NAME, which is defined if EXPR is true. This is equivalent
to this sequence of directives:
```
#undef NAME
#if EXPR
#define NAME EXPR
#endif
```
Additionally the converter remembers the connection between NAME and EXPR.
The converted code can later use NAME again instead of EXPR.
One use case is to declare mutually exclusive macros, e.g.:
```
#unknown OS
#alias LINUX OS == 1
#alias WIN   OS == 2
#alias MACOS OS == 3
```
Normally the converter allows all combinations of the platform macros,
but in practice at most one of them can be defined. Using the single
macro OS internally tells the converter, which combinations are
possible.

## Output

Argument --output-dir of cppconv selects the directory, where the
output D files are stored. The existing projects built by build.d
use a directory called conv inside the project directory, like
projects/qt5/conv.

A configuration file selected with argument --output-config controls
details about the generated files. One example is
projects/qt5/output-config.json, which also includes other settings from
file projects/common/output-config.json. Settings from the included
file can be overridden in the including file. For settings, which are
a list of patterns or values, the lists are combined. Different settings
in this file are documented below. 

### Formatting

The conversion tries to preserve formatting, whitespace and comments
from the source files. Sometimes additional indentation has to be added.
This can be configured with the setting `indent`.

### Special Modules

Two special modules are used by the generated code. The modules are not
generated, but have to be supplied manually. A config module contains
declarations used for conditional compilation. The module name is
configured with setting `configModule`. There is also a helper module
with different declarations used in the generated code. Setting
`helperModule` contains the module name.

### Declaration Pattern

Some settings in the output configuration apply to C++ declarations.
These settings can use patterns for different properties of the
declarations to apply settings to the selected declarations. 
A list of patterns is used, and the last match is used for every
declaration. Some settings directly use a list of patterns, while others
use a list of objects with a pattern and values for the setting.

The following properties of declarations can be used:
* filename: A regular expression for the filename.
* name: A regular expression for the name of the declaration.
* lines: A range of line numbers of the declaration.
* isTemplate: Set to `true`, so only templates are selected, or to
    `false`, so only non-templates are selected.
* inMacro: Select if the declaration should or should not be declared
    in a macro.

The regular expressions can contain named captures, which can be used
in some settings. Currently, the capture name needs to be a single letter,
and it will be used with a percent sign.

### Declaration Selection

Not all declarations from the source files should be in the output.
By default, only declarations from the main translation units and
dependencies are used. The setting `includeDeclFilenamePatterns`
can configure other files, where all declarations should be included.
It contains a list of regular expressions for filenames.

It is possible to exclude declarations from the output with setting
`blacklist`. It contains a list of declaration patterns. The selected
declarations are not translated to D code, but may still be included
as comments.

### Module Names

Setting `modulePatterns` controls how the declarations are distributed
into output modules. It contains a list of objects. Every object
contains a declaration pattern in subobject `match`. For every
declaration the last match is selected. Setting `moduleName` will
then select the module name for the declaration. It can also contain
named captures from the declaration pattern. The filename inside
the output directory is based on the module name. Optionally it can
be in another subdirectory with the setting `extraPrefix`. This can
be used to generate different versions of the same module for different
platforms.

### `class` vs `struct`

Both C++ and D can declare new types as `class` or `struct`, but they
mean different things. In C++ it changes the default visibility, but
in D it controls if a virtual table is used and inheritance is allowed.
The converter automatically detects virtual methods and chooses `class`
or `struct` based on this. Setting `typeKinds` allows overriding
this choice.

# build.d

The tool cppconv can be used alone, but this repository also contains
build.d, which runs it for some existing projects. These projects
are subdirectories in directory projects. Some are only used as
dependencies for other projects.

Running build.d will download the source code for all required projects
and extract it in subdirectory orig of the project directory. 
It is only created, when it does not yet exist, so it has to be manually
deleted if changes have been made.

For projects with main source files, build.d will then call cppconv with
the correct parameters, so the D output files are created. They will
be placed in subdirectory conv of the project.

The sample project can be used with this command:
```
dmd -run build.d sample
```
It does not download any source code. Instead, the code from
projects/sample/src/ is converted and placed in projects/sample/conv/.

The bindings for qt5 can be generated with:
```
dmd -run build.d qt5
```
The header files for Qt are downloaded and placed in projects/qt5/orig/.
Headers for dependencies, like libc, are also downloaded and placed in
other orig-directories for the projects. The bindings for Qt are then
generated in projects/qt5/conv/. The same can be done with qt6 instead
of qt5.

The program build.d and the converter have only been tested on Linux.
Program build.d calls some external programs like wget, tar, 7z and make
to download, extract and prepare the source for the projects.
