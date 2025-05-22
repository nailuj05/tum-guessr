module header;

import std.stdio;
import std.process;
import std.conv;

import mustache;
import serverino;

import session;
import sqlite;
import logger;

alias MustacheEngine!(string) Mustache;

void set_header_context(Mustache.Context context, Request request, Output output) {
  int user_id = session_load(request, output);
  if (user_id > 0) {
    context.useSection("logged_in");

		scope(failure) flogger.error("header context failed");
		scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
		auto row = db.query!(int, int)(db.prepare_bind!(int)("SELECT is_admin, is_trusted FROM users WHERE user_id = ?", user_id))[0];

		if (row[0] == 1) {
				context.useSection("is_admin");
				context.useSection("is_trusted");
		}
		if (row[1] == 1) {
				context.useSection("is_trusted");
		}
  }
}
