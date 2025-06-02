module report;

import std.conv;
import std.process;

import serverino;
import mustache;

import sqlite;
import session;
import logger;
import header;

alias MustacheEngine!(string) Mustache;

@endpoint @priority(10) @route!(r => r.path == "/report" && r.get.has("photo_id"))
void report_get(Request r, Output output) {
  Mustache mustache;
  mustache.path("public");
  scope auto mustache_context = new Mustache.Context;
  
  int user_id = set_header_context(mustache_context, r, output);
  mustache_context["photo_id"] = r.get.read("photo_id");
  
	output ~= mustache.render("report", mustache_context);
}

@endpoint @priority(10) @route!(r => r.path == "/report" && r.post.has("photo_id"))
void report_post(Request r, Output output) {
  if(r.post.has("message")) {
    string report = r.post.read("message");

		int user_id = session_load(request, output);
		if (user_id < 0)
			user_id = 0;

    int photo_id = to!int(r.post.read("photo_id", "0"));

    scope(failure) { output.status = 500; output ~= "reporting failed"; }
    scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
    
    Stmt stmt = db.prepare_bind!(int, string, int)("INSERT INTO reports (user_id, report_text, photo_id)
      VALUES(?, ?, ?)", user_id, report, photo_id);
    db.exec(stmt);

    output.status = 200;
    output ~= "report submitted";
  } else {
    output.status = 500;
    output ~= "could not send empty report";
  }
}
