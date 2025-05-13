module game;

import std.stdio;
import std.format;
import std.logger;
import std.conv;

import serverino;
import mustache;

import session;
import sqlite;
import std.process : environment;

alias MustacheEngine!(string) Mustache;
alias Request.Method.Get GET;
alias Request.Method.Get POST;

@endpoint @route!(r => (r.path == "/photo" && r.get.has("location")))
void photo(Request request, Output output) {
	string location = request.get.read("location");
	try {
		scope Database db = new Database(environment["db_filename"]);
		Stmt stmt = db.prepare_bind("SELECT photo_id, path
      FROM photos WHERE location = ?
      ORDER BY RANDOM() LIMIT 1", location);

		auto rows = db.query!(int, string)(stmt);
		if(rows.length == 0) throw new Exception("Empty result");

		auto row = rows[0];
		output.serveFile(row[1]);
		output.addHeader("photo_id", to!string(row[0]));
	}
	catch (Exception e) {
		error("/photo requested for ", location, " had error: ", e);
		output.status = 500;
		output ~= "Internal Server Error\n";
	}
}

@endpoint @route!(r => (r.path == "/coords" && r.get.has("photo_id")))
void coords(Request request, Output output) {
	string id = request.get.read("photo_id");
	try {
		scope Database db = new Database(environment["db_filename"]);
		Stmt stmt = db.prepare_bind("SELECT latitude, longitude
      FROM photos WHERE photo_id = ?", id);

		auto rows = db.query!(double, double)(stmt);
		if(rows.length == 0) throw new Exception("Empty result");

		auto row = rows[0];
		output ~= format(`{"lat": %2.6f, "long": %2.6f}`, row[0], row[1]);
	}
	catch (Exception e) {
		error("/coords requested for ", id, " had error: ", e);
		output.status = 500;
		output ~= "Internal Server Error\n";
	}
}

@endpoint @priority(10) @route!("/game")
void game(Request request, Output output) {
  if (request.method == Request.Method.Get) {
		Mustache mustache;
		mustache.path("public");
		scope auto mustache_context = new Mustache.Context;
		
		int user_id = session_load(request, output);
		if (user_id > 0) {
			mustache_context.useSection("logged_in");
		}
		output ~= mustache.render("game", mustache_context);
	}
}

