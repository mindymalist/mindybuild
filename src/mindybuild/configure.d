/+
	This file is part of «mindybuild» — “an open-source build configuration and build system.”
	Copyright © 2026  Mindy Batek (0xEAB)

	This Source Code Form is subject to the terms of the Mozilla Public
	License, v. 2.0. If a copy of the MPL was not distributed with this
	file, You can obtain one at https://mozilla.org/MPL/2.0/.
 +/
/++
	mindybuild — Build Configuration System
 +/
module mindybuild.configure;

import mindybuild.common;
import mindybuild.kapenparse;

import std.array;
import std.conv;
import File = std.file;
import Meta = std.meta;
import std.path;
import std.stdio : FileHandle = File;

///
int run(FileHandle stderr, string[] args) @safe {
	try {
		changeDirectoryToProjectRoot();
		const recipe = collectBuildRecipe(args);
		writeMakefile(recipe);
		return 0;
	}
	catch (Exception ex) {
		(() @trusted => stderr.writeln(ex))();
	}

	return 1;
}

///
struct Sentinel {
	///
	str filename;

	///
	Type type;

	///
	enum Type {
		///
		file,

		///
		directory,
	}
}

immutable struct Conventions {
	@disable this();
	@disable this(this);

	// Sentinels
	static immutable {

		auto projectRootSentinelsPrimary = [
			Sentinel(".mindybuild", Sentinel.Type.directory),
			Sentinel(".mindybuild-root", Sentinel.Type.file),
		];
		auto projectRootSentinelsSecondary = [
			Sentinel(".git", Sentinel.Type.directory),
			Sentinel(".gitignore", Sentinel.Type.file),
			Sentinel(".hg", Sentinel.Type.directory),
			Sentinel(".hgignore", Sentinel.Type.file),
			Sentinel("dub.json", Sentinel.Type.file),
			Sentinel("dub.sdl", Sentinel.Type.file),
		];

		auto buildUnitRootSentinelsPrimary = [
			".mindybuild-buildunit",
			".buildunit",
		];

		auto stringImportRootSentinelsPrimary = [
			".-J",
			".mindybuild-J",
			".string-imports",
		];
		auto stringImportDirectorySentinels = [
			".string-imports",
			"dubhash.txt",
		];

		auto dImportRootSentinelsPrimary = [
			".-I",
			".d-imports",
			".imports",
		];
		auto dImportRootSentinelsSecondary = [
			".-I",
			".d-imports",
			".imports",
		];

	}

	// File extensions
	static immutable {

		auto stringImportFileExtensions = [
			".dt",
		];

		auto stringImportCommonDirectories = [
			"views",
			"strings",
		];

		auto dSourceFileExtensions = [
			".d",
		];
		auto dImportFileExtensions = [
			".di",
		];

		auto cSourceFileExtensions = [
			".c",
		];
		auto cIncludeFileExtensions = [
			".h",
			".i",
		];

		auto objectFileExtensions = [
			".o",
			".obj",
		];
		auto libraryStaticFileExtensions = [
			".a",
			".lib",
		];
		auto libraryDynamicFileExtensions = [
			".so",
			".dll",
		];
	}
}

struct Recipe {
	str name;
	OutputPaths paths;

	BuildUnit[] units = null;
	str dCompiler;
}

struct BuildUnit {
	str name;

	str[] dflags;
	str[] lflags;

	BuildPaths paths;
	str dCompiler;
}

struct BuildPaths {
	InputPaths input;
	OutputPaths output;
}

struct InputPaths {
	str[] source;
	str[] import_;
	str[] stringImport;
}

struct OutputPaths {
	str prefix = ".";
	str bin = "$(prefix)/bin";
	str lib = "$(prefix)/lib";
}

///
final class ConfigureException : Exception {
	private this(
		string msg,
		Throwable nextInChain = null,
		string file = __FILE__, size_t line = __LINE__,
	) @nogc @safe pure nothrow {
		super(msg, file, line, null);
	}
}

@safe:

void changeDirectoryToProjectRoot() {
	str projectRoot;
	try {
		projectRoot = determineProjectRoot();
	}
	catch (Exception ex) {
		throw new ConfigureException("An error occured while determining the project root.", ex);
	}
	if (projectRoot is null) {
		return;
	}

	try {
		File.chdir(projectRoot);
	}
	catch (Exception ex) {
		const projectRootString = (() @trusted => cast(string) projectRoot)();
		const msg = "Could not change the current working directory to `" ~ projectRootString ~ "`.";
		throw new ConfigureException(msg);
	}
}

str determineProjectRoot() {
	str projectRoot = findDirUpstream(".", Conventions.projectRootSentinelsPrimary);

	if (projectRoot is null) {
		projectRoot = findDirUpstream(".", Conventions.projectRootSentinelsSecondary);
	}

	return projectRoot;
}

Recipe collectBuildRecipe(const str[] args) {
	auto result = Recipe();

	result.name = baseName(".".asAbsolutePath).array;
	// TODO

	return result;
}

void writeMakefile(const Recipe recipe) {
	// TODO
	assert(false, "Not implemented.");
}

@safe:

BuildUnit collectBuildUnit(string path) {
	import std.array : array;
	import std.path;

	auto result = BuildUnit();

	result.name = path.asAbsolutePath.asNormalizedPath.array.baseName;

	auto sourceFiles = appender!(str[]);
	auto importDirs = appender!(str[]);
	auto stringDirs = appender!(str[]);
	collectFilesByPurpose(
		path, sourceFiles, importDirs, stringDirs
	);

	result.paths.input.source = sourceFiles[];
	result.paths.input.import_ = importDirs[];
	result.paths.input.stringImport = stringDirs[];

	return result;
}

private void collectFilesByPurpose(
	string path,
	ref Appender!(str[]) sourceFiles,
	ref Appender!(str[]) importDirs,
	ref Appender!(str[]) stringDirs,
) @safe {
	import std.array : array;
	import std.path;

	bool pathAsImportDirAdded = false;
	void addPathAsImportDir() {
		if (pathAsImportDirAdded) {
			return;
		}

		importDirs ~= path;
		pathAsImportDirAdded = true;
	}

	bool pathAsStringImportDirAdded = false;
	void addPathAsStringImportDir() {
		if (pathAsStringImportDirAdded) {
			return;
		}

		stringDirs ~= path;
		pathAsStringImportDirAdded = true;
	}

	const pathBaseName = path.asAbsolutePath.asNormalizedPath.array.baseName;
	if (Conventions.stringImportCommonDirectories.contains(pathBaseName)) {
		addPathAsStringImportDir();
	}

	() @trusted /* ← DMD < 2.114 */ {
		foreach (file; File.dirEntries(path, File.SpanMode.shallow)) {
			() @safe {
				if (file.isFile) {
					if (file.name.isDSourceFile) {
						string sourceCode = (() @trusted => cast(string) File.read(file.name))();
						const moduleName = parseModuleName(sourceCode);
					}
					if (file.name.isDSourceFile || file.name.isCSourceFile) {
						sourceFiles ~= file.name;
						// TODO: wrong dir
						addPathAsImportDir();
						return;
					}

					if (file.name.isDImportFile || file.name.isCIncludeFile) {
						// TODO: wrong dir
						addPathAsImportDir();
						return;
					}

					if (file.name.isDImportFile || file.name.isCIncludeFile) {
						// TODO: wrong dir
						addPathAsImportDir();
						return;
					}

					if (Conventions.stringImportDirectorySentinels.contains(file.name)) {
						addPathAsStringImportDir();
						return;
					}

					const fileExt = file.name.extension;
					if (Conventions.stringImportFileExtensions.contains(fileExt)) {
						addPathAsStringImportDir();
						return;
					}

					return;
				}

				if (file.isDir) {
					if (file.name == "..") {
						return;
					}
					if (file.name == path) {
						return;
					}

					collectFilesByPurpose(file.name, sourceFiles, importDirs, stringDirs);
				}
			}();
		}
	}();
}

private str findDirUpstream(string pathStartingPoint, const(Sentinel)[] needles) {
	static immutable parent = dirSeparator ~ "..";

	for (auto path = appender!string(pathStartingPoint); !isRoot(path[]); path ~= parent) {
		foreach (needle; needles) {
			bool found = false;
			auto filePath = chainPath(path[], needle.filename);
			try {
				found = File.exists(filePath);
			}
			catch (Exception) {
				continue;
			}

			if (found) {
				final switch (needle.type) {
					case Sentinel.Type.file:
						if (File.isFile(filePath)) {
							return path.array;
						}
						break;

					case Sentinel.Type.directory:
						if (File.isDir(filePath)) {
							return path.array;
						}
						break;
				}
			}
		}
	}

	return null;
}

bool isRoot(str path) {
	import std.algorithm.comparison : cmp;
	import std.path;

	const compared = cmp(
		chainPath(path, ".").asAbsolutePath.asNormalizedPath,
		chainPath(path, "..").asAbsolutePath.asNormalizedPath,
	);

	return (compared == 0);
}

str fileExtensionOf(str filename) {
	import std.path : extension;

	return extension(filename);
}

bool isDSourceFile(str filename) {
	return Conventions.dSourceFileExtensions.contains(fileExtensionOf(filename));
}

bool isDImportFile(str filename) {
	return Conventions.dImportFileExtensions.contains(fileExtensionOf(filename));
}

bool isCSourceFile(str filename) {
	return Conventions.cSourceFileExtensions.contains(fileExtensionOf(filename));
}

bool isCIncludeFile(str filename) {
	return Conventions.cIncludeFileExtensions.contains(fileExtensionOf(filename));
}

bool isObjectFile(str filename) {
	return Conventions.objectFileExtensions.contains(fileExtensionOf(filename));
}

bool isStaticLibraryFile(str filename) {
	return Conventions.libraryStaticFileExtensions.contains(fileExtensionOf(filename));
}

bool isDynamicLibraryFile(str filename) {
	return Conventions.libraryDynamicFileExtensions.contains(fileExtensionOf(filename));
}
