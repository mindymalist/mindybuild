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

import mindybuild.annabel;
import mindybuild.common;
import mindybuild.kapenparse;
import std.conv;

import File = std.file;
import std.stdio : FileHandle = File;

int run(FileHandle stderr, string[] args) @safe {
	auto abstractRecipe = loadAndAnalyzeRecipe();
	stderr.writeln(abstractRecipe.data, "\n====");
	auto recipe = transformRecipe(abstractRecipe);
	stderr.writeln(recipe);
	return 1;
}

struct Conventions {
	static immutable {
		auto recipeFilename = "mindybuild.bel";

		auto projectRootSentinels = [
			".git",
			".gitignore",
			".hg",
			".hgignore",
			"dub.json",
			"dub.sdl",
		];

		auto stringImportFileExtensions = [
			".dt",
		];

		auto stringImportDirectorySentinels = [
			"dubhash.txt",
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

AbstractRecipe loadAndAnalyzeRecipe() @safe {
	const runningInProjectRoot = File.exists(Conventions.recipeFilename);
	if (!runningInProjectRoot) {
		return analyze(fallbackRecipe(FallbackRecipeType.recipeFileAbsent));
	}

	auto document = loadDocument(Conventions.recipeFilename);
	if (document.statements.length == 0) {
		return analyze(fallbackRecipe(FallbackRecipeType.recipeFileEmpty));
	}

	return analyze(document);
}

Document loadDocument(str path) @safe {
	const rawRecipe = (() @trusted => cast(string) File.read(path))();
	return parseDocument(rawRecipe, path);
}

enum FallbackRecipeType {
	error,
	recipeFileAbsent,
	recipeFileEmpty,
}

Statement fallbackRecipe(FallbackRecipeType type) @safe {
	auto lhsSelector = new SelectorExpression();
	lhsSelector.identifiers = ["units"];

	auto rhsSelector = new SelectorExpression();

	auto rhsCall = new CallExpression();
	rhsCall.functionName = rhsSelector;

	if (type == FallbackRecipeType.recipeFileAbsent) {
		rhsSelector.identifiers = ["autocollect"];
		rhsCall.parameters = [];
	}
	else if (type == FallbackRecipeType.recipeFileEmpty) {
		rhsSelector.identifiers = ["collect"];
		auto rhsCallParam0 = new StringLiteralExpression();
		rhsCallParam0.value = ".";
		auto rhsCallParam0Value = new ValueExpression();
		rhsCallParam0Value.data = ValueExpression.Data(rhsCallParam0);
		rhsCall.parameters = [rhsCallParam0Value];
	}
	else {
		assert(false, type.to!string());
	}

	auto rhsArray = new ArrayLiteralExpression();
	rhsArray.items ~= ValueExpression.pack(rhsCall);

	auto rhsValue = new ValueExpression();
	rhsValue.data = ValueExpression.Data(rhsArray);

	auto assignment = new AssignmentExpression();
	assignment.lhs = lhsSelector;
	assignment.rhs = rhsValue;

	auto statement = Statement(assignment);
	return statement;
}

AbstractRecipe analyze(Document document) @safe {
	return analyze(document.statements);
}

AbstractRecipe analyze(Statement[] statements) @safe {
	auto engine = makeEngine();
	foreach (statement; statements) {
		engine.execute(statement);
	}
	return AbstractRecipe(engine.data);
}

AbstractRecipe analyze(Statement statement) @safe {
	auto engine = makeEngine();
	engine.execute(statement);
	return AbstractRecipe(engine.data);
}

ExecutionEngine makeEngine() @safe {
	auto engine = new ExecutionEngine();

	engine.register("autocollect", wrapFunctions!autocollect);
	engine.register("collect", wrapFunctions!collect);
	engine.boot();

	return engine;
}

///
class AnalyzerException : Exception {
	public {
		///
		Location location;
	}

	private this(
		string message,
		Location location,
		string file = __FILE__, size_t line = __LINE__
	) @safe pure nothrow @nogc {
		this.location = location;
		super(message, file, line);
	}
}

///
struct AbstractRecipe {
	///
	ObjectLiteralExpression data;
}

Recipe transformRecipe(AbstractRecipe abstractRecipe) @safe {
	static void transformDC(ValueExpression[str] data, ref Recipe result, lazy string parent) {
		ValueExpression* dc = "dc" in data;
		if (dc is null) {
			return;
		}

		result.dCompiler = tryGetString(*dc, parent.buildPropertyPath("dc")).value;
	}

	static void transformInputPaths(ValueExpression[str] data, out InputPaths result, lazy string parent) {
		ValueExpression* paths = "paths" in data;
		if (paths is null) {
			return;
		}

		ObjectLiteralExpression collection = tryGetObject(*paths, "paths");

		ValueExpression* sourcePaths = "source" in collection.properties;
		ValueExpression* importPaths = "import" in collection.properties;
		ValueExpression* stringImportPaths = "string" in collection.properties;

		if (sourcePaths !is null) {
			auto pathsArray = tryGetArray(*sourcePaths, parent.buildPropertyPath("paths.source")).items;
			result.source.reserve(pathsArray.length);
			foreach (idx, path; pathsArray) {
				result.source ~= tryGetString(path, parent.buildPropertyPath(i"paths.source[$(idx)]".text)).value;
			}
		}
		if (importPaths !is null) {
			auto pathsArray = tryGetArray(*importPaths, parent.buildPropertyPath("paths.import")).items;
			result.source.reserve(pathsArray.length);
			foreach (idx, path; pathsArray) {
				result.import_ ~= tryGetString(path, parent.buildPropertyPath(i"paths.import[$(idx)]".text)).value;
			}
		}
		if (sourcePaths !is null) {
			auto pathsArray = tryGetArray(*stringImportPaths, parent.buildPropertyPath("paths.string")).items;
			result.source.reserve(pathsArray.length);
			foreach (idx, path; pathsArray) {
				result.stringImport ~= tryGetString(path, parent.buildPropertyPath(i"paths.string[$(idx)]".text)).value;
			}
		}
	}

	static void transformOutputPaths(ValueExpression[str] data, out OutputPaths result, lazy string parent) {
		ValueExpression* paths = "paths" in data;
		if (paths is null) {
			return;
		}

		ObjectLiteralExpression collection = tryGetObject(*paths, "paths");

		ValueExpression* prefix = "prefix" in collection.properties;
		ValueExpression* bin = "bin" in collection.properties;
		ValueExpression* lib = "lib" in collection.properties;

		if (prefix !is null) {
			result.prefix = tryGetString(*prefix, parent.buildPropertyPath("paths.prefix")).value;
		}
		if (bin !is null) {
			result.bin = tryGetString(*bin, parent.buildPropertyPath("paths.bin")).value;
		}

		if (lib !is null) {
			result.prefix = tryGetString(*lib, parent.buildPropertyPath("paths.lib")).value;
		}
	}

	static void transformUnit(ValueExpression[str] data, out BuildUnit result, lazy string parent) {
		ValueExpression* name = "name" in data;
		ValueExpression* dc = "dc" in data;
		ValueExpression* paths = "paths" in data;
		ValueExpression* dflags = "dflags" in data;

		if (name !is null) {
			result.name = tryGetString(*name, parent.buildPropertyPath("name")).value;
		}

		if (paths !is null) {
			transformInputPaths(data, result.paths.input, parent);
			transformOutputPaths(data, result.paths.output, parent);
		}

		if (dc !is null) {
			result.dCompiler = tryGetString(*dc, parent.buildPropertyPath("dc")).value;
		}

		if (dflags !is null) {
			ArrayLiteralExpression dflagsArray;
			StringLiteralExpression dflagsString;
			if ((*dflags).data.tryGet(dflagsArray)) {
				result.dflags = tryGetArrayOfStrings(dflagsArray, parent.buildPropertyPath("dflags"));
			}
			else if ((*dflags).data.tryGet(dflagsString)) {
				result.dflags = splitArgsString(dflagsString.value);
			}
			else {
				throw new BadRecipeValueException(
					parent.buildPropertyPath("dflags"),
					"Must be either an array or a string.",
					dflags.location,
				);	
			}
		}
	}

	static void transformUnits(ValueExpression[str] data, ref Recipe result) {
		ValueExpression* units = "units" in data;
		if (units is null) {
			return;
		}

		ArrayLiteralExpression unitsArray = tryGetArray(*units, "units");
		result.units.reserve(unitsArray.items.length);

		foreach (idx, unit; unitsArray.items) {
			auto unitData = tryGetObject(unit, i"units[$(idx)]".text).properties;

			BuildUnit buildUnit;
			transformUnit(unitData, buildUnit, i"units[$(idx)]".text);

			result.units ~= buildUnit;
		}
	}

	auto result = Recipe();
	transformDC(abstractRecipe.data.properties, result, null);
	transformOutputPaths(abstractRecipe.data.properties, result.paths, null);
	transformUnits(abstractRecipe.data.properties, result);
	return result;

	// TODO
	assert(false, "TODO");
}

struct Recipe {
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

struct ProjectRoot {
	str path;
	str recipeFilename;

@safe pure nothrow @nogc:

	bool hasRecipeFile() const {
		return (recipeFilename !is null);
	}
}

///
final class BadRecipeParameterException : BadRecipeException {
	public {
		///
		string functionName;

		///
		size_t index;
	}

	private this(
		string functionName,
		size_t index,
		string issue,
		Location location,
		string file = __FILE__, size_t line = __LINE__
	) @safe pure nothrow {
		this.functionName = functionName;
		this.index = index;

		const msg =
			"Unsupported value for parameter #" ~ index.to!string ~ " of function `" ~ functionName ~ "`: " ~ issue;
		super(msg, location, file, line);
	}
}

///
class BadRecipeException : Exception {
	public {
		///
		Location location;
	}

	private this(
		string message,
		Location location,
		string file = __FILE__, size_t line = __LINE__
	) @safe pure nothrow @nogc {
		this.location = location;
		super(message, file, line);
	}
}

///
final class BadRecipeValueException : BadRecipeException {
	public {
		///
		string property;
	}

	private this(
		string property,
		string issue,
		Location location,
		string file = __FILE__, size_t line = __LINE__
	) @safe pure nothrow {
		this.property = property;

		const msg = "Unsupported value for property `" ~ property ~ "`: " ~ issue;
		super(msg, location, file, line);
	}
}

@safe:

LiteralExpression collect(LiteralExpression pathExpr) {
	import std.array : array;
	import std.path;

	auto pathStringExpr = cast(StringLiteralExpression) pathExpr;
	if (pathStringExpr is null) {
		throw new BadRecipeParameterException("collect", 0, "String expected.", pathExpr.location);
	}

	const path = (() @trusted => cast(string) pathStringExpr.value)();
	const pathBaseName = path.asAbsolutePath.asNormalizedPath.array.baseName;

	ValueExpression[] sourceFiles;
	ValueExpression[] importDirs;
	ValueExpression[] stringDirs;
	collectFilesByPurpose(path, sourceFiles, importDirs, stringDirs);

	{
		auto result = new ObjectLiteralExpression();

		result.properties["name"] = ValueExpression.pack(pathBaseName);

		auto inputPaths = new ObjectLiteralExpression();
		inputPaths.properties["source"] = ValueExpression.pack(ArrayLiteralExpression.pack(sourceFiles));
		inputPaths.properties["import"] = ValueExpression.pack(ArrayLiteralExpression.pack(importDirs));
		inputPaths.properties["string"] = ValueExpression.pack(ArrayLiteralExpression.pack(stringDirs));
		result.properties["paths"] = ValueExpression.pack(inputPaths);

		return result;
	}
}

private void collectFilesByPurpose(
	string path,
	ref ValueExpression[] sourceFiles,
	ref ValueExpression[] importDirs,
	ref ValueExpression[] stringDirs,
) @safe {
	import std.array : array;
	import std.path;

	bool pathAsImportDirAdded = false;
	void addPathAsImportDir() {
		if (pathAsImportDirAdded) {
			return;
		}

		importDirs ~= ValueExpression.pack(path);
		pathAsImportDirAdded = true;
	}

	bool pathAsStringImportDirAdded = false;
	void addPathAsStringImportDir() {
		if (pathAsStringImportDirAdded) {
			return;
		}

		stringDirs ~= ValueExpression.pack(path);
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
					if (file.name.isDSourceFile || file.name.isCSourceFile) {
						sourceFiles ~= ValueExpression.pack(file.name);
						addPathAsImportDir();
						return;
					}

					if (file.name.isDImportFile || file.name.isCIncludeFile) {
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

LiteralExpression autocollect() {
	const target = determineAutocollectTarget();
	auto cwd = new StringLiteralExpression();
	cwd.value = ".";

	File.chdir(target);

	return collect(cwd);
}

private str determineAutocollectTarget() {
	const recipeDir = findRecipeDir(".");
	if (recipeDir !is null) {
		return recipeDir;
	}

	const projectDir = findProjectDir(".");
	if (projectDir !is null) {
		return projectDir;
	}

	return ".";
}

private str findRecipeDir(str pathStartingPoint) {
	return findDir(pathStartingPoint, Conventions.recipeFilename);
}

private str findProjectDir(str pathStartingPoint) {
	import std.meta;

	return findDir(pathStartingPoint, aliasSeqOf!(Conventions.projectRootSentinels));
}

private str findDir(Needles...)(const str pathStartingPoint, immutable Needles needles) {
	import std.path;

	size_t safetyMechanism = 0;

	str path = pathStartingPoint;
	do {
		if (++safetyMechanism >= 256) {
			assert(false, "Unrealistically deep nesting; potential recursion issue.");
		}

		foreach (needle; needles) {
			static assert(is(typeof(needle) == immutable(string)));

			bool found = false;
			try {
				const filePath = path.buildPath(Conventions.recipeFilename);
				found = File.exists(filePath);
			}
			catch (Exception) {
				return null;
			}

			if (found) {
				return pathStartingPoint;
			}
		}

		path = path.buildPath("..");
	}
	while (!path.isRoot);

	return null;
}

bool isRoot(str path) {
	import std.path;

	version (Posix) {
		import std.algorithm.comparison : cmp;

		return (cmp(path.asAbsolutePath.asNormalizedPath, "/") == 0);
	}
	version (Windows) {
		import std.array : array;

		const stripped = stripDrive(path.asAbsolutePath.asNormalizedPath.array);
		return ((stripped == `\`) || (stripped == ""));
	}
}

string buildPropertyPath(string parent, string child) {
	if (parent.length > 0) {
		return parent ~ "." ~ child;
	}

	return child;
}

ArrayLiteralExpression tryGetArray(ValueExpression expr, lazy string property) {
	ArrayLiteralExpression result;
	if (!expr.data.tryGet(result)) {
		throw new BadRecipeValueException(property, "Must be an array.", expr.location);
	}
	return result;
}

ObjectLiteralExpression tryGetObject(ValueExpression expr, lazy string property) {
	ObjectLiteralExpression result;
	if (!expr.data.tryGet(result)) {
		throw new BadRecipeValueException(property, "Must be an object.", expr.location);
	}
	return result;
}

StringLiteralExpression tryGetString(ValueExpression expr, lazy string property) {
	StringLiteralExpression result;
	if (!expr.data.tryGet(result)) {
		throw new BadRecipeValueException(property, "Must be a string.", expr.location);
	}
	return result;
}

str[] tryGetArrayOfStrings(ArrayLiteralExpression expr, lazy string property) {
	auto result = new str[](expr.items.length);
	foreach (idx, item; expr.items) {
		*(() @trusted => &result.ptr[idx])() = tryGetString(item, property ~ "[" ~ idx.to!string() ~ "]").value;
	}

	return result;
}

str[] tryGetArrayOfStrings(ValueExpression expr, lazy string property) {
	auto arrayExpr = tryGetArray(expr, property);
	return tryGetArrayOfStrings(arrayExpr, property);
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
