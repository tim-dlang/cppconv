import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.path;
import std.process;
import std.regex;
import std.stdio;
import std.string;

string escapeShellCommandMultiline(const string[] args)
{
    string[] escaped;
    escaped.length = args.length;
    size_t fullLength;
    foreach (i; 0 .. args.length)
    {
        escaped[i] = escapeShellCommand(args[i .. i + 1]);
        fullLength += escaped[i].length;
        if (i)
            fullLength++;
    }
    string result;
    if (fullLength <= 72)
    {
        foreach (i; 0 .. args.length)
        {
            if (i)
                result ~= " ";
            result ~= escaped[i];
        }
    }
    else
    {
        size_t lineStart;
        foreach (i; 0 .. args.length)
        {
            if (i)
                result ~= " ";
            result ~= escaped[i];
            if (i + 1 < args.length
                && (args[i + 1].startsWith("-")
                    || result.length - lineStart + escaped[i + 1].length > 72))
            {
                result ~= " \\\n";
                lineStart = result.length;
                result ~= "   ";
            }
        }
    }
    return result;
}

void runCommand(string[] args, bool verbose, string workDir = null)
{
    writeln("Running: ", escapeShellCommandMultiline(args));

    Redirect redirect = Redirect.stdin;
    if (!verbose)
        redirect |= Redirect.stdout | Redirect.stderrToStdout;
    auto pipes = pipeProcess(args, redirect, null, Config.none, workDir);
    pipes.stdin.close();
    Appender!string app;
    if (!verbose)
    {
        foreach (ubyte[] chunk; pipes.stdout.byChunk(4096))
            app.put(chunk);
    }

    auto status = pipes.pid.wait();

    if (status)
    {
        if (!verbose)
            writeln(app.data);
        throw new Exception(text("Command ", args[0], " failed with status ", status));
    }
}

void rmdirRecurseIfExists(scope const(char)[] pathname)
{
    if (exists(pathname))
    {
        rmdirRecurse(pathname);
    }
}

void copyFiles(string sourceDir, string pattern, string targetDir)
{
    foreach (entry; dirEntries(sourceDir, pattern, SpanMode.depth))
    {
        if (entry.isDir)
            continue;
        string targetName = buildPath(targetDir, relativePath(absolutePath(entry.name), absolutePath(sourceDir)));
        mkdirRecurse(dirName(targetName));
        copy(entry.name, targetName);
    }
}

void copyFilesNoExt(string sourceDir, string targetDir)
{
    foreach (entry; dirEntries(sourceDir, SpanMode.depth))
    {
        if (entry.isDir)
            continue;
        if (baseName(entry.name).canFind("."))
            continue;
        string targetName = buildPath(targetDir, relativePath(absolutePath(entry.name), absolutePath(sourceDir)));
        mkdirRecurse(dirName(targetName));
        copy(entry.name, targetName);
    }
}

void downloadFile(string url, string filename, bool verbose)
{
    if (!exists(filename))
    {
        runCommand(["wget", url, "-O", filename ~ ".part"], verbose);
        rename(filename ~ ".part", filename);
    }
}

void createDocCommentsFile(string projectDir, string baseUrl)
{
    auto titleRegex = regex(r"<title>([a-zA-Z0-9_]*) Class \| [^<>]*</title>");
    auto subTitleRegex = regex("<span class=\"small-subtitle\">class <a[^<>]*>([a-zA-Z0-9_]*)</a>::([a-zA-Z0-9_]*)</span>");
    string[2][] docComments;
    foreach (entry; dirEntries(buildPath(projectDir, "Docs"), "*.html", SpanMode.depth))
    {
        if (entry.isDir)
            continue;

        auto content = readText(entry.name);
        auto capture = matchFirst(content, titleRegex);
        if (capture.empty)
            continue;
        auto className = capture[1];

        capture = matchFirst(content, subTitleRegex);
        if (!capture.empty)
        {
            enforce(capture[2] == className);
            className = capture[1] ~ "::" ~ capture[2];
        }

        docComments ~= [className, entry.name.baseName];
    }
    docComments.sort();
    File docCommentsFile = File(buildPath(projectDir, "doccomments.json"), "w");
    docCommentsFile.writeln("{");
    docCommentsFile.writeln("    \"docComments\": {");
    foreach (i, docComment; docComments)
    {
        docCommentsFile.writeln("        \"", docComment[0], "\": \"Binding for C++ class [", docComment[0], "](", baseUrl, docComment[1], ").\"", (i + 1 < docComments.length) ? "," : "");
    }
    docCommentsFile.writeln("    }");
    docCommentsFile.writeln("}");
}

abstract class Project
{
    immutable string name;
    immutable string projectDir;
    string[] converterArgs;
    string[] sourceFiles;
    string[] tmpDirs;
    string[] dependencies;
    bool selected;

    string delegate() getMemberDescription;

    this(this T)(string name)
    {
        this.name = name;
        projectDir = "projects/" ~ name;

        getMemberDescription = () {
            string r;
            T this_ = cast(T) this;
            static foreach (member; this.tupleof)
            {{
                enum memberName = __traits(identifier, member);
                if (!is(typeof(member) == delegate))
                    r ~= text(memberName, ": ", member, "\n");
            }}
            static foreach (member; T.init.tupleof)
            {{
                enum memberName = __traits(identifier, member);
                r ~= text(memberName, ": ", __traits(getMember, this_, memberName), "\n");
            }}
            return r;
        };
    }

    void download() {}
    void prepare() {}
}

int main(string[] args)
{
    Project[] projects;

    bool verbose;
    string[] explicitProjects;
    string[] extraConverterArgs;
    
    for (size_t i = 1; i < args.length; i++)
    {
        string arg = args[i];
        if (arg.startsWith("-"))
        {
            if (arg == "-v")
                verbose = true;
            else if (arg == "--warn-unused")
                extraConverterArgs ~= arg;
            else
            {
                stderr.writeln("unknown argument ", arg);
                return 1;
            }
        }
        else
        {
            explicitProjects ~= arg;
        }
    }

    if (explicitProjects.length == 0)
    {
        writeln("No projects selected");
        return 0;
    }

    projects ~= new class Project
    {
        string archiveBase, archive;
        this()
        {
            super("glibc");
            archiveBase = "glibc-2.32";
            archive = archiveBase ~ ".tar.xz";
            tmpDirs ~= archiveBase;
            tmpDirs ~= "tmp-build";
        }

        override void download()
        {
            downloadFile("https://ftp.gnu.org/gnu/glibc/" ~ archive, projectDir ~ "/" ~ archive, verbose);
        }

        override void prepare()
        {
            runCommand(["tar", "xf", archive], verbose, projectDir);
            mkdirRecurse(buildPath(projectDir, "tmp-build"));

            runCommand([absolutePath(buildPath(projectDir, archiveBase, "configure")), "--prefix=" ~ absolutePath(buildPath(projectDir, "tmp-orig"))], verbose, buildPath(projectDir, "tmp-build"));
            runCommand(["make", "install-headers"], verbose, buildPath(projectDir, "tmp-build"));
        }
    };
    projects ~= new class Project
    {
        string archiveBase, archive;
        this()
        {
            super("linuxapi");
            archiveBase = "linux-5.8.1";
            archive = archiveBase ~ ".tar.xz";
            tmpDirs ~= archiveBase;
        }

        override void download()
        {
            downloadFile("https://mirrors.edge.kernel.org/pub/linux/kernel/v5.x/" ~ archive, projectDir ~ "/" ~ archive, verbose);
        }

        override void prepare()
        {
            runCommand(["tar", "xf", archive], verbose, projectDir);

            runCommand(["make", "INSTALL_HDR_PATH=" ~ absolutePath(buildPath(projectDir, "tmp-orig")), "headers_install"], verbose, buildPath(projectDir, archiveBase));
        }
    };
    projects ~= new class Project
    {
        string archiveBase, archive;
        this()
        {
            super("gcc-rt");
            archiveBase = "gcc-10.2.0";
            archive = archiveBase ~ ".tar.xz";
            tmpDirs ~= archiveBase;
        }

        override void download()
        {
            downloadFile("https://ftp.gwdg.de/pub/misc/gcc/releases/" ~ archiveBase ~ "/" ~ archive, projectDir ~ "/" ~ archive, verbose);
        }

        override void prepare()
        {
            runCommand(["tar", "xf", archive], verbose, projectDir);

            mkdirRecurse(buildPath(projectDir, "tmp-orig", "include"));
            mkdirRecurse(buildPath(projectDir, "tmp-orig", "include-fixed"));

            copyFiles(buildPath(projectDir, archiveBase, "gcc/config/i386"), "*.h", buildPath(projectDir, "tmp-orig", "include"));
            copyFiles(buildPath(projectDir, archiveBase, "gcc/ginclude"), "*.h", buildPath(projectDir, "tmp-orig", "include"));
            copy(buildPath(projectDir, archiveBase, "gcc/ginclude/stdint-wrap.h"), buildPath(projectDir, "tmp-orig", "include", "stdint.h"));

            copy(buildPath(projectDir, archiveBase, "gcc/glimits.h"), buildPath(projectDir, "tmp-orig", "include-fixed", "limits.h"));
            copy(buildPath(projectDir, archiveBase, "gcc/gsyslimits.h"), buildPath(projectDir, "tmp-orig", "include-fixed", "syslimits.h"));

            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/include/std"), "*", buildPath(projectDir, "tmp-orig", "include-cxx"));
            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/include/c"), "*", buildPath(projectDir, "tmp-orig", "include-cxx"));
            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/include/c_global"), "*", buildPath(projectDir, "tmp-orig", "include-cxx"));
            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/include/backward"), "*", buildPath(projectDir, "tmp-orig", "include-cxx/backward"));
            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/include/bits"), "*", buildPath(projectDir, "tmp-orig", "include-cxx/bits"));
            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/include/debug"), "*", buildPath(projectDir, "tmp-orig", "include-cxx/debug"));
            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/include/experimental"), "*", buildPath(projectDir, "tmp-orig", "include-cxx/experimental"));
            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/include/ext"), "*", buildPath(projectDir, "tmp-orig", "include-cxx/ext"));
            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/include/parallel"), "*", buildPath(projectDir, "tmp-orig", "include-cxx/parallel"));
            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/include/pstl"), "*", buildPath(projectDir, "tmp-orig", "include-cxx/pstl"));
            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/include/tr1"), "*", buildPath(projectDir, "tmp-orig", "include-cxx/tr1"));

            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/libsupc++"), "*.h", buildPath(projectDir, "tmp-orig", "include-cxx/bits"));
            copyFilesNoExt(buildPath(projectDir, archiveBase, "libstdc++-v3/libsupc++"), buildPath(projectDir, "tmp-orig", "include-cxx"));

            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/config/os/generic"), "*", buildPath(projectDir, "tmp-orig", "include-cxx/platform-generic/bits"));
            copyFiles(buildPath(projectDir, archiveBase, "libstdc++-v3/config/cpu/generic"), "*", buildPath(projectDir, "tmp-orig", "include-cxx/platform-generic/bits"));
            copy(buildPath(projectDir, archiveBase, "libstdc++-v3/config/allocator/new_allocator_base.h"), buildPath(projectDir, "tmp-orig", "include-cxx/platform-generic/bits/c++allocator.h"));
            copy(buildPath(projectDir, archiveBase, "libstdc++-v3/config/locale/generic/c_locale.h"), buildPath(projectDir, "tmp-orig", "include-cxx/platform-generic/bits/c++locale.h"));
            copy(buildPath(projectDir, archiveBase, "libgcc/gthr.h"), buildPath(projectDir, "tmp-orig", "include-cxx/platform-generic/bits/gthr.h"));
            copy(buildPath(projectDir, archiveBase, "libgcc/gthr-posix.h"), buildPath(projectDir, "tmp-orig", "include-cxx/platform-generic/bits/gthr-default.h"));

            string cxxConfig = readText(buildPath(projectDir, archiveBase, "libstdc++-v3/include/bits/c++config"));

            // Analog to sed command in projects/gcc-rt/gcc-*/libstdc++-v3/Makefile.am
            cxxConfig = cxxConfig
                .replace("define __GLIBCXX__", "define __GLIBCXX__ 20210427")
                .replace("define _GLIBCXX_RELEASE", "define _GLIBCXX_RELEASE 11")
                .replace("define _GLIBCXX_INLINE_VERSION", "define _GLIBCXX_INLINE_VERSION 0")
                .replace("define _GLIBCXX_HAVE_ATTRIBUTE_VISIBILITY", "define _GLIBCXX_HAVE_ATTRIBUTE_VISIBILITY 1")
                .replace("#define _GLIBCXX_EXTERN_TEMPLATE", "#define _GLIBCXX_EXTERN_TEMPLATE 1")
                .replace("define _GLIBCXX_USE_DUAL_ABI", "define _GLIBCXX_USE_DUAL_ABI 1")
                .replace("define _GLIBCXX_USE_CXX11_ABI", "define _GLIBCXX_USE_CXX11_ABI 1")
                .replace("define _GLIBCXX_USE_ALLOCATOR_NEW", "define _GLIBCXX_USE_ALLOCATOR_NEW 1")
                .replace("define _GLIBCXX_USE_FLOAT128", "define _GLIBCXX_USE_FLOAT128 1");

            foreach (line; File(buildPath(projectDir, archiveBase, "libstdc++-v3/config.h.in")).byLine)
            {
                line = line
                        .replace("HAVE_", "_GLIBCXX_HAVE_")
                        .replace("PACKAGE", "_GLIBCXX_PACKAGE")
                        .replace("WORDS_", "_GLIBCXX_WORDS_")
                        .replace("_DARWIN_USE_64_BIT_INODE", "_GLIBCXX_DARWIN_USE_64_BIT_INODE")
                        .replace("_FILE_OFFSET_BITS", "_GLIBCXX_FILE_OFFSET_BITS")
                        .replace("_LARGE_FILES", "_GLIBCXX_LARGE_FILES")
                        .replace("ICONV_CONST", "_GLIBCXX_ICONV_CONST");

                if (line.startsWith("#undef _GLIBCXX_HOSTED"))
                    cxxConfig ~= "#define _GLIBCXX_HOSTED 1\n";
                else if (line.startsWith("#undef _GTHREAD_USE_MUTEX_TIMEDLOCK"))
                    cxxConfig ~= "#define _GTHREAD_USE_MUTEX_TIMEDLOCK 1\n";
                else if (line.startsWith("#undef _GLIBCXX_HAVE_STDINT_H"))
                    cxxConfig ~= "#define _GLIBCXX_HAVE_STDINT_H 1\n";
                else if (line.startsWith("#undef"))
                {
                    cxxConfig ~= "/* " ~ line ~ " */\n";
                }
                else
                    cxxConfig ~= line ~ "\n";
            }

            cxxConfig ~= "\n#endif\n";
            std.file.write(buildPath(projectDir, "tmp-orig", "include-cxx/platform-generic/bits/c++config.h"), cxxConfig);
        }
    };
    projects ~= new class Project
    {
        string archiveBase, archive;
        this()
        {
            super("wine");
            archiveBase = "wine-5.20";
            archive = archiveBase ~ ".tar.xz";
            tmpDirs ~= archiveBase;
        }

        override void download()
        {
            downloadFile("https://dl.winehq.org/wine/source/5.x/" ~ archive, projectDir ~ "/" ~ archive, verbose);
        }

        override void prepare()
        {
            runCommand(["tar", "xf", archive], verbose, projectDir);

            copyFiles(buildPath(projectDir, archiveBase, "include"), "*.h", buildPath(projectDir, "tmp-orig", "include/windows"));
            rename(buildPath(projectDir, "tmp-orig", "include/windows/msvcrt"), buildPath(projectDir, "tmp-orig", "include/msvcrt"));
            copyFiles(buildPath(projectDir, archiveBase, "include/wine"), "*.h", buildPath(projectDir, "tmp-orig", "include"));
        }
    };
    projects ~= new class Project
    {
        this()
        {
            super("common");
            dependencies = ["glibc", "gcc-rt", "linuxapi", "wine"];
        }
    };
    projects ~= new class Project
    {
        this()
        {
            super("sample");
            sourceFiles = ["sample/src/sample.cpp"];
            converterArgs = [
                "--output-config", "sample/output-config.json",
                "-include", "sample/prefixinclude.h"
                ];
        }
    };
    projects ~= new class Project
    {
        string archive, archive2, archiveExtracted;
        string[] docArchives;
        this()
        {
            super("qt5");
            dependencies = ["common"];
            archive = "5.15.2-0-202011130601qtbase-Linux-RHEL_7_6-GCC-Linux-RHEL_7_6-X86_64.7z";
            archive2 = "5.15.2-0-202011130601qtwebengine-Linux-RHEL_7_6-GCC-Linux-RHEL_7_6-X86_64.7z";
            docArchives = [
                "qt.qt5.5152.doc/5.15.2-0-202011130614qtcore-documentation.7z",
                "qt.qt5.5152.doc/5.15.2-0-202011130614qtgui-documentation.7z",
                "qt.qt5.5152.doc/5.15.2-0-202011130614qtwidgets-documentation.7z",
                "qt.qt5.5152.doc/5.15.2-0-202011130614qtnetwork-documentation.7z",
                "qt.qt5.5152.doc.qtwebengine/5.15.2-0-202011130614qtwebengine-documentation.7z",
                ];
            archiveExtracted = "5.15.2";
            sourceFiles = ["qt5/allincludes.cpp"];
            converterArgs = [
                "--output-config", "qt5/output-config.json",
                "-Iqt5/orig/qtbase",
                "-Iqt5/orig/qtbase/QtCore",
                "-Iqt5/orig/qtbase/QtGui",
                "-Iqt5/orig/qtbase/QtWidgets",
                "-Iqt5/orig/qtbase/QtNetwork",
                "-Iqt5/orig/qtwebengine",
                "-Iqt5/orig/qtwebengine/QtWebEngineCore",
                "-Iqt5/orig/qtwebengine/QtWebEngineWidgets",
                "-Igcc-rt/orig/include-cxx",
                "-Igcc-rt/orig/include-cxx/platform-generic",
                "-include", "common/prefixinclude.h",
                "-include", "qt5/prefixinclude.h"
                ];
            tmpDirs ~= archiveExtracted;
            tmpDirs ~= "Docs";
        }

        override void download()
        {
            downloadFile("https://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt5_5152/qt.qt5.5152.gcc_64/" ~ archive, projectDir ~ "/" ~ archive, verbose);
            downloadFile("https://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt5_5152/qt.qt5.5152.qtwebengine.gcc_64/" ~ archive2, projectDir ~ "/" ~ archive2, verbose);

            foreach (a; docArchives)
                downloadFile("https://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt5_5152_src_doc_examples/" ~ a, projectDir ~ "/" ~ baseName(a), verbose);
        }

        override void prepare()
        {
            runCommand(["7z", "x", archive, archiveExtracted ~ "/gcc_64/include/"], verbose, projectDir);
            rename(buildPath(projectDir, archiveExtracted ~ "/gcc_64/include/"), buildPath(projectDir, "tmp-orig/qtbase"));

            runCommand(["7z", "x", archive2, archiveExtracted ~ "/gcc_64/include/"], verbose, projectDir);
            rename(buildPath(projectDir, archiveExtracted ~ "/gcc_64/include/"), buildPath(projectDir, "tmp-orig/qtwebengine"));

            foreach (a; docArchives)
                runCommand(["7z", "x", baseName(a), "Docs/"], verbose, projectDir);

            createDocCommentsFile(projectDir, "https://doc.qt.io/qt-5/");
        }
    };
    projects ~= new class Project
    {
        string archive, archive2, archiveExtracted;
        string[] docArchives;
        this()
        {
            super("qt6");
            dependencies = ["common"];
            archive = "6.2.3-0-202201260729qtbase-Linux-RHEL_8_4-GCC-Linux-RHEL_8_4-X86_64.7z";
            archive2 = "6.2.3-0-202201260729qtwebengine-Linux-RHEL_8_4-GCC-Linux-RHEL_8_4-X86_64.7z";
            docArchives = [
                "qt.qt6.623.doc/6.2.3-0-202201260755qtcore-documentation.7z",
                "qt.qt6.623.doc/6.2.3-0-202201260755qtgui-documentation.7z",
                "qt.qt6.623.doc/6.2.3-0-202201260755qtwidgets-documentation.7z",
                "qt.qt6.623.doc/6.2.3-0-202201260755qtnetwork-documentation.7z",
                "qt.qt6.623.doc.qtwebengine/6.2.3-0-202201260755qtwebengine-documentation.7z",
                ];
            archiveExtracted = "6.2.3";
            sourceFiles = ["qt6/allincludes.cpp"];
            converterArgs = [
                "--output-config", "qt6/output-config.json",
                "-Iqt6/orig/qtbase",
                "-Iqt6/orig/qtbase/QtCore",
                "-Iqt6/orig/qtbase/QtGui",
                "-Iqt6/orig/qtbase/QtWidgets",
                "-Iqt6/orig/qtbase/QtNetwork",
                "-Iqt6/orig/qtwebengine",
                "-Iqt6/orig/qtwebengine/QtWebEngineCore",
                "-Iqt6/orig/qtwebengine/QtWebEngineWidgets",
                "-Igcc-rt/orig/include-cxx",
                "-Igcc-rt/orig/include-cxx/platform-generic",
                "-include", "common/prefixinclude.h",
                "-include", "qt6/prefixinclude.h"
                ];
            tmpDirs ~= archiveExtracted;
            tmpDirs ~= "Docs";
        }

        override void download()
        {
            downloadFile("https://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt6_623/qt.qt6.623.gcc_64/" ~ archive, projectDir ~ "/" ~ archive, verbose);
            downloadFile("https://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt6_623/qt.qt6.623.addons.qtwebengine.gcc_64/" ~ archive2, projectDir ~ "/" ~ archive2, verbose);

            foreach (a; docArchives)
                downloadFile("https://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt6_623_src_doc_examples/" ~ a, projectDir ~ "/" ~ baseName(a), verbose);
        }

        override void prepare()
        {
            runCommand(["7z", "x", archive, archiveExtracted ~ "/gcc_64/include/"], verbose, projectDir);
            rename(buildPath(projectDir, archiveExtracted ~ "/gcc_64/include/"), buildPath(projectDir, "tmp-orig/qtbase"));

            runCommand(["7z", "x", archive2, archiveExtracted ~ "/gcc_64/include/"], verbose, projectDir);
            rename(buildPath(projectDir, archiveExtracted ~ "/gcc_64/include/"), buildPath(projectDir, "tmp-orig/qtwebengine"));

            foreach (a; docArchives)
                runCommand(["7z", "x", baseName(a), "Docs/"], verbose, projectDir);

            createDocCommentsFile(projectDir, "https://doc.qt.io/qt-6/");
        }
    };

    Project[string] projectByName;
    foreach (project; projects)
    {
        projectByName[project.name] = project;
    }

    void selectProject(string name)
    {
        if (name !in projectByName)
        {
            throw new Exception("Unknown project " ~ name);
        }
        if (!projectByName[name].selected)
        {
            projectByName[name].selected = true;
            foreach (dependency; projectByName[name].dependencies)
            {
                selectProject(dependency);
            }
        }
    }
    foreach (name; explicitProjects)
    {
        if (name == "all")
        {
            foreach (project; projects)
                project.selected = true;
        }
        else
            selectProject(name);
    }

    runCommand(["dub", "build"], true);

    foreach (project; projects)
    {
        const projectDir = project.projectDir;
        if (!project.selected)
            continue;
        if ((&project.download).funcptr is &Project.download
                && (&project.prepare).funcptr is &Project.prepare)
            continue;

        string currentMemberDescription = project.getMemberDescription();
        string cacheKeyPath = buildPath(projectDir, "orig-cache-key.txt");
        string previousMemberDescription;
        if (exists(cacheKeyPath))
            previousMemberDescription = readText(cacheKeyPath);

        if (!exists(projectDir ~ "/orig") || currentMemberDescription != previousMemberDescription)
        {
            writeln("===== ", project.name, " =====");

            foreach (d; project.tmpDirs)
                rmdirRecurseIfExists(buildPath(projectDir, d));
            rmdirRecurseIfExists(buildPath(projectDir, "orig"));
            rmdirRecurseIfExists(buildPath(projectDir, "tmp-orig"));
            if (exists(cacheKeyPath))
                remove(cacheKeyPath);
            mkdirRecurse(buildPath(projectDir, "tmp-orig"));

            mkdirRecurse(projectDir);
            project.download();
            project.prepare();

            rename(buildPath(projectDir, "tmp-orig"), buildPath(projectDir, "orig"));

            foreach (d; project.tmpDirs)
                rmdirRecurseIfExists(buildPath(projectDir, d));

            std.file.write(cacheKeyPath, currentMemberDescription);
        }
    }

    foreach (project; projects)
    {
        if (!project.selected)
            continue;
        if (project.sourceFiles.length)
        {
            writeln("===== ", project.name, " =====");
            rmdirRecurseIfExists(buildPath(project.projectDir, "conv"));
            runCommand(["../cppconv", "--output-dir", project.name ~ "/conv"] ~ project.sourceFiles ~ project.converterArgs ~ extraConverterArgs, true, "projects");
        }
    }

    return 0;
}
