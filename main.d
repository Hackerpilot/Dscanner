
//          Copyright Brian Schott (Sir Alaran) 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module main;


import std.file;
import std.stdio;
import std.algorithm;
import std.conv;
import std.array;
import std.path;
import std.regex;
import std.getopt;
import std.parallelism;
import types;
import tokenizer;
import parser;
import langutils;
import autocomplete;
import highlighter;

pure bool isLineOfCode(TokenType t)
{
	switch(t)
	{
	case TokenType.Semicolon:
	case TokenType.While:
	case TokenType.If:
	case TokenType.For:
	case TokenType.Foreach:
	case TokenType.Foreach_reverse:
	case TokenType.Case:
		return true;
	default:
		return false;
	}
}

/**
 * Loads any import directories specified in /etc/dmd.conf.
 * Bugs: Only works on Linux
 * Returns: the paths specified as -I options in /etc/dmd.conf
 */
string[] loadDefaultImports()
{
version(linux)
{
	string path = "/etc/dmd.conf";
	if (!exists(path))
		return [];
	string[] rVal;
	auto file = File(path, "r");
	foreach(char[] line; file.byLine())
	{
		if (!line.startsWith("DFLAGS"))
			continue;
		while ((line = line.find("-I")).length > 0)
		{
			auto end = std.string.indexOf(line, " ");
			auto importDir = line[2 .. end].idup;
			rVal ~= importDir;
			line = line[end .. $];
		}
	}
	return rVal;
}
else
{
	return [];
}
}

/**
 * Returns: the absolute path of the given module, or null if it could not be
 *     found.
 */
string findAbsPath(string[] dirs, string moduleName)
{
	// For file names
	if (endsWith(moduleName, ".d") || endsWith(moduleName, ".di"))
	{
		if (isAbsolute(moduleName))
			return moduleName;
		else
			return buildPath(getcwd(), moduleName);
	}

	// Try to find the file name from a module name like "std.stdio"
	foreach(dir; dirs)
	{
		string fileLocation = buildPath(dir, replace(moduleName, ".", dirSeparator));
		string dfile = fileLocation ~ ".d";
		if (exists(dfile) && isFile(dfile))
		{
			return dfile;
		}
		if (exists(fileLocation  ~ ".di") && isFile(fileLocation  ~ ".di"))
		{
			return fileLocation ~ ".di";
		}
	}
	stderr.writeln("Could not locate import ", moduleName, " in ", dirs);
	return null;
}

string[] loadConfig()
{
	string path = expandTilde("~" ~ dirSeparator ~ ".dscanner");
	string[] dirs;
	if (exists(path))
	{
		auto f = File(path, "r");
		scope(exit) f.close();

		auto trimRegex = ctRegex!(`\s*$`);
		foreach(string line; lines(f))
		{
			dirs ~= replace(line, trimRegex, "");
		}
	}
	foreach(string importDir; loadDefaultImports()) {
		dirs ~= importDir;
	}
	return dirs;
}

int main(string[] args)
{
	string[] importDirs;
	bool sloc;
	bool dotComplete;
	bool json;
	bool parenComplete;
	bool highlight;
	bool ctags;
	bool recursiveCtags;
	bool format;
	bool help;

	try
	{
		getopt(args, "I", &importDirs, "dotComplete", &dotComplete, "sloc", &sloc,
			"json", &json, "parenComplete", &parenComplete, "highlight", &highlight,
			"ctags", &ctags, "recursive|r|R", &recursiveCtags, "help|h", &help);
	}
	catch (Exception e)
	{
		stderr.writeln(e.msg);
	}

	if (help)
	{
		printHelp();
		return 0;
	}

	importDirs ~= loadConfig();

	if (sloc)
	{
		if (args.length == 1)
		{
			auto f = appender!string();
			char[] buf;
			while (stdin.readln(buf))
				f.put(buf);
			writeln(f.data.tokenize().count!(a => isLineOfCode(a.type))());
		}
		else
		{
			writeln(args[1..$].map!(a => a.readText().tokenize())().joiner()
				.count!(a => isLineOfCode(a.type))());
		}
		return 0;
	}

	if (highlight)
	{
		if (args.length == 1)
		{
			auto f = appender!string();
			char[] buf;
			while (stdin.readln(buf))
				f.put(buf);
			highlighter.highlight(f.data.tokenize(IterationStyle.EVERYTHING));
		}
		else
		{
			highlighter.highlight(args[1].readText().tokenize(IterationStyle.EVERYTHING));
		}
		return 0;
	}

	if (dotComplete || parenComplete)
	{
		if (isAbsolute(args[1]))
			importDirs ~= dirName(args[1]);
		else
			importDirs ~= getcwd();
		Token[] tokens;
		try
		{
			to!size_t(args[1]);
			auto f = appender!string();
			char[] buf;
			while (stdin.readln(buf))
				f.put(buf);
			tokens = f.data.tokenize();
		}
		catch(ConvException e)
		{
			tokens = args[1].readText().tokenize();
			args.popFront();
		}
		auto mod = parseModule(tokens);
		CompletionContext context = new CompletionContext(mod);
		context.importDirectories = importDirs;
		foreach (im; parallel(mod.imports))
		{
			auto p = findAbsPath(importDirs, im);
			if (p is null || !p.exists())
				continue;
			context.addModule(p.readText().tokenize().parseModule());
		}
		auto complete = AutoComplete(tokens, context);
		if (parenComplete)
			writeln(complete.parenComplete(to!size_t(args[1])));
		else if (dotComplete)
			writeln(complete.dotComplete(to!size_t(args[1])));
		return 0;
	}

	if (json)
	{
		Token[] tokens;
		if (args.length == 1)
		{
			// Read from stdin
			auto f = appender!string();
			char[] buf;
			while (stdin.readln(buf))
				f.put(buf);
			tokens = tokenize(f.data);
		}
		else
		{
			// read given file
			tokens = tokenize(readText(args[1]));
		}
		auto mod = parseModule(tokens);
		mod.writeJSONTo(stdout);
		return 0;
	}

	if (ctags)
	{
		stdout.writeln("!_TAG_FILE_FORMAT 2");
		stdout.writeln("!_TAG_FILE_SORTED 1");
		stdout.writeln("!_TAG_PROGRAM_URL https://github.com/Hackerpilot/Dscanner/");
		if (!recursiveCtags)
		{
			auto tokens = tokenize(readText(args[1]));
			auto mod = parseModule(tokens);
			foreach (tag; mod.getCtags(args[1]))
				stdout.writeln(tag);
		}
		else
		{
			string[] allTags;
			foreach (dirEntry; dirEntries(args[1], SpanMode.breadth))
			{
				if (!dirEntry.name.endsWith(".d", ".di"))
					continue;
				stderr.writeln("Generating tags for ", dirEntry.name);
				auto tokens = tokenize(readText(dirEntry.name));
				auto mod = parseModule(tokens);
				allTags ~= mod.getCtags(dirEntry.name);
			}
			allTags.sort();
			foreach (tag; allTags)
				stdout.writeln(tag);
		}
	}
	return 0;
}

void printHelp()
{
	writeln(
q{
    Usage: dscanner options

options:
    --help | -h
        Prints this help message

    --sloc [sourceFiles]
        count the number of logical lines of code in the given
        source files. If no files are specified, a file is read from stdin.

    --json [sourceFile]
        Generate a JSON summary of the given source file. If no file is
        specifed, the file is read from stdin.

    --dotComplete [sourceFile] cursorPosition
        Provide autocompletion for the insertion of the dot operator. The cursor
        position is the character position in the *file*, not the position in
        the line. If no file is specified, the file is read from stdin.

    --parenComplete [sourceFile] cursorPosition
        Provides a listing of function parameters or pre-defined version
        identifiers at the cursor position. The cursor position is the character
        position in the *file*, not the line. If no file is specified, the
        contents are read from stdin.

    --highlight [sourceFile] - Syntax-highlight the given source file. The
        resulting HTML will be written to standard output.

    -I includePath
        Include _includePath_ in the list of paths used to search for imports.
        By default dscanner will search in the current working directory as
        well as any paths specified in /etc/dmd.conf. This is only used for the
        --parenComplete and --dotComplete options.

    --ctags sourceFile
        Generates ctags information from the given source code file. Note that
        ctags information requires a filename, so stdin cannot be used in place
        of a filename.

    --recursive | -R | -r directory
        When used with --ctags, dscanner will produce ctags output for all .d
        and .di files contained within directory and its sub-directories.});
}
