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

		bool empty() {
			return (_length == 0);
		}

		auto front() {
			return _data.front;
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

			void popFront() @system
			in (!empty) {
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
			bool empty() const {
				return _data.empty;
			}

			char front() const @system {
				return _data.front;
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
			size_t _nextSeparator;
		}

	@safe pure nothrow @nogc:

		public this(Phase1 data) @trusted {
			_data = data;
			_nextSeparator = 0;
			this.loadFront();
		}

		public this(str data) {
			this(data.Phase0.Phase1);
		}

		public {
			bool empty() const {
				return (_nextSeparator == 0);
			}

			SubRange!Phase1 front() const {
				return SubRange!Phase1(_data, _nextSeparator);
			}

			void popFront() @system {
				for (typeof(_nextSeparator) n = 0; n < _nextSeparator; ++n) {
					_data.popFront();
				}

				if (_data.empty) {
					_nextSeparator = 0;
					return;
				}

				// pop separator, too
				_data.popFront();

				this.loadFront();
			}

			private void loadFront() @trusted {
				size_t n = 0;
				foreach (c; _data.save) {
					if (c == directorySeparator) {
						_nextSeparator = n;
						return;
					}

					++n;
				}
				_nextSeparator = n;
			}

			typeof(this) save() {
				return this;
			}
		}
	}
}

@system unittest {
	import std.algorithm : cmp;

	alias Posix = RelativePathNormalizer!(Platform.posix);
	alias Win__ = RelativePathNormalizer!(Platform.windows);

	assert(0 == cmp(Posix.Phase0(`a/sd/f`), `a/sd/f`));
	assert(0 == cmp(Posix.Phase0(`a/sd/f/`), `a/sd/f/`));
	assert(0 == cmp(Posix.Phase0(`a\sd/f/`), `a\sd/f/`));
	assert(0 == cmp(Win__.Phase0(`a/sd/f`), `a\sd\f`));
	assert(0 == cmp(Win__.Phase0(`a\sd\f`), `a\sd\f`));
	assert(0 == cmp(Win__.Phase0(`a/sd\f`), `a\sd\f`));

	assert(0 == cmp(Posix.Phase1(`a//sd///f`), `a/sd/f`));
	assert(0 == cmp(Win__.Phase1(`a//sd///f`), `a\sd\f`));
	assert(0 == cmp(Win__.Phase1(`a\sd\\f\\`), `a\sd\f\`));
	assert(0 == cmp(Posix.Phase1(`a\sd\\f\\`), `a\sd\\f\\`));

	assert(0 == cmp(Posix.Phase2(`a/sd/f`), [`a`, `sd`, `f`]));
	assert(0 == cmp(Win__.Phase2(`a\sd\f`), [`a`, `sd`, `f`]));
	assert(0 == cmp(Posix.Phase2(`a/sd/f/`), [`a`, `sd`, `f`]));
	assert(0 == cmp(Win__.Phase2(`a\sd\f\`), [`a`, `sd`, `f`]));
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
