/+
	This file is part of «mindybuild» — “an open-source build configuration and build system.”
	Copyright © 2026  Mindy Batek (0xEAB)

	This Source Code Form is subject to the terms of the Mozilla Public
	License, v. 2.0. If a copy of the MPL was not distributed with this
	file, You can obtain one at https://mozilla.org/MPL/2.0/.
 +/
/++
	fcompat — Forward compatibility shim
 +/
module mindybuild.fcompat;

public import std.file;
public import std.path;
import std.traits;

package(mindybuild):

auto asAbsolutePath(R)(R path) @trusted {
	return std.path.asAbsolutePath(path);
}

auto assumeNoGC(T)(T t) @system
if (isFunctionPointer!T || isDelegate!T) {
	enum attrs = functionAttributes!T | FunctionAttribute.nogc;
	return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs)) t;
}

auto assumePure(T)(T t) @system
if (isFunctionPointer!T || isDelegate!T) {
	enum attrs = functionAttributes!T | FunctionAttribute.pure_;
	return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs)) t;
}

auto dirEntries(string path, std.file.SpanMode mode, bool followSymlink = true) {
	static struct DirIterator {
		private {
			alias Impl = typeof(std.file.dirEntries(path, mode, followSymlink));
			Impl _impl;
		}

		this(Impl impl) @trusted {
			_impl = impl;
		}

		@property bool empty() @trusted {
			return _impl.empty;
		}

		@property DirEntry front() @trusted {
			return DirEntry(_impl.front);
		}

		void popFront() @trusted {
			_impl.popFront();
		}
	}

	return DirIterator(std.file.dirEntries(path, mode, followSymlink));
}

struct DirEntry {
	import std.datetime;

	private {
		std.file.DirEntry _impl;
	}

	this(std.file.DirEntry impl) @safe pure nothrow @nogc {
		_impl = impl;
	}

	@property string name() @trusted {
		return _impl.name;
	}

	@property bool isDir() @trusted {
		return _impl.isDir;
	}

	@property bool isFile() @trusted {
		return _impl.isFile;
	}

	@property bool isSymlink() @trusted {
		return _impl.isSymlink;
	}

	@property ulong size() {
		return _impl.size;
	}

	@property SysTime timeLastAccessed() @trusted {
		return _impl.timeLastAccessed;
	}

	@property SysTime timeLastModified() @trusted {
		return _impl.timeLastModified;
	}

	@property SysTime timeStatusChanged() {
		return _impl.timeStatusChanged;
	}
}
