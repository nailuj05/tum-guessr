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
	scope Database db = new Database("test.db");
	db.exec_imm("CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY, line TEXT)");
	return ServerinoConfig.create().addListener("0.0.0.0", 8080);
}

@endpoint @route!("/data")
void data(Request request, Output output)
{
	output ~= "Data:<br>";
	
	scope Database db = new Database("test.db", OpenFlags.READONLY);
	auto rows = db.query_imm!(int, string)("SELECT * FROM test");
	foreach (row; rows) {
		string f = format("%d: %s", row[0], row[1]);
		output ~= f ~ "<br>";
	}
}

@endpoint
void router(Request request, Output output) {
	string path = "public";
	if(request.path == "/")
		path ~= "/index.html";
	else
		path ~= request.path;

	// if we don't want to use serve File we will need to set the mime manually (check the code for serveFile for a good example on that)
	if(exists(path))
		output.serveFile(path);
}

@endpoint @priority(-1)
void page404(Output output)
{
	// Set the status code to 404
	output.status = 404;
	output.addHeader("Content-Type", "text/plain");

	output.write("Page not found!");
}
