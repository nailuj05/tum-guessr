import std.stdio;
import std.format;
import sqlite : Database, Request;

void main(string[] args) {
	Database db = new Database("test.db");
	Request r;

	db.exec_imm("INSERT INTO test (line) VALUES ('oke?')");
	r = db.prepare_bind("INSERT INTO test (line) VALUES (?)", "nice");
	db.exec(r);

	auto rows = db.query_imm!(int, string)("SELECT * FROM test WHERE id < 10");
	foreach(row; rows) {
		writeln(format("Line %d: %s", row[0], row[1]));
	}
}
