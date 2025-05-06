module app;

import std;
import std.stdio;
import std.format;
import simplesession;
import serverino;
import core.sync.mutex;

import sqlite;

mixin ServerinoMain;


@onServerInit ServerinoConfig configure(string[] args)
{
	Database db = new Database("test.db");
	db.exec_imm("CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY, line TEXT)");
	return ServerinoConfig.create().addListener("0.0.0.0", 8080);
}

@endpoint @route!("/data")
void data(Request request, Output output)
{
	output ~= "Data:<br>";
	
	Database db = new Database("test.db", OpenFlags.READONLY);
	auto rows = db.query_imm!(int, string)("SELECT * FROM test");
	foreach (row; rows) {
		string f = format("%d: %s", row[0], row[1]);
		output ~= f ~ "<br>";
	}
}


@endpoint @route!("/")
void index(Request request, Output output) {
  SimpleSession session = SimpleSession(request, output, 60.minutes);
  JSONValue session_data = session.load();
  // retrieve and set session data here
  session.save(session_data);

  output.serveFile("public/index.html");
}
