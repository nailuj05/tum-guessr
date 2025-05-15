module logger;

import std.logger;
import std.stdio;

import serverino;

private FileLogger _flogger;

@property FileLogger flogger() { return _flogger; }

shared static this() {
	writeln("logger started");
	_flogger = new FileLogger("logs/log.txt");
}
