module game;

import serverino;
import session;
import mustache;
import sqlite;
import std.process : environment;

alias MustacheEngine!(string) Mustache;

@endpoint @route!("/game")
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

