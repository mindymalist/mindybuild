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
import File = std.file;

int run(string[] args) {
	auto abstractRecipe = loadAndAnalyzeRecipe();
	auto recipe = transformRecipe(abstractRecipe);
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
	}
}

AbstractRecipe loadAndAnalyzeRecipe() {
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
		assert(false);
	}

	auto rhsValue = new ValueExpression();
	rhsValue.data = ValueExpression.Data(rhsCall);

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
	engine.register("collect", wrapFunctions!autocollect);
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

Recipe transformRecipe(AbstractRecipe abstractRecipe) {
	// TODO
	assert(false, "TODO");
}

struct Recipe {
	// dfmt off
	Paths paths = Paths(
		prefix: ".",
		bin: "$(prefix)/bin",
		lib: "$(prefix)/lib",
	);
	// dfmt on

	BuildUnit[] units = null;
}

struct Paths {
	str prefix = null;
	str bin = null;
	str lib = null;
}

struct BuildUnit {
	Paths paths;
}

struct ProjectRoot {
	str path;
	str recipeFilename;

@safe pure nothrow @nogc:

	bool hasRecipeFile() const {
		return (recipeFilename !is null);
	}
}

@safe:

LiteralExpression collect(LiteralExpression options) {
	return null;
}

LiteralExpression autocollect() {
	auto target = new StringLiteralExpression();
	target.value = determineAutocollectTarget();
	return collect(target);
}

private str determineAutocollectTarget() {
	const recipeDir = findProjectDir(".");
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
		const stripped = stripDrive(path.asAbsolutePath.asNormalizedPath.array);
		return ((stripped == `\`) || (stripped == ""));
	}
}
