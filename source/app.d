module app;

import std.stdio;
import std.format;
import std.algorithm;
import std.file;
import session;
import serverino;
import mustache;

import sqlite;
import upload;
import login;
import profile;

mixin ServerinoMain!(upload, login, profile);

@onServerInit ServerinoConfig configure(string[] args)
{
  import std.logger;
	if(!exists("photos"))
		 mkdir("photos");

	scope Database db = new Database("test.db", OpenFlags.READWRITE
      | OpenFlags.CREATE);
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
		// TODO: Games table for tracking played games, wins, losses, ...
  } catch (Database.DBException e){
    error("An exception occurred during database initialization: ", e.msg);
  }
      
	return ServerinoConfig.create().addListener("0.0.0.0", 8080);
}

@endpoint @route!("/")
void index(Request request, Output output) {
  Mustache mustache;
  mustache.path("public");
  scope auto mustache_context = new Mustache.Context;
  Session session = Session(request, output, "test.db");
  int user_id = session.load();
  if (user_id > 0) {
    mustache_context.useSection("logged_in");
  }
	output ~= mustache.render("index", mustache_context);
}

@endpoint @priority(-1)
void router(Request request, Output output) {
  Session session = Session(request, output, "test.db");
  int user_id = session.load();
	string path = "public" ~ request.path;

	// if we don't want to use serve File we will need to set the mime manually (check the code for serveFile for a good example on that)
	string[] ftypes = [".js", ".css", ".ico", ".png", ".jpg", ".jpeg"];
	if(exists(path) && ftypes.any!(suffix => path.endsWith(suffix)))
		output.serveFile(path);
	else {
		output.status = 302;
		output.addHeader("Location", "/");
	}
}

@endpoint @priority(-10)
void page404(Output output)
{
	// Set the status code to 404
	output.status = 404;
	output.addHeader("Content-Type", "text/plain");

	output.write("Page not found!");
}
