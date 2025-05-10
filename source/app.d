module app;

import std.stdio;
import std.format;
import std.file;
import session;
import serverino;

import sqlite;
import upload;
import login;

mixin ServerinoMain!(upload, login);

@onServerInit ServerinoConfig configure(string[] args)
{
	scope Database db = new Database("test.db");
  try {
    db.exec_imm("CREATE TABLE IF NOT EXISTS users (
      user_id INTEGER PRIMARY KEY, 
      email TEXT NOT NULL UNIQUE, 
      username TEXT NOT NULL UNIQUE, 
      password_hash TEXT NOT NULL,
      isAdmin INTEGER NOT NULL DEFAULT FALSE   
    )"); 
    db.exec_imm("CREATE TABLE IF NOT EXISTS photos ( 
      photo_id INTEGER PRIMARY KEY, 
      path TEXT NOT NULL UNIQUE,  
      latitude REAL NOT NULL, 
      longitude REAL NOT NULL, 
      user_id INTEGER, 
      FOREIGN KEY(user_id) 
        REFERENCES users(user_id) 
          ON DELETE SET NULL 
          ON UPDATE CASCADE 
    )"); 
    db.exec_imm("CREATE TABLE IF NOT EXISTS sessions ( 
      session_id TEXT PRIMARY KEY, 
      user_id INTEGER NOT NULL, 
      expiration INTEGER NOT NULL, 
      FOREIGN KEY(user_id) 
        REFERENCES users(user_id)  
          ON DELETE CASCADE 
          ON UPDATE CASCADE 
    )");
  } catch (Database.DBException e){
    writeln("An exception occurred during database initialization: ", e.msg);
  }
      
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
  Session session = Session(request, output, "test.db");
  int user_id = session.load();
  if (user_id >= 0) {
    writeln("Logged in as user with id ", user_id, "\n");
  }
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
