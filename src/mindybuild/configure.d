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
import mindybuild.database;
import mindybuild.fcompat;
import mindybuild.kapenparse;

import std.array;
import std.conv;
import File = std.file;
import Meta = std.meta;
import std.stdio : FileHandle = File;

///
int run(FileHandle stderr, string[] args) @safe {
	try {
		changeDirectoryToProjectRoot();
		const recipe = collectBuildRecipe(args);
		writeMakefile(recipe);
		return 0;
	}
	catch (ConfigureException ex) {
		(() @trusted => stderr.lockingTextWriter.writeException(ex))();
	}
	catch (Exception ex) {
		(() @trusted => stderr.writeln(ex))();
	}

	return 1;
}

immutable struct Conventions {
	@disable this();
	@disable this(this);

	// Sentinels
	static immutable {

		auto projectRootSentinelsPrimary = [
			".mindybuild",
			".mindybuild-root",
		];
		auto projectRootSentinelsSecondary = [
			".git",
			".gitignore",
			".hg",
			".hgignore",
			"dub.json",
			"dub.sdl",
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

struct ConfigurationDatabase {
	string name = null;

	bool doNotCollect = false;
	string[] unitPaths = null;

	string[] ignore = null;
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

	const db = loadDatabase();
	if (db.name != "") {
		result.name = db.name;
	}
	else {
		result.name = baseName(".".asAbsolutePath).array;
	}

	// TODO

	if (!db.doNotCollect) {
		result.units = [collectBuildUnit(".")];
	}

	return result;
}

ConfigurationDatabase loadDatabase() {
	foreach (dbFileCandidate; Conventions.projectRootSentinelsPrimary) {
		if (File.exists(dbFileCandidate)) {
			return openAndDeserializeDatabase!ConfigurationDatabase(dbFileCandidate);
		}
	}

	return ConfigurationDatabase();
}

void writeMakefile(const Recipe recipe) {
	// TODO
	assert(false, "Not implemented.");
}

BuildUnit collectBuildUnit(string path) {
	import std.array : array;

	auto result = BuildUnit();

	result.name = path.asAbsolutePath.asNormalizedPath.array.baseName;

	auto sourceFiles = HashSet!str();
	auto importDirs = HashSet!str();
	auto stringDirs = HashSet!str();
	collectFilesByPurpose(
		path, sourceFiles, importDirs, stringDirs
	);

	result.paths.input.source = sourceFiles.toArray();
	result.paths.input.import_ = importDirs.toArray();
	result.paths.input.stringImport = stringDirs.toArray();

	return result;
}

private void collectFilesByPurpose(
	string path,
	ref HashSet!str sourceFiles,
	ref HashSet!str importDirs,
	ref HashSet!str stringDirs,
) @safe {
	import std.array : array;

	const pathBaseName = path.asAbsolutePath.asNormalizedPath.array.baseName;
	if (Conventions.stringImportCommonDirectories.contains(pathBaseName)) {
		stringDirs.ensureAdded(path);
	}

	() @trusted /* ← DMD < 2.114 */ {
		foreach (file; dirEntries(path, File.SpanMode.shallow)) {
			() @safe {
				if (file.isFile) {
					if (file.name.isDSourceFile) {
						string sourceCode = (() @trusted => cast(string) File.read(file.name))();
						const moduleName = parseModuleName(sourceCode);
						str importRoot;
						if (!determineModuleFileImportRoot(moduleName, file.name, importRoot)){
							assert(false, "`-mv` has not been implemented yet.");
						}

						importDirs.ensureAdded(importRoot);
						sourceFiles.ensureAdded(file.name);
						return;
					}
					if (file.name.isCSourceFile) {
						importDirs.ensureAdded(path);
						sourceFiles.ensureAdded(file.name);
						return;
					}

					if (file.name.isDImportFile) {
						string sourceCode = (() @trusted => cast(string) File.read(file.name))();
						const moduleName = parseModuleName(sourceCode);
						str importRoot;
						if (!determineModuleFileImportRoot(moduleName, file.name, importRoot)){
							assert(false, "`-mv` has not been implemented yet.");
						}

						importDirs.ensureAdded(importRoot);
						return;
					}

					if (file.name.isCIncludeFile) {
						importDirs.ensureAdded(path);
						return;
					}

					if (Conventions.stringImportDirectorySentinels.contains(file.name)) {
						stringDirs.ensureAdded(path);
						return;
					}

					const fileExt = file.name.extension;
					if (Conventions.stringImportFileExtensions.contains(fileExt)) {
						stringDirs.ensureAdded(path);
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

private str findDirUpstream(string pathStartingPoint, const(string)[] needles) {
	static immutable parent = dirSeparator ~ "..";

	for (auto path = appender!string(pathStartingPoint); !isRoot(path.data); path ~= parent) {
		foreach (needle; needles) {
			bool found = false;
			auto filePath = path.data.buildPath(needle);
			try {
				found = File.exists(filePath);
			}
			catch (Exception) {
				continue;
			}

			if (found) {
				return path.data;
			}
		}
	}

	return null;
}

bool isRoot(str path) {
	import std.algorithm.comparison : cmp;

	const compared = cmp(
		chainPath(path, ".").asAbsolutePath.asNormalizedPath,
		chainPath(path, "..").asAbsolutePath.asNormalizedPath,
	);

	return (compared == 0);
}

private {
	alias fileExtensionOf = std.path.extension;
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

str pathSpliceTail(ref str path) @trusted {
	foreach_reverse (idx, c; path) {
		if (c.isDirSeparator) {
			const result = path.ptr[(idx + 1) .. path.length];
			path = path.ptr[0 .. idx];
			return result;
		}
	}

	const result = path;
	path = null;
	return result;
}

@safe unittest {
	str s0 = "foo/bar";
	assert(pathSpliceTail(s0) == "bar");
	assert(s0 == "foo");
	assert(pathSpliceTail(s0) == "foo");
	assert(s0 == "");

	str s1 = "foo/bar/foobar";
	assert(pathSpliceTail(s1) == "foobar");
	assert(s1 == "foo/bar");
	assert(pathSpliceTail(s1) == "bar");
	assert(s1 == "foo");

	str s2 = "";
	assert(pathSpliceTail(s2) == "");
	assert(s2 == "");

	str s3 = "/";
	assert(pathSpliceTail(s3) == "");
	assert(s3 == "");
}

bool determineModuleFileImportRoot(const(str)[] identifiers, str path, out str result) {
	assert(identifiers.length >= 1);

	const bn = baseName!(CaseSensitive.no)(path, ".d");
	if (bn != identifiers[$ - 1]) {
		return false;
	}
	identifiers = identifiers[0 .. ($ - 1)];

	auto p = pathSpliceTail(path);
	while ((path !is null) && (identifiers.length > 0)) {
		p = pathSpliceTail(path);
		if (p != identifiers[$ - 1]) {
			return false;
		}

		identifiers = identifiers[0 .. ($ - 1)];
	}

	if (identifiers.length > 0) {
		return false;
	}

	result = path;
	return true;
}

@safe unittest {
	str s;
	assert(determineModuleFileImportRoot(["foo", "bar"], "foo/bar.d", s));
	assert(s == "");

	assert(determineModuleFileImportRoot(["foo", "bar"], "src/foo/bar.d", s));
	assert(s == "src");

	assert(determineModuleFileImportRoot(["bar"], "src/bar.d", s));
	assert(s == "src");

	assert(determineModuleFileImportRoot(["bar"], "bar.d", s));
	assert(s == "");

	assert(!determineModuleFileImportRoot(["foo", "foo"], "src/foo.d", s));
	assert(!determineModuleFileImportRoot(["foo", "foo", "foo"], "foo/foo.d", s));
}
