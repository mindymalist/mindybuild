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
else version (MindybuildUnittestApp) {
	void main() {
		return;
	}
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

			case "make":
			case "--make":
			case "-m":
				return runMake(stderr, args[1 .. $]);

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
			static import mindybuild.configure;

			return mindybuild.configure.run(stderr, args);
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
					stderr.writeln(file, ": ", ex.msg);
					continue;
				}

				const(str)[] moduleName;
				try {
					moduleName = parseModuleName(sourceCode);
				}
				catch (ParserException ex) {
					status = Status.error;
					stderr.writeln(file, ": ", ex.msg);
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

		int runMake(File stderr, string[] args) {
			static import mindybuild.make;

			return mindybuild.make.run(stderr, args);
		}
	}

	debug void writeExceptionOrigin(File target, Throwable ex) @trusted {
		debug target.writeln("\tThrown from ", ex.file, "(", ex.line, ").\n", ex.info);
	}
}
