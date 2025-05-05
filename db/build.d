import std.stdio;
import std.process;

void main() {
	auto dmd = execute(["dmd", "test.d", "sqlite.d"]);
	if (dmd.status != 0) writeln("Compilation failed:\n", dmd.output);
}
