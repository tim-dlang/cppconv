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

void runCommand(string[] args, string workDir = null, Appender!string *app = null)
{
    if (app !is null)
        app.put(text("Running: ", escapeShellCommand(args), "\n"));
    else
        writeln("Running: ", escapeShellCommand(args));

    Redirect redirect = Redirect.stdin;
    if (app !is null)
        redirect |= Redirect.stdout | Redirect.stderrToStdout;
    auto pipes = pipeProcess(args, redirect, null, Config.none, workDir);
    pipes.stdin.close();
    if (app !is null)
    {
        foreach (ubyte[] chunk; pipes.stdout.byChunk(4096))
            app.put(chunk);
    }

    auto status = pipes.pid.wait();

    if (status)
    {
        throw new Exception(text("Command ", args[0], " failed with status ", status));
    }
}

class Test
{
    string name;
    string workDir;
    string[] translationUnits;
    string[] includedFiles;
    string[] testDefines;
    string[] expectedOutputFiles;
    string[] extraArgs;
}

int cmpNumberStrings(string a, string b)
{
    while (1)
    {
        if (a.length == 0 && b.length == 0)
            return 0;
        if (a.length == 0)
            return -1;
        if (b.length == 0)
            return 1;

        size_t nlena;
        while (nlena < a.length && a[nlena] >= '0' && a[nlena] <= '9')
            nlena++;
        size_t nlenb;
        while (nlenb < b.length && b[nlenb] >= '0' && b[nlenb] <= '9')
            nlenb++;

        if (nlena != nlenb)
        {
            if (nlena == 0)
                return 1;
            if (nlenb == 0)
                return -1;
            if (nlena < nlenb)
                return -1;
            if (nlena > nlenb)
                return 1;
        }

        if (a[0] < b[0])
            return -1;
        if (a[0] > b[0])
            return 1;

        a = a[1 .. $];
        b = b[1 .. $];
    }
}

int main(string[] args)
{
    Test[] tests;
    Test[string] testByName;
    bool anyFailure;
    bool color;
    bool github;
    bool updateExpected;

    for (size_t i = 1; i < args.length; i++)
    {
        auto arg = args[i];
        if (arg.startsWith("--color"))
        {
            color = true;
        }
        else if (arg.startsWith("--github"))
        {
            github = true;
        }
        else if (arg.startsWith("--update-expected"))
        {
            updateExpected = true;
        }
        else
        {
            stderr.writeln("Unknown argument ", arg);
            return 1;
        }
    }

    foreach (DirEntry e; dirEntries("tests/single", SpanMode.depth))
    {
        string name = e.name.stripExtension;
        string ext = e.name.extension;

        if (e.name.endsWith("-output-config.json"))
        {
            ext = "-output-config.json";
            name = e.name[0 .. $ - ext.length];
        }

        Test test;
        if (name in testByName)
        {
            test = testByName[name];
        }
        else
        {
            test = new Test;
            test.name = name;
            testByName[name] = test;
            tests ~= test;
            test.workDir = "tests/single";
        }

        if (ext.among(".c", ".cpp"))
        {
            test.translationUnits ~= relativePath(absolutePath(e.name), absolutePath(test.workDir));
        }
        else if (ext == ".d")
        {
            test.expectedOutputFiles ~= relativePath(absolutePath(e.name), absolutePath(test.workDir));
        }
        else if (ext == "-output-config.json")
        {
            test.extraArgs = ["--output-config", relativePath(absolutePath(e.name), absolutePath(test.workDir))];
        }
        else
        {
            stderr.writeln("Unexpected file: ", e.name);
            anyFailure = true;
            continue;
        }
    }

    foreach (DirEntry d; dirEntries("tests/multifile", SpanMode.shallow))
    {
        Test test = new Test;
        test.name = d.name;
        test.workDir = d.name;
        tests ~= test;

        foreach (DirEntry e; dirEntries(d.name, SpanMode.depth))
        {
            string name = e.name.stripExtension;
            string ext = e.name.extension;

            if (ext.among(".c", ".cpp"))
            {
                test.translationUnits ~= relativePath(absolutePath(e.name), absolutePath(test.workDir));
            }
            else if (ext.among(".h"))
            {
                test.includedFiles ~= relativePath(absolutePath(e.name), absolutePath(test.workDir));
            }
            else if (ext.among(".d"))
            {
                test.expectedOutputFiles ~= relativePath(absolutePath(e.name), absolutePath(test.workDir));
            }
            else if (baseName(e.name) == "output-config.json")
            {
                test.extraArgs = ["--output-config", relativePath(absolutePath(e.name), absolutePath(test.workDir))];
            }
            else
            {
                stderr.writeln("Unexpected file: ", e.name);
                anyFailure = true;
            }
        }
    }

    tests.sort!((a, b) {
        return cmpNumberStrings(a.name, b.name) < 0;
    });

    auto regexTestDefine = regex(r"\bDEF[a-zA-Z0-9]*\b");
    foreach (test; tests)
    {
        test.translationUnits.sort!((a, b) {
            return cmpNumberStrings(a, b) < 0;
        });
        test.includedFiles.sort!((a, b) {
            return cmpNumberStrings(a, b) < 0;
        });
        test.expectedOutputFiles.sort!((a, b) {
            return cmpNumberStrings(a, b) < 0;
        });
        foreach (filename; test.translationUnits ~ test.includedFiles)
        {
            string content = readText(buildPath(test.workDir, filename));
            foreach (c; matchAll(content, regexTestDefine))
            {
                if (!test.testDefines.canFind(c.hit))
                    test.testDefines ~= c.hit;
            }
        }
        test.testDefines.sort!((a, b) {
            return cmpNumberStrings(a, b) < 0;
        });
    }

    if (exists("test_results"))
    {
        rmdirRecurse("test_results");
    }

    runCommand(["dub", "build"]);

    string[] failedTests;
    size_t successfulTests;
    foreach (test; tests)
    {
        auto testDir = absolutePath(buildPath("test_results", test.name));
        auto convDir = absolutePath(buildPath("test_results", test.name, "conv"));
        Appender!string app;
        bool hasError;
        try
        {
            runCommand([relativePath(absolutePath("./cppconv"), absolutePath(test.workDir)),
                "--output-dir", relativePath(convDir, absolutePath(test.workDir)),
                "--extra-output-dir", relativePath(testDir, absolutePath(test.workDir)),
                "-DALWAYS_PREDEFINED_IN_TEST=1", "-UALWAYS_PREUNDEFINED_IN_TEST"]
                ~ test.extraArgs
                ~ test.translationUnits, test.workDir, &app);

            foreach (tu; test.translationUnits)
            {
                string[] gccArgs = [tu.extension == ".cpp" ? "g++" : "gcc",
                    tu, "-c", "-o", "/dev/null"];
                if (color)
                    gccArgs ~= "-fdiagnostics-color";
                runCommand(gccArgs, test.workDir, &app);
                foreach (testDefine; test.testDefines)
                {
                    runCommand(gccArgs ~ ["-D" ~ testDefine], test.workDir, &app);
                }
            }

            string[] outputFiles;

            foreach (DirEntry e; dirEntries(convDir, SpanMode.depth))
            {
                enforce(e.name.endsWith(".d"));
                outputFiles ~= relativePath(absolutePath(e.name), absolutePath(convDir));
                string[] dmdArgs = ["dmd", relativePath(absolutePath(e.name), absolutePath(convDir)),
                    "-I" ~ relativePath(absolutePath("tests/helpers"), absolutePath(convDir)),
                    "-c", "-of/dev/null"];
                if (color)
                    dmdArgs ~= "-color=on";
                runCommand(dmdArgs, convDir, &app);
                foreach (testDefine; test.testDefines)
                {
                    runCommand(dmdArgs ~ ["-version=" ~ testDefine], convDir, &app);
                }
            }

            outputFiles.sort!((a, b) {
                return cmpNumberStrings(a, b) < 0;
            });

            if (updateExpected)
            {
                foreach (name; test.expectedOutputFiles)
                {
                    remove(buildPath(test.workDir, name));
                }

                foreach (name; outputFiles)
                {
                    copy(buildPath(convDir, name), buildPath(test.workDir, name));
                }

                test.expectedOutputFiles = outputFiles;
            }

            if (outputFiles != test.expectedOutputFiles)
            {
                throw new Exception(text("Wrong set of output files: ", outputFiles, " expected: ", test.expectedOutputFiles));
            }

            foreach (name; outputFiles)
            {
                string text1 = readText(buildPath(test.workDir, name)).replace("\r", "");
                string text2 = readText(buildPath(convDir, name)).replace("\r", "");
                if (text1 != text2)
                {
                    app.put(text("Files differ: ", name, "\n"));
                    runCommand(["diff", buildPath(test.workDir, name), buildPath(convDir, name)], null, &app);
                    hasError = true;
                }
            }

            if (!hasError)
                successfulTests++;
        }
        catch (Exception e)
        {
            app.put(e.msg);
            app.put("\n");
            hasError = true;
        }
        if (hasError)
        {
            failedTests ~= test.name;
            anyFailure = true;
            if (github)
                writeln("::group::Test ", test.name, " failed");
            else
                writeln("############ Test ", test.name, " failed ############");
            writeln(app.data);
            if (github)
                writeln("::endgroup::");
        }
    }

    if (failedTests.length)
    {
        writeln("Failed tests:");
        foreach (test; failedTests)
            writeln("  ", test);
    }

    writeln("Successful tests: ", successfulTests, " / ", tests.length);

    return anyFailure;
}
