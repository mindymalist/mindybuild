/+
	This file is part of «mindybuild» — “an open-source build configuration and build system.”
	Copyright © 2026  Mindy Batek (0xEAB)

	This Source Code Form is subject to the terms of the Mozilla Public
	License, v. 2.0. If a copy of the MPL was not distributed with this
	file, You can obtain one at https://mozilla.org/MPL/2.0/.
 +/
/++
	Cross-platform path library.
 +/
module mindybuild.path;

import mindybuild.common;
import std.sumtype;

///
enum Platform {
	///
	posix,

	///
	windows,
}

private {
	version (Posix) {
		enum targetPlatform = Platform.posix;
	}
	else version (Windows) {
		enum targetPlatform = Platform.windows;
	}
}

private template SubRange(Range) {
	import std.range : isForwardRange;

	static assert(isForwardRange!Range);

	struct SubRange {
		private {
			Range _data;
			size_t _length;
		}

		this(Range data, size_t length) {
			_data = data.save;
			_length = length;
		}

		bool empty() const {
			return (_length == 0);
		}

		auto front() {
			return _data.front;
		}

		size_t length() const {
			return _length;
		}

		int opCmp(R)(R other) const {
			import std.algorithm : cmp;

			return cmp(this.save, other);
		}

		void popFront() {
			_data.popFront();
			--_length;
		}

		SubRange save() const {
			return this;
		}
	}
}

template RelativePathNormalizer(Platform platform) {

	static if (platform == Platform.posix) {
		///
		enum char directorySeparator = '/';
	}
	static if (platform == Platform.windows) {
		///
		enum char directorySeparator = '\\'; // @suppress(dscanner.suspicious.label_var_same_name)
	}

	struct Phase0 {
		private {
			str _data;
		}

	@safe pure nothrow @nogc:

		public this(str data) {
			_data = data;
		}

		public {
			char back() const @system {
				const c = _data.ptr[-1 + _data.length];
				static if (platform == Platform.windows) {
					if (c == '/') {
						return '\\';
					}
				}
				return c;
			}

			bool empty() const {
				return (_data.length == 0);
			}

			char front() const @system {
				const c = _data.ptr[0];
				static if (platform == Platform.windows) {
					if (c == '/') {
						return '\\';
					}
				}
				return c;
			}

			size_t length() const {
				return _data.length;
			}

			void popBack() @system {
				_data = _data.ptr[0 .. (-1 + _data.length)];
			}

			void popFront() @system {
				_data = _data.ptr[1 .. _data.length];
			}

			typeof(this) save() {
				return this;
			}
		}
	}

	struct Phase1 {
		private {
			Phase0 _data;
		}

	@safe pure nothrow @nogc:

		public this(Phase0 data) {
			_data = data;
		}

		public this(str data) {
			this(data.Phase0);
		}

		public {
			char back() const @system {
				return _data.back;
			}

			bool empty() const {
				return _data.empty;
			}

			char front() const @system {
				return _data.front;
			}

			size_t length() @trusted {
				size_t result = 0;
				for (auto rest = this.save; !rest.empty; rest.popFront()) {
					++result;
				}
				return result;
			}

			void popBack() @system {
				const prevWasDirectorySeparator = (_data.back == directorySeparator);

				_data.popBack();

				if (prevWasDirectorySeparator) {
					while (!_data.empty) {
						if (_data.back != directorySeparator) {
							break;
						}
						_data.popBack();
					}
				}
			}

			void popFront() @system {
				const prevWasDirectorySeparator = (_data.front == directorySeparator);

				_data.popFront();

				if (prevWasDirectorySeparator) {
					while (!_data.empty) {
						if (_data.front != directorySeparator) {
							break;
						}
						_data.popFront();
					}
				}
			}

			typeof(this) save() {
				return this;
			}
		}
	}

	struct Phase2 {
		private {
			Phase1 _data;
			size_t _nextFrontSeparator;
			size_t _nextBackSeparator;
		}

	@safe pure nothrow @nogc:

		public this(Phase1 data) @trusted {
			_data = data;
			this.loadFront();
			this.loadBack();
		}

		public this(str data) {
			this(data.Phase0.Phase1);
		}

		public {
			SubRange!Phase1 back() @trusted {
				size_t offset = -_nextBackSeparator + _data.length;
				auto clone = _data.save;
				for (size_t n = 0; n < offset; ++n) {
					clone.popFront();
				}
				return SubRange!Phase1(clone, _nextBackSeparator);
			}

			bool empty() const {
				return _data.empty;
			}

			SubRange!Phase1 front() const {
				return SubRange!Phase1(_data, _nextFrontSeparator);
			}

			size_t length() @trusted {
				size_t result = 0;
				for (auto rest = this.save; !rest.empty; rest.popFront()) {
					++result;
				}
				return result;
			}

			void popBack() @system {
				for (typeof(_nextBackSeparator) n = 0; n < _nextBackSeparator; ++n) {
					_data.popBack();
				}

				if (_data.empty) {
					return;
				}

				// pop separator, too
				_data.popBack();

				this.loadBack();
			}

			void popFront() @system {
				for (typeof(_nextFrontSeparator) n = 0; n < _nextFrontSeparator; ++n) {
					_data.popFront();
				}

				if (_data.empty) {
					return;
				}

				// pop separator, too
				_data.popFront();

				this.loadFront();
			}

			typeof(this) save() {
				return this;
			}
		}

		private {
			void loadBack() @trusted {
				size_t n = 0;
				foreach_reverse (c; _data.save) {
					if (c == directorySeparator) {
						_nextBackSeparator = n;
						return;
					}

					++n;
				}
				_nextBackSeparator = n;
			}
		}

		void loadFront() @trusted {
			size_t n = 0;
			foreach (c; _data.save) {
				if (c == directorySeparator) {
					_nextFrontSeparator = n;
					return;
				}

				++n;
			}
			_nextFrontSeparator = n;
		}
	}

	struct Phase3 {
		private {
			Phase2 _data;
		}

	@safe pure nothrow @nogc:

		public this(Phase2 data) @trusted {
			_data = data;
			this.loadFront();
			this.loadBack();
		}

		public this(str data) {
			this(data.Phase0.Phase1.Phase2);
		}

		public {
			SubRange!Phase1 back() @system {
				return _data.back;
			}

			bool empty() const {
				return _data.empty;
			}

			SubRange!Phase1 front() const @system {
				return _data.front;
			}

			void popBack() @system {
				_data.popBack();
				this.loadBack();
			}

			void popFront() @system {
				_data.popFront();
				this.loadFront();
			}

			typeof(this) save() {
				return this;
			}
		}

		private {
			void loadBack() @system {
				while (!_data.empty) {
					if ((_data.back.length == 1) && (_data.back.front == '.')) {
						_data.popBack();
						continue;
					}

					return;
				}
			}

			void loadFront() @system {
				while (!_data.empty) {
					if ((_data.front.length == 1) && (_data.front.front == '.')) {
						_data.popFront();
						continue;
					}

					return;
				}
			}
		}
	}

	struct Phase4 {
		private {
			Phase3 _data;
		}

	@safe pure nothrow @nogc:

		public this(Phase3 data) @trusted {
			_data = data;
			this.loadBack();
		}

		public this(str data) {
			this(data.Phase0.Phase1.Phase2.Phase3);
		}

		public {
			SubRange!Phase1 back() @system {
				return _data.back;
			}

			bool empty() const {
				return _data.empty;
			}

			void popBack() @system {
				_data.popBack();
				this.loadBack();
			}
		}

		private {
			void loadBack() @system {
				while (!_data.empty) {
					size_t toPop = 0;

					for (auto iterator = _data.save; !iterator.empty; iterator.popBack()) {
						if (!isDotDot(iterator.back)) {
							break;
						}
						++toPop;
					}

					toPop += toPop;
					auto bak = _data;
					for (size_t n = 0; n < toPop; ++n) {
						if (_data.empty) {
							_data = bak;
							return;
						}
						bak = _data;
						_data.popBack();
					}

					return;
				}
			}

			static bool isDotDot(SubRange!Phase1 dir) @system {
				if (dir.empty) {
					return false;
				}
				if (dir.front != '.') {
					return false;
				}
				dir.popFront();
				if (dir.empty) {
					return false;
				}
				if (dir.front != '.') {
					return false;
				}
				dir.popFront();
				if (!dir.empty) {
					return false;
				}
				return true;
			}
		}
	}

	struct Phase5 {
		private {
			Phase4 _data;
		}

	@safe pure nothrow @nogc:

		public this(Phase4 data) @trusted {
			_data = data;
		}

		public this(str data) {
			this(data.Phase0.Phase1.Phase2.Phase3.Phase4);
		}

		public {
			auto front() @system {
				return _data.back;
			}

			bool empty() const {
				return _data.empty;
			}

			void popFront() @system {
				_data.popBack();
			}
		}
	}
}

@system unittest {
	import std.algorithm : cmp;

	alias Posix = RelativePathNormalizer!(Platform.posix);
	alias Win__ = RelativePathNormalizer!(Platform.windows);

	// Phase 0
	assert(0 == cmp(Posix.Phase0(`a/sd/f`), `a/sd/f`));
	assert(0 == cmp(Posix.Phase0(`a/sd/f/`), `a/sd/f/`));
	assert(0 == cmp(Posix.Phase0(`a\sd/f/`), `a\sd/f/`));
	assert(0 == cmp(Win__.Phase0(`a/sd/f`), `a\sd\f`));
	assert(0 == cmp(Win__.Phase0(`a\sd\f`), `a\sd\f`));
	assert(0 == cmp(Win__.Phase0(`a/sd\f`), `a\sd\f`));

	// Phase 1
	assert(0 == cmp(Posix.Phase1(`a//sd///f`), `a/sd/f`));
	assert(0 == cmp(Win__.Phase1(`a//sd///f`), `a\sd\f`));
	assert(0 == cmp(Win__.Phase1(`a\sd\\f\\`), `a\sd\f\`));

	assert(0 == cmp(Posix.Phase1(`a\sd\\f\\`), `a\sd\\f\\`));

	// Phase 2
	assert(0 == cmp(Posix.Phase2(`a`), [`a`]));
	assert(0 == cmp(Win__.Phase2(`a`), [`a`]));

	assert(0 == cmp(Posix.Phase2(`a/`), [`a`]));
	assert(0 == cmp(Win__.Phase2(`a\`), [`a`]));

	assert(0 == cmp(Posix.Phase2(`a/sd/f`), [`a`, `sd`, `f`]));
	assert(0 == cmp(Win__.Phase2(`a\sd\f`), [`a`, `sd`, `f`]));

	assert(0 == cmp(Posix.Phase2(`a/sd/f/`), [`a`, `sd`, `f`]));
	assert(0 == cmp(Win__.Phase2(`a\sd\f\`), [`a`, `sd`, `f`]));

	// Phase 3
	assert(0 == cmp(Posix.Phase3(`.`), cast(string[])[]));
	assert(0 == cmp(Win__.Phase3(`.`), cast(string[])[]));

	assert(0 == cmp(Posix.Phase3(`./`), cast(string[])[]));
	assert(0 == cmp(Win__.Phase3(`.\`), cast(string[])[]));

	assert(0 == cmp(Posix.Phase3(`./.`), cast(string[])[]));
	assert(0 == cmp(Win__.Phase3(`.\.`), cast(string[])[]));

	assert(0 == cmp(Posix.Phase3(`././`), cast(string[])[]));
	assert(0 == cmp(Win__.Phase3(`.\.\`), cast(string[])[]));

	assert(0 == cmp(Posix.Phase3(`a/./sd/f`), [`a`, `sd`, `f`]));
	assert(0 == cmp(Win__.Phase3(`a\.\sd\f`), [`a`, `sd`, `f`]));

	assert(0 == cmp(Posix.Phase3(`./a/sd/f/`), [`a`, `sd`, `f`]));
	assert(0 == cmp(Win__.Phase3(`./a\sd\f\`), [`a`, `sd`, `f`]));

	assert(0 == cmp(Posix.Phase3(`a/./././sd/./f`), [`a`, `sd`, `f`]));
	assert(0 == cmp(Win__.Phase3(`a\.\.\.\sd\.\f`), [`a`, `sd`, `f`]));

	// Phase 4+5
	assert(0 == cmp(Posix.Phase5(`a/sd/../f`), [`f`, `a`]));
	assert(0 == cmp(Win__.Phase5(`a\sd\..\f`), [`f`, `a`]));
	assert(0 == cmp(Posix.Phase5(`a/./././sd/../f`), [`f`, `a`]));
	assert(0 == cmp(Win__.Phase5(`a\.\.\.\sd\..\f`), [`f`, `a`]));
	assert(0 == cmp(Posix.Phase5(`a/../z/0/../sd/../../f`), [`f`]));
	assert(0 == cmp(Win__.Phase5(`a\..\z\0\..\sd\..\..\f`), [`f`]));
}

///
class PathException : Exception {
	private this(
		string msg,
		string file = __FILE__, size_t line = __LINE__,
	) @safe pure nothrow @nogc {
		super(msg, file, line);
	}
}

final class BadPathException : PathException {
	///
	str path;

	private this(
		str path,
		string issue,
		string file = __FILE__, size_t line = __LINE__,
	) @safe pure nothrow {
		this.path = path;

		const msg = "Bad path `" ~ (() @trusted => cast(string) path)() ~ "`: " ~ issue;
		super(msg, file, line);
	}
}
