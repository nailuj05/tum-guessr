module game;

import std.stdio;
import std.format;
import std.logger;

import serverino;
import mustache;

import session;
import sqlite;

alias MustacheEngine!(string) Mustache;
alias Request.Method.Get GET;
alias Request.Method.Get POST;

@endpoint @route!(r => (r.path == "/photo" && r.get.has("location")))
void photo(Request request, Output output) {
	string location = request.get.read("location");
	try {
		scope Database db = new Database("test.db");
		Stmt stmt = db.prepare_bind("SELECT photo_id, path, latitude, longitude
      FROM photos WHERE location = ?
      ORDER BY RANDOM() LIMIT 1", location);

		auto rows = db.query!(int, string, double, double)(stmt);
		if(rows.length == 0) throw new Exception("Empty result");

		auto row = rows[0];
		
		output ~= format("PhotoID: %d<br>Path: %s<br>Coords: (%f,%f)", row[0], row[1], row[2], row[3]);
	}
	catch (Exception e) {
		error("/photo requested for ", location, " had error: ", e);
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
		Session session = Session(request, output, "test.db");
		int user_id = session.load();
		if (user_id > 0) {
			mustache_context.useSection("logged_in");
		}
		output ~= mustache.render("game", mustache_context);
	}
}

