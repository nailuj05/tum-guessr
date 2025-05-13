module app;

import std.ascii : LetterCase;
import std.stdio;
import std.format;
import std.algorithm;
import std.file;
import std.getopt;
import std.range;
import std.logger;
import std.conv;
import std.digest : toHexString;
import std.uni : toLower;
import std.process : environment;
import std.string : representation;
import session;
import std.path : baseName;
import serverino;
import mustache;

import sqlite;
import upload;
import login;
import profile;
import game;
import admin;

mixin ServerinoMain!(upload, login, profile, game, admin);

alias MustacheEngine!(string) Mustache;

@onServerInit ServerinoConfig configure(string[] args)
{
  bool showHelp = false;
	bool verbose = false;
	string db_filename = "prod.db";

	try { showHelp = getopt(args,
													"verbose",  &verbose,
													"database", &db_filename)
			.helpWanted; }
	catch (Exception e) { showHelp = true; }

	if (showHelp)
	{
		writeln("Usage: ", baseName(args[0]), " [OPTIONS]");
    writeln("Options:");
    writeln("  --help             Show this help message");
    writeln("  --verbose          Enable verbose output");
    writeln("  --database=FILE    Path to database file");
		return ServerinoConfig.create().setReturnCode(1);
	}

	environment["verbose"] = verbose.to!string;
	environment["db_filename"] = db_filename;

	if(!exists("photos"))
		 mkdir("photos");

	scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE
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
      user_id INTEGER NOT NULL, 
      FOREIGN KEY(user_id) 
        REFERENCES users(user_id) 
          ON DELETE CASCADE 
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
		db.exec_imm("CREATE TABLE IF NOT EXISTS games (
      game_id INTEGER PRIMARY KEY,
      user_id INTEGER NOT NULL,
      FOREIGN KEY(user_id) 
        REFERENCES users(user_id) 
          ON DELETE CASCADE 
          ON UPDATE CASCADE
    )");
		db.exec_imm("CREATE TABLE IF NOT EXISTS rounds (
      round_id INTEGER PRIMARY KEY,
      game_id INTEGER NOT NULL,
      photo_id INTEGER NOT NULL,
      guess_lat REAL DEFAULT 0,
      guess_long REAL DEFAULT 0,
      score INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY(game_id) 
        REFERENCES games(game_id) 
          ON DELETE CASCADE
          ON UPDATE CASCADE,
      FOREIGN KEY(photo_id)
        REFERENCES photos(photo_id)
          ON DELETE CASCADE
          ON UPDATE CASCADE
    )");
  } catch (Database.DBException e){
    error("An exception occurred during database initialization: ", e.msg);
  }
      
	return ServerinoConfig.create().addListener("0.0.0.0", 8080);
}

@onDaemonStart
void daemon_start() {
	ubyte[] random_bytes = cast(ubyte[])read("/dev/urandom", 64);
	environment["cookie_hmac_key"] = random_bytes.toHexString!(LetterCase.lower);
}

@endpoint @route!("/")
void index(Request request, Output output) {
  Mustache mustache;
  mustache.path("public");

	scope auto mustache_context = new Mustache.Context;
	
  int user_id = session_load(request, output);
  if (user_id > 0) {
    mustache_context.useSection("logged_in");
  }

	int[] milestones = [10, 25, 50, 100, 250, 500, 750, 1000, 1500, 2000, 3000, 5000];
	scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
	int users = db.query_imm!(int)("SELECT COUNT(*) FROM users")[0][0];
	int photos = db.query_imm!(int)("SELECT COUNT(*) FROM photos")[0][0];

	int nextBigger(int[] arr, int num) {
		int i = 0;
		while (arr[i] < num && i < (arr.length - 1)) i++;
		return arr[i];
	}
	mustache_context["user_cur"] = users;
	mustache_context["user_max"] = nextBigger(milestones, users);
	mustache_context["photo_cur"] = photos;
	mustache_context["photo_max"] = nextBigger(milestones, photos);

	output ~= mustache.render("index", mustache_context);
}

@endpoint @route!("/about")
void about(Request request, Output output) {
  Mustache mustache;
  mustache.path("public");
  scope auto mustache_context = new Mustache.Context;
  
  int user_id = session_load(request, output);
  if (user_id > 0) {
    mustache_context.useSection("logged_in");
  }
	output ~= mustache.render("about", mustache_context);
}

@endpoint @priority(-1)
void router(Request request, Output output) {
	string path = "public" ~ request.path;

	// if we don't want to use serve File we will need to set the mime manually (check the code for serveFile for a good example on that)
	string[] ftypes = [".js", ".css", ".ico", ".png", ".jpg", ".jpeg"];
	if(exists(path) && ftypes.any!(suffix => path.endsWith(suffix))) {
		if (environment["verbose"] == true.to!string)
				info("Router served resource at " ~ path);
		output.serveFile(path);
  } else {
    warning("Router refused to serve resource at " ~ path);
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
