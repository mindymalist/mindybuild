/+
	This file is part of «mindybuild» — “an open-source build configuration and build system.”
	Copyright © 2026  Mindy Batek (0xEAB)

	This Source Code Form is subject to the terms of the Mozilla Public
	License, v. 2.0. If a copy of the MPL was not distributed with this
	file, You can obtain one at https://mozilla.org/MPL/2.0/.
 +/
/++
	Command-line interface of mindybuild.
 +/
module mindybuild.cli;

import mindybuild.common;

version (MindybuildCommandLineApp) {
	mixin MindybuildCommandLineAppEntryPoint!();
}

///
mixin template MindybuildCommandLineAppEntryPoint() {
	private int main(string[] args) @system {
		import mindybuild.cli;
		import std.stdio;

		return runMindybuildCommandLineApp!()(stdout, stdout, args[0], args[1 .. $]);
	}
}

///
template runMindybuildCommandLineApp() {
	import std.stdio;

@safe:

	///
	int runMindybuildCommandLineApp(File stdout, File stderr, string arg0, string[] args) {
		import mindybuild.common;

		if (args.length == 0) {
			stderr.writeln("mindybuild -- Build configuration and build system.\n");
			stderr.writeHelp(arg0);
			stderr.writeln("Error: No command provided.");
			return 1;
		}

		switch (args[0]) {
			case "build":
			case "--build":
			case "-b":
				return runBuild(stderr, args[1 .. $]);

			case "configure":
			case "conf":
			case "--configure":
			case "--conf":
			case "-c":
				return runConfigure(stderr, args[1 .. $]);

			case "get-module-name":
			case "--get-module-name":
				return runGetModuleName(stdout, stderr, args[1 .. $]);

			case "lex-bel":
			case "--lex-bel":
				return runLexBEL(stdout, stderr, args[1 .. $]);

			case "make":
			case "--make":
			case "-m":
				return runMake(stderr, args[1 .. $]);

			case "parse-bel":
			case "--parse-bel":
				return runParseBEL(stdout, stderr, args[1 .. $]);

			case "help":
			case "--help":
			case "-h":
				stdout.writeHelp(arg0);
				return 0;

			default:
				break;
		}

		stderr.writeln("Error: Unknown command `", args[0], "`.");
		return 1;

	}

	private {
		void writeHelp(File target, string arg0) {
			target.writeln(
				"Usage:\n"
					~ "\t", arg0, "  <command> [<args>]\n"
					~ "\n"
					~ "Available commands:\n"
					~ "\t    build - Run both the Build Configuration utility and the Build System.\n"
					~ "\t            \t--     - Separates build configuration and build system arguments.\n"
					~ "\tconfigure - Run the Build Configuration utility.\n"
					~ "\t            \t--list - List the available configuration options of the current project.\n"
					~ "\t     make - Run the Build System.\n"
					~ "\t            \t-j=<n> - Number of jobs to run simultaneously.\n"
					~ "\t            \t -j<n>\n"
					~ "\t     help - Print this help text.\n"
			);
		}

		void writeErrorNoInputfiles(File target) {
			target.writeln("Error: No input files provided.");
		}

		int runBuild(File stderr, string[] args) {
			string[] confArgs = null;
			string[] makeArgs = null;

			if (args.length > 0) {
				foreach (idx, arg; args) {
					if (arg == "--") {
						confArgs = args[0 .. idx];
						makeArgs = args[idx + 1 .. $];
						break;
					}
				}

				if (confArgs is null) {
					confArgs = args;
				}
			}

			const confStatus = runConfigure(stderr, confArgs);
			if (confStatus != 0) {
				return confStatus;
			}

			const makeStatus = runMake(stderr, makeArgs);
			return makeStatus;
		}

		int runConfigure(File stderr, string[] args) {
			return 1;
		}

		int runGetModuleName(File stdout, File stderr, string[] args) {
			import mindybuild.kapenparse;
			import std.file : readText;

			if (args.length == 0) {
				stderr.writeErrorNoInputfiles();
				return 1;
			}

			auto status = Status.success;

			foreach (file; args) {
				string sourceCode;

				try {
					sourceCode = readText(file);
				}
				catch (Exception ex) {
					status = status.error;
					stderr.writeln(file, ": ", ex.message);
					continue;
				}

				const(str)[] moduleName;
				try {
					moduleName = parseModuleName(sourceCode);
				}
				catch (ParserException ex) {
					status = Status.error;
					stderr.writeln(file, ": ", ex.message);
					continue;
				}

				foreach (idx, id; moduleName) {
					if (idx == 0) {
						stdout.write(id);
						continue;
					}

					stdout.write(".", id);
				}
				stdout.writeln();
			}

			return (status == Status.success) ? 0 : 1;
		}

		int runLexBEL(File stdout, File stderr, string[] args) {
			import mindybuild.annabel;
			import std.file : readText;

			if (args.length == 0) {
				stderr.writeErrorNoInputfiles();
				return 1;
			}

			if (args.length > 1) {
				stderr.writeln("Error: Too many arguments.");
				return 1;
			}

			const file = args[0];

			string sourceCode;
			try {
				sourceCode = readText(file);
			}
			catch (Exception ex) {
				stderr.writeln(file, ": ", ex.msg);
				debug {
					stderr.writeExceptionOrigin(ex);
				}
				return 1;
			}

			auto status = Status.success;
			foreach (token; Lexer(sourceCode, file)) {
				if (token.type == Token.Type.invalid) {
					status = Status.error;
				}
				else if (token.type == Token.Type.invalidCharset) {
					status = Status.error;
				}

				const(char)[][1] tokData = [token.data];
				stdout.writefln!"%s,%s,%s,%(%s%)"(token.location.file, token.location.byteOffset, token.type, tokData);
			}

			return (status == Status.success) ? 0 : 1;
		}

		int runMake(File stderr, string[] args) {
			return 1;
		}

		int runParseBEL(File stdout, File stderr, string[] args) {
			import mindybuild.annabel;
			import std.file : readText;

			if (args.length == 0) {
				stderr.writeErrorNoInputfiles();
				return 1;
			}

			if (args.length > 1) {
				stderr.writeln("Error: Too many arguments.");
				return 1;
			}

			const file = args[0];

			string sourceCode;
			try {
				sourceCode = readText(file);
			}
			catch (Exception ex) {
				stderr.writeln(file, ": ", ex.msg);
				return 1;
			}

			try {
				foreach (statement; Parser(sourceCode, file)) {
					stdout.write(statement.toString());
				}
			}
			catch (ParserException ex) {
				stderr.writeln(ex.location.humanReadable, ": ", ex.msg);
				debug {
					stderr.writeExceptionOrigin(ex);
				}
				return 1;
			}
			catch (Exception ex) {
				stderr.writeln("Error: ", ex.msg);
				debug {
					stderr.writeExceptionOrigin(ex);
				}
				return 1;
			}

			return 0;
		}
	}

	debug void writeExceptionOrigin(File target, Throwable ex) {
		debug target.writeln("\tThrown from ", ex.file, "(", ex.line, ").\n", ex.info);
	}
}
