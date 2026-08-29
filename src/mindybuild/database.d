/+
	This file is part of «mindybuild» — “an open-source build configuration and build system.”
	Copyright © 2026  Mindy Batek (0xEAB)

	This Source Code Form is subject to the terms of the Mozilla Public
	License, v. 2.0. If a copy of the MPL was not distributed with this
	file, You can obtain one at https://mozilla.org/MPL/2.0/.
 +/
/++
	mindybuild.database — Text-based storage engine
 +/
module mindybuild.database;

import mindybuild.common;
import std.array;
import std.conv;
import std.stdio;

DatabaseFile* openDatabaseFile(string filePath) {
	return new DatabaseFile(filePath);
}

private Database openDatabase(char[] data) @trusted {
	auto entries = Parser(Lexer(data)).array;
	auto index = Database.buildIndex(entries);
	return Database(entries, index);
}

///
alias DatabaseValue = TaggedUnion!(
	bool,
	string,
	string[],
);

private struct Entry {
	string key;
	DatabaseValue value;
}

struct DatabaseFile {
	private {
		File _file;
		Database _db;
	}

	private this(string filePath) @safe {
		_file = File(filePath, "a+");
		(() @trusted => _file.lock())();

		_file.rewind();
		auto buffer = new ubyte[](_file.size);
		buffer = _file.rawRead(buffer);

		() @trusted {
			auto entries = Parser(Lexer(cast(char[]) buffer)).array();
			auto index = Database.buildIndex(entries);
			_db = Database(entries, index);
		}();
	}

	@disable this(this);

	public ~this() {
		if (!_file.isOpen) {
			return;
		}
		_file.flush();
		_file.reopen(null, "w+");
		_file.rewind();
		_db.toString(&_file.lockingBinaryWriter.rawWrite!(const(char)));
		_file.unlock();
	}
}

///
struct Database {

	private {
		alias Index = Entry*[string];

		Entry[] _data;
		Index _index;
	}

	///
	private this(Entry[] data, Index index) @safe pure nothrow @nogc {
		_data = data;
		_index = index;
	}

	///
	private this(Entry[] data) @safe pure {
		_data = data;
		this.rebuildIndex();
	}

	///
	@disable this(this);

	public @safe pure nothrow @nogc {
		///
		bool has(str key) const {
			return ((key in _index) !is null);
		}

		///
		inout(DatabaseValue) get(str key) inout {
			return _index[key].value;
		}

		///
		bool tryGet(str key, out DatabaseValue result) {
			auto ptr = key in _index;

			if (ptr is null) {
				return false;
			}

			result = (**ptr).value;
			return true;
		}
	}

	public @safe pure nothrow @nogc {
		const(Entry)[] opSlice() const {
			return _data[];
		}
	}

	public @safe pure {
		///
		void insert(string key, DatabaseValue value) @trusted {
			if (key in _index) {
				throw new DatabaseException("Cannot insert entry `" ~ key ~ "`: Key is already in use.");
			}

			_data ~= Entry(key, value);
			_index[key] = &_data[$ - 1];
		}

		///
		void update(string key, DatabaseValue value) {
			auto ptr = key in _index;

			if (ptr is null) {
				throw new DatabaseException("Cannot update entry `" ~ key ~ "`: Entry does not exist.");
			}

			(**ptr).value = value;
		}

		///
		void set(string key, DatabaseValue value) {
			auto ptr = key in _index;

			if (ptr is null) {
				_data ~= Entry(key, value);
				_index[key] = &_data[$ - 1];
			}

			(**ptr).value = value;
		}

		/// ditto
		void set(str key, DatabaseValue value) {
			return this.set(key.idup, value);
		}
	}

	public @safe {
		void toString(void delegate(string) @safe sink) const {
			sink("# com.mindymalist.mindybuild.database\n");

			foreach (entry; _data) {
				entry.key.writeTo(sink);
				sink(": ");

			}
		}

		string toString() const {
			auto result = appender!string;
			this.toString(&result.put!string);
			return result[];
		}
	}

	private @safe pure {
		static Index buildIndex(Entry[] data) @system {
			Index result;

			foreach (ref entry; data) {
				if (entry.key in result) {
					throw new DatabaseException("Duplicate key `" ~ entry.key ~ "`.");
				}
				result[entry.key] = &entry;
			}

			return result;
		}

		void rebuildIndex() @trusted {
			_index = buildIndex(_data);
		}
	}
}

///
class DatabaseException : Exception {
	private this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow @nogc {
		super(msg, file, line);
	}
}

///
final class UnexpectedTokenException : DatabaseException {
	private this(
		in Lexer.Token actual,
		string expected,
		string file = __FILE__, size_t line = __LINE__
	) @safe pure nothrow {
		bool shallPrintData(Lexer.Token.Type type) {
			switch (type) with (Lexer.Token.Type) {
				case braceSquareClose:
				case braceSquareOpen:
				case eol:
				case literalBoolFalse:
				case literalBoolTrue:
					return false;

				default:
					break;
			}

			return true;
		}

		const printData = shallPrintData(actual.type);
		// dfmt off
		const unexpectedThing = (printData)
			? actual.type.name ~ " `" ~ (() @trusted => cast(string) actual.data)() ~ "`"
			: actual.type.name;
		// dfmt on
		const msg = "Corrupt database file: Unexpected " ~ unexpectedThing ~ "; " ~ expected ~ " expected.";

		super(msg, file, line);
	}
}

///
final class UnexpectedEndOfFileException : DatabaseException {
	private this(
		string expected,
		string file = __FILE__, size_t line = __LINE__
	) @safe pure nothrow {
		const msg = "Corrupt database file: Unexpected end of file; " ~ expected ~ " expected.";
		super(msg, file, line);
	}

	private this(
		string file = __FILE__, size_t line = __LINE__,
		string msg,
	) @safe pure nothrow @nogc {
		super(msg, file, line);
	}

	private static typeof(this) make(
		Lexer.Token.Type expected,
	)(
		string file = __FILE__, size_t line = __LINE__
	) @safe pure nothrow {
		static immutable msg = "Corrupt database file: Unexpected end of file; " ~ expected.name ~ " expected.";
		return new typeof(this)(file, line, msg);
	}
}

private void writeTo(string value, void delegate(string) @safe sink) @safe {
	static bool needsEscaping(string value) {
		foreach (c; value) {
			if (c == '"') {
				return true;
			}
			if (c == '\\') {
				return true;
			}
		}

		return false;
	}

	sink("\"");

	if (needsEscaping(value)) {
		do {
			foreach (idx, c; value) {
				if (c == '\\') {
					const toFlush = (() @trusted => value.ptr[0 .. idx])();
					sink(toFlush);
					sink(`\\`);
					value = (() @trusted => value.ptr[(idx + 1) .. value.length])();
					break;
				}
				if (c == '"') {
					const toFlush = (() @trusted => value.ptr[0 .. idx])();
					sink(toFlush);
					sink(`\"`);
					value = (() @trusted => value.ptr[(idx + 1) .. value.length])();
					break;
				}

				if ((idx + 1) == value.length) {
					sink(value);
				}
			}
		}
		while (value.length > 0);
	}
	else {
		sink(value);
	}

	sink("\"");
}

private void writeTo(bool value, void delegate(string) @safe sink) @safe {
	const s = (value) ? "true" : "false";
	sink(s);
}

private void writeTo(string[] value, void delegate(string) @safe sink) @safe {
	sink("[");

	foreach (idx, v; value) {
		v.writeTo(sink);

		if ((idx + 1) == value.length) {
			break;
		}
		sink(", ");
	}

	sink("]");
}

private void writeTo(DatabaseValue value, void delegate(string) @safe sink) @safe {
	string valueString;
	if (value.tryGet(valueString)) {
		return valueString.writeTo(sink);
	}

	bool valueBool;
	if (value.tryGet(valueBool)) {
		return valueBool.writeTo(sink);
	}

	string[] valueArray;
	if (value.tryGet(valueArray)) {
		return valueArray.writeTo(sink);
	}

	assert(false, "Unsupported union type.");
}

private struct Parser {
	private {
		Lexer _lexer;
		Entry _front;
	}

	public this(Lexer lexer) @safe pure {
		_lexer = lexer;
		this.loadFront();
	}

	public @safe pure {
		bool empty() {
			return _lexer.empty;
		}

		Entry front() {
			return _front;
		}

		void popFront() {
			this.loadFront();
		}

		private void loadFront() {
			alias Type = Lexer.Token.Type;

			_lexer.skipComments();

			if (_lexer.empty) {
				return;
			}

			if (_lexer.front.type != Type.literalString) {
				throw new UnexpectedTokenException(_lexer.front, Type.literalString.name);
			}
			const key = (() @trusted => cast(string) _lexer.front.data)();

			_lexer.popFront();
			if (_lexer.empty) {
				throw UnexpectedEndOfFileException.make!(Type.colon)();
			}

			if (_lexer.front.type != Type.colon) {
				throw new UnexpectedTokenException(_lexer.front, Type.colon.name);
			}

			_lexer.popFront();
			if (_lexer.empty) {
				throw new UnexpectedEndOfFileException("literal");
			}

			DatabaseValue value;

			switch (_lexer.front.type) {
				case Type.literalString:
					const dat = (() @trusted => cast(string) _lexer.front.data)();
					value = DatabaseValue(dat);
					_lexer.popFront();
					break;

				case Type.literalBoolFalse:
					value = DatabaseValue(false);
					_lexer.popFront();
					break;

				case Type.literalBoolTrue:
					value = DatabaseValue(true);
					_lexer.popFront();
					break;

				case Type.braceSquareOpen:
					value = DatabaseValue(this.parseArray());
					break;

				default:
					throw new UnexpectedTokenException(_lexer.front, "literal");
			}

			if (_lexer.empty) {
				throw UnexpectedEndOfFileException.make!(Type.eol)();
			}

			_front = Entry(key, value);
		}

		private string[] parseArray() {
			alias Type = Lexer.Token.Type;

			assert(_lexer.front.type == Type.braceSquareOpen);
			_lexer.popFront();

			if (_lexer.empty) {
				throw UnexpectedEndOfFileException.make!(Type.eol)();
			}
			if (_lexer.front.type != Type.eol) {
				throw new UnexpectedTokenException(_lexer.front, Type.eol.name);
			}
			_lexer.popFront();

			auto result = appender!(string[]);

			while (true) {
				if (_lexer.empty) {
					throw UnexpectedEndOfFileException.make!(Type.literalString)();
				}
				if (_lexer.front.type != Type.literalString) {
					throw new UnexpectedTokenException(_lexer.front, Type.literalString.name);
				}
				const value = (() @trusted => cast(string) _lexer.front.data)();
				_lexer.popFront();

				if (_lexer.empty) {
					throw UnexpectedEndOfFileException.make!(Type.braceSquareClose)();
				}
				if (_lexer.front.type != Type.eol) {
					throw new UnexpectedTokenException(_lexer.front, Type.eol.name);
				}
				_lexer.popFront();

				result ~= value;

				if (_lexer.empty) {
					throw UnexpectedEndOfFileException.make!(Type.braceSquareClose)();
				}
				if (_lexer.front.type == Type.braceSquareClose) {
					_lexer.popFront();
					break;
				}
			}

			return result[];
		}
	}
}

private struct Lexer {

	private {
		char[] _data;
		Token _front;
	}

	public this(char[] data) @safe pure {
		_data = data;
		this.popFront();
	}

	public @safe pure {
		bool empty() const {
			return (_data is null);
		}

		inout(Token) front() inout {
			return _front;
		}

		void popFront() {
			if (_data.length == 0) {
				_data = null;
			}

			_front = this.loadFront();
		}

		void skipComments() {
			for (; !this.empty; this.popFront()) {
				const skip = ((_front.type == Token.Type.comment) || (_front.type == Token.Type.eol));
				if (!skip) {
					return;
				}
			}
		}
	}

	private @safe pure {
		Token makeToken(Token.Type type, size_t length) @nogc {
			auto result = Token(type, _data[0 .. length]);
			_data = _data[length .. $];
			return result;
		}

		Token loadFront() {
			if (_data.length == 0) {
				return Token(Token.Type.invalid, null);
			}

			const c = (() @trusted => _data.ptr[0])();
			switch (c) {
				case '\n':
					return this.makeToken(Token.Type.eol, 1);

				case '#':
					return this.lexComment();

				case ':':
					return this.makeToken(Token.Type.colon, 1);

				case '[':
					return this.makeToken(Token.Type.braceSquareOpen, 1);

				case ']':
					return this.makeToken(Token.Type.braceSquareClose, 1);

				case '"':
					return this.lexString();

				case 'f':
					return this.lexBool!false();

				case 't':
					return this.lexBool!true();

				default:
					throw new DatabaseException("Corrupt database file: Unexpected character `" ~ c ~ "`.");
			}
		}

		Token lexBool(bool value)() {
			static immutable keyword = (value) ? "true" : "false";

			if (_data.length < keyword.length) {
				const dat = (() @trusted => cast(string) _data)();
				const msg = "Corrupt database file: Unexpected sequence `" ~ dat ~ "`; `" ~ keyword ~ "` expected.";
				throw new DatabaseException(msg);
			}

			const haystack = (() @trusted => _data.ptr[0 .. keyword.length])();
			if (haystack != keyword) {
				const dat = (() @trusted => cast(string) haystack)();
				const msg = "Corrupt database file: Unexpected sequence `" ~ dat ~ "`; `" ~ keyword ~ "` expected.";
				throw new DatabaseException(msg);
			}

			enum type = (value) ? Token.Type.literalBoolTrue : Token.Type.literalBoolFalse;
			return this.makeToken(type, keyword.length);
		}

		Token lexComment() {
			foreach (idx, c; _data) {
				if (c == '\n') {
					return this.makeToken(Token.Type.comment, idx);
				}
			}

			return this.makeToken(Token.Type.comment, _data.length);
		}

		Token lexString() {
			_data = _data[1 .. $];

			for (size_t idx = 0; idx < _data.length; ++idx) {
				const c = (() @trusted => _data.ptr[idx])();

				if (c == '\\') {
					_data.removeSplice(idx);
				}
				else if (c == '"') {
					const value = (() @trusted => _data.ptr[0 .. idx])();
					auto result = Token(Token.Type.literalString, value);
					_data = (() @trusted => _data.ptr[(idx + 1) .. _data.length])();
					return result;
				}
			}

			throw new DatabaseException("Corrupt database file: Unterminated string literal.");
		}
	}

	static struct Token {
		Type type;
		const(char)[] data;

		enum Type {
			invalid,
			eol,
			comment,
			colon,
			literalString,
			literalBoolFalse,
			literalBoolTrue,
			braceSquareOpen,
			braceSquareClose,
		}
	}
}

private string name(in Lexer.Token.Type type) @safe pure nothrow @nogc {
	final switch (type) with (Lexer.Token.Type) {
		case invalid:
			return "error";
		case eol:
			return "end of line";
		case comment:
			return "comment";
		case colon:
			return "colon";
		case literalString:
			return "string literal";
		case literalBoolFalse:
		case literalBoolTrue:
			return "bool literal";
		case braceSquareOpen:
			return "opening square brace";
		case braceSquareClose:
			return "closing square brace";
	}
}

@safe unittest {
	char[] src = `# com.mindymalist.mindybuild.database
"foo":"bar"
"foobar":"foo
bar"
"array":[
"10"
"40"
"2000"
]
"bool[0]":false
"bool[1]":true
`.dup;

	auto db = openDatabase(src);
	assert(db.has("foo"));
	assert(!db.has("bar"));
	assert(db.has("foobar"));
	assert(db.has("array"));
	assert(db.has("bool[0]"));
	assert(db.has("bool[1]"));
	assert(db.get("foo") == DatabaseValue("bar"));
	assert(db.get("foobar") == DatabaseValue("foo\nbar"));
	assert(db.get("array") == DatabaseValue(["10", "40", "2000"]));
	assert(db.get("bool[0]") == DatabaseValue(false));
	assert(db.get("bool[1]") == DatabaseValue(true));
}
