/+
	This file is part of «mindybuild» — “an open-source build configuration and build system.”
	Copyright © 2026  Mindy Batek (0xEAB)

	This Source Code Form is subject to the terms of the Mozilla Public
	License, v. 2.0. If a copy of the MPL was not distributed with this
	file, You can obtain one at https://mozilla.org/MPL/2.0/.
 +/
/++
	Common library of mindybuild.
 +/
module mindybuild.common;

///
alias str = const(char)[];

///
enum Status : bool {
	///
	error = false,
	///
	success = true,
}

pragma(inline, true) @safe pure nothrow @nogc {
	///
	bool isOK(const Status status) @safe pure nothrow @nogc {
		return (status == Status.success);
	}

	///
	bool isError(const Status status) @safe pure nothrow @nogc {
		return !isOK(status);
	}
}

///
struct CodePrinter {
	import std.array : Appender;
	import std.conv : text;

	private {
		Appender!string _appender;
		size_t _indent;
		string _indentChar;
	}

	private template isString(T) {
		import std.traits : Unconst;

		enum bool isString = (is(Unconst!T == string) || is(T == str));
	}

@safe pure:

	public this(size_t indentationLevel, string indentationCharacter = "\t") {
		_indent = indentationLevel;
		_indentChar = indentationCharacter;
	}

	public this(string indentationCharacter, size_t indentationLevel = 0) {
		this(indentationLevel, indentationCharacter);
	}

	public {
		typeof(this) opOpAssign(string op : '~')(string value) {
			_appender.put(value);
			return this;
		}

		typeof(this) opOpAssign(string op : '~')(char value) {
			_appender.put(value);
			return this;
		}
	}

	public {
		/++
			Prints `prefix`, then advances identation by one.
		 +/
		void startBlock(string prefix, bool hasChildren) {
			this.print(prefix);
			if (hasChildren) {
				this.print("\n");
			}

			++_indent;
		}

		/++
			Retrogresses indentation by one, then prints `suffix`.
		 +/
		void endBlock(string suffix, bool hasChildren) {
			--_indent;

			if (hasChildren) {
				this.print("\n");
				this.printIdentation();
			}
			this.print(suffix);
		}

		/++
			Prints the indentation for a new line.
		 +/
		void printIdentation() {
			foreach (n; 0 .. _indent) {
				_appender.put(_indentChar);
			}
		}

		/++
			Prints the provided data immediately.
		 +/
		void print(Args...)(Args args) {
			foreach (arg; args) {
				static if (isString!(typeof(arg))) {
					_appender.put(arg);
				}
				else {
					_appender.put(text(arg));
				}
			}
		}

		/++
			Prints a new line at the current identation level.
		 +/
		void printLine(Args...)(Args args) {
			size_t reservation = (_indent * _indentChar.length);
			foreach (arg; args) {
				static if (isString!(typeof(arg))) {
					reservation += arg.length;
				}
			}

			_appender.reserve(reservation);
			printIdentation();
			foreach (arg; args) {
				static if (is(typeof(arg) == string)) {
					_appender.put(arg);
				}
				else {
					_appender.put(text(arg));
				}
			}
		}
	}

	public string toString() const {
		return _appender[];
	}
}

///
template TaggedUnion(Types...) {
	import std.meta : NoDuplicates, staticIndexOf;
	import std.traits : TemplateArgsOf;

	static assert(Types.length > 0, "Nonsensical union of no types.");
	static assert(Types.length <= ubyte.max, "Type count out of range.");
	static assert(is(NoDuplicates!Types == Types), "Duplicate types.");

	///
	struct TaggedUnion {
		public {
			alias Types = TemplateArgsOf!(typeof(this));
		}

		private {
			Storage _storage;
			ubyte _tag;
		}

		///
		public this(T)(T value)
		if (canHold!T) {
			this.set(value);
		}

		public {
			///
			auto opAssign(T)(auto ref T value)
			if (canHold!T) {
				this.set(value);
				return this;
			}

			///
			auto opAssign(typeof(this) value) @trusted {
				_tag = value._tag;
				_storage = value._storage;
				return this;
			}

			///
			auto opAssign(ref typeof(this) value) @trusted {
				_tag = value._tag;
				_storage = value._storage;
				return this;
			}
		}

		public {
			///
			enum bool canHold(T) = (staticIndexOf!(T, Types) >= 0);

			///
			private template indexOf(T)
			if (canHold!T) {
				enum ubyte indexOf = (staticIndexOf!(T, Types) & ubyte.max);
			}
		}

		public {
			///
			bool has(T)() const
			if (canHold!T) {
				pragma(inline, true);
				return (_tag == indexOf!T);
			}

			///
			inout(T) get(T)() inout @trusted
			if (canHold!T) {
				if (_tag != indexOf!T) {
					assert(false, "The requested type (" ~ T.stringof ~ ") is not held by this tagged union instance.");
				}

				return this.load!T();
			}

			///
			bool tryGet(T)(out T value) @trusted
			if (canHold!T) {
				const doesntHave = !this.has!T();
				if (doesntHave) {
					return false;
				}

				value = this.load!T();
				return true;
			}

			///
			void set(T)(auto ref T value) @trusted
			if (canHold!T) {
				this.store(value);
			}
		}

		private {
			inout(T) load(T)() inout @system
			if (canHold!T) {
				return _storage.tupleof[indexOf!T];
			}

			void store(T)(auto ref T value) @trusted
			if (canHold!T) {
				_storage.tupleof[indexOf!T] = value;
				_tag = indexOf!T;
			}
		}

		private static union Storage {
			enum string memberName(size_t idx) = "value" ~ idx.stringof;

			static foreach (idx, T; Types) {
				mixin(`T ` ~ memberName!idx ~ `;`);
			}
		}
	}

}

///
enum BOM {
	///
	none,
	/// UTF-8
	utf8,
	/// UTF-16 Little Endian
	utf16LE,
	/// UTF-16 Big Endian
	utf16BE,
	/// UTF-32 Little Endian
	utf32LE,
	/// UTF-32 Big Endian
	utf32BE,
}

///
template bomData(BOM bom) {
	static if (bom == BOM.none) {
		///
		static immutable ubyte[0] bomData = [];
	}
	else static if (bom == BOM.utf8) {
		///
		static immutable ubyte[3] bomData = [0xEF, 0xBB, 0xBF];
	}
	else static if (bom == BOM.utf16LE) {
		///
		static immutable ubyte[2] bomData = [0xFF, 0xFE];
	}
	else static if (bom == BOM.utf16BE) {
		///
		static immutable ubyte[2] bomData = [0xFE, 0xFF];
	}
	else static if (bom == BOM.utf32LE) {
		///
		static immutable ubyte[4] bomData = [0xFF, 0xFE, 0x00, 0x00];
	}
	else static if (bom == BOM.utf32BE) {
		///
		static immutable ubyte[4] bomData = [0x00, 0x00, 0xFE, 0xFF];
	}
	else {
		static assert(false, "Unsupported charset.");
	}
}

///
BOM scanBOM(in str input) @safe pure nothrow @nogc {
	if (input.length >= 4) {
		const firstBytes = input[0 .. 4];
		if (firstBytes == bomData!(BOM.utf32LE)) {
			return BOM.utf32LE;
		}
		if (firstBytes == bomData!(BOM.utf32BE)) {
			return BOM.utf32BE;
		}
	}

	if (input.length >= 3) {
		const firstBytes = input[0 .. 3];
		if (firstBytes == bomData!(BOM.utf8)) {
			return BOM.utf8;
		}
	}

	if (input.length >= 2) {
		const firstBytes = input[0 .. 2];
		if (firstBytes == bomData!(BOM.utf16LE)) {
			return BOM.utf16LE;
		}
		if (firstBytes == bomData!(BOM.utf16BE)) {
			return BOM.utf16BE;
		}
	}

	return BOM.none;
}

/++
	Determines whether a string starts with a line terminator.

	Returns:
		The length of the line terminator, if applicable.
		Otherwise, a negative number.
 +/
ptrdiff_t scanEOL(in str s) @safe pure nothrow @nogc {
	if (s.length == 0) {
		return -1;
	}

	switch (s[0]) {
		case '\x0D':
			return ((s.length >= 2) && (s[1] == '\x0A')) ? 2 : 1;

		case '\x0A':
			return 1;

		case '\xE2':
			if (s.length < 3) {
				return -1;
			}
			if (s[1] == '\x80' && (s[2] == '\xA8' || s[2] == '\xA9')) {
				return 3;
			}
			return -1;

		default:
			break;
	}

	return -1;
}

///
ptrdiff_t indexOfNextEOL(in str input) @safe pure nothrow @nogc {
	foreach (idx, c; input) {
		const length = scanEOL(input[idx .. $]);
		if (length >= 1) {
			return idx;
		}
	}

	return -1;
}

///
ptrdiff_t scanIdentifier(scope str input) @safe pure nothrow @nogc {
	import std.ascii : isAlphaNum;

	const originalLength = input.length;

	auto idx = 0;
	while (input.length > 0) {
		const c = input[0];

		if (c == '\\') {
			const ucn = scanUniversalCharacterName(input);
			if (ucn < 0) {
				return -1;
			}
			input = input[ucn .. $];
			idx += ucn;
			continue;
		}

		if ((ubyte(c) & ubyte(0b1111_0000)) == 0b1111_0000) {
			if (input.length < 4) {
				return -1;
			}
			input = input[4 .. $];
			idx += 4;
			continue;
		}
		if ((ubyte(c) & ubyte(0b1110_0000)) == 0b1110_0000) {
			if (input.length < 3) {
				return -1;
			}

			// EOL?
			if (c == '\xE2' && input[1] == '\x80' && (input[2] == '\xA8' || input[2] == '\xA9')) {
				return idx;
			}

			input = input[3 .. $];
			idx += 3;
			continue;
		}
		if ((ubyte(c) & ubyte(0b1100_0000)) == 0b1100_0000) {
			if (input.length < 2) {
				return -1;
			}
			input = input[2 .. $];
			idx += 2;
			continue;
		}
		if ((ubyte(c) & ubyte(0b1000_0000)) == 0b1000_0000) {
			// bad unicode
			return -1;
		}

		const bool isEnd = !(
			c.isAlphaNum || c == '_'
		);

		if (isEnd) {
			return idx;
		}

		input = input[1 .. $];
		++idx;
	}

	return originalLength;
}

///
ptrdiff_t scanUniversalCharacterName(in str input) @safe pure nothrow @nogc {
	import std.ascii : isHexDigit;

	if (input.length < 2) {
		return -1;
	}

	if (input[1] == 'u') {
		if (input.length < (2 + 4)) {
			return -1;
		}

		foreach (c; input[2 .. 2 + 4]) {
			if (!c.isHexDigit) {
				return -1;
			}
		}

		return 4;
	}

	if (input[1] == 'U') {
		if (input.length < (2 + 8)) {
			return -1;
		}

		foreach (c; input[2 .. 2 + 8]) {
			if (!c.isHexDigit) {
				return -1;
			}
		}

		return 8;
	}

	return -1;
}

ptrdiff_t scanLineComment(in str input) @safe pure nothrow @nogc {
	if (input.length < 2 || input[0 .. 2] != "//") {
		return -1;
	}

	if (input.length == 2) {
		return 2;
	}

	const idxEOL = input.indexOfNextEOL();
	const length = (idxEOL < 0) ? input.length : idxEOL;
	return length;
}

ptrdiff_t scanAsteriskComment(in str input) @safe pure nothrow @nogc {
	if (input.length < 2 || input[0 .. 2] != "/*") {
		return -1;
	}

	if (input.length == 2) {
		return 2;
	}

	bool prevWasAsterisk = false;
	foreach (idx, c; input[2 .. $]) {
		if (prevWasAsterisk && (c == '/')) {
			return 2 + idx + 1;
		}
		prevWasAsterisk = (c == '*');
	}

	return input.length;
}

///
ptrdiff_t scanNestableComment(in str input) @safe pure nothrow @nogc {
	if (input.length < 2 || input[0 .. 2] != "/+") {
		return -1;
	}

	if (input.length == 2) {
		return 2;
	}

	size_t level = 1;

	bool prevWasPlus = false;
	bool prevWasSlash = false;
	foreach (idx, c; input[2 .. $]) {
		bool isSlash = (c == '/');
		bool isPlus = false;
		if (prevWasPlus && isSlash) {
			--level;
			isSlash = false;
		}
		else {
			isPlus = (c == '+');
			if (prevWasSlash && isPlus) {
				++level;
				isPlus = false;
			}
		}

		if (level == 0) {
			return 2 + idx + 1;
		}

		prevWasPlus = isPlus;
		prevWasSlash = isSlash;
	}

	return input.length;
}

///
ptrdiff_t scanWhitespace(in str input) @safe pure nothrow @nogc {
	foreach (idx, c; input) {
		switch (c) {
			case '\x20':
			case '\x09':
			case '\x0B':
			case '\x0C':
				continue;

			default:
				return idx;
		}
	}

	return -1;
}

///
struct Location {
	///
	str file;

	///
	size_t byteOffset;

	///
	str sourceCode;

	LocationHumanReadable humanReadable() const @safe pure {
		return LocationHumanReadable.fromLocation(this);
	}
}

///
struct LocationHumanReadable {
	///
	str file;

	///
	size_t line;

	///
	size_t column;

	///
	static typeof(this) fromLocation(const Location location) @safe pure {
		import std.uni;

		size_t cntLine = 1;
		size_t cntColumn = 1;

		bool prevWasCR = false;

		size_t offset = 0;

		foreach (g; location.sourceCode.byGrapheme) {
			offset += g.length;
			if (offset >= location.byteOffset) {
				return typeof(this)(location.file, cntLine, cntColumn);
			}

			if (g.length == 1) {
				if (g[0] == '\x0A') {
					if (prevWasCR) {
						prevWasCR = false;
						continue;
					}

					++cntLine;
					cntColumn = 1;
					continue;
				}

				if (g[0] == '\x0D') {
					++cntLine;
					cntColumn = 1;
					prevWasCR = true;
					continue;
				}
			}

			if (g[] == "\u2028" || g[] == "\u2029") {
				++cntLine;
				cntColumn = 1;
				continue;
			}

			prevWasCR = false;
			++cntColumn;
		}

		return typeof(this)(location.file, cntLine, cntColumn);
	}

	string toString() const @safe pure nothrow {
		import std.conv : text;

		return text(file, "(", line, ",", column, ")");
	}
}

///
bool contains(H, N)(H haystack, N needle) {
	version (LDC) {
		pragma(inline, true);
	}

	foreach (item; haystack) {
		if (item == needle) {
			return true;
		}
	}

	return false;
}

///
ptrdiff_t indexOf(H, N)(H haystack, N needle) {
	version (LDC) {
		pragma(inline, true);
	}

	foreach (idx, item; haystack) {
		if (item == needle) {
			return idx;
		}
	}

	return -1;
}

///
void sliceOffLast(T)(ref T[] data) @trusted pure nothrow @nogc {
	version (LDC) {
		pragma(inline, true);
	}

	if (data.length == 0) {
		return;
	}

	const last = -1 + data.length;
	data = data.ptr[0 .. last];
}

///
void removeSplice(T)(ref T[] data, size_t indexOfElementToRemove) @trusted pure nothrow @nogc
in (indexOfElementToRemove < data.length, "Out of range.") {
	const last = -1 + data.length;

	if (indexOfElementToRemove < last) {
		for (size_t idx = indexOfElementToRemove; idx < last; ++idx) {
			data.ptr[idx] = data.ptr[idx + 1];
		}
	}

	sliceOffLast(data);
}

///
str[] splitArgsString(str argsString) @safe {
	import std.array : appender;

	char[] buffer = argsString.dup;

	auto result = appender!(str[]);
	for (ptrdiff_t cursor = 0; cursor < buffer.length; ++cursor) {
		const char c = (() @trusted => buffer.ptr[cursor])();

		switch (c) {
			case '\\':
				buffer.removeSplice(cursor);
				++cursor;
				break;

			case ' ':
				result ~= (() @trusted => buffer.ptr[0 .. cursor])();
				buffer = (() @trusted => buffer.ptr[(cursor + 1) .. buffer.length])();
				break;

			case '\'':
				buffer.removeSplice(cursor);
				const restBuffer = (() @trusted => buffer.ptr[cursor .. buffer.length])();
				auto endOfQuotedString = restBuffer.indexOf('\'');
				if (endOfQuotedString < 0) {
					endOfQuotedString = restBuffer.length;
				}
				else {
					buffer.removeSplice(cursor + endOfQuotedString);
				}
				break;

			case '"':
				buffer.removeSplice(cursor);

				for (; cursor < buffer.length; ++cursor) {
					const cq0 = (() @trusted => buffer.ptr[cursor])();

					if (cq0 == '\"') {
						buffer.removeSplice(cursor);
						break;
					}

					if (cq0 == '\\') {
						const cursorNext = (cursor + 1);
						if (cursorNext >= buffer.length) {
							break;
						}

						const cq1 = (() @trusted => buffer.ptr[cursorNext])();
						const specialMeaning = ((cq1 == '\\') || (cq1 == '\"'));
						if (specialMeaning) {
							buffer.removeSplice(cursor);
						}
					}
				}
				break;

			default:
				break;
		}
	}

	if (buffer.length > 0) {
		result ~= buffer;
	}

	return result[];
}
