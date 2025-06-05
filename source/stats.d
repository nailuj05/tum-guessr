module stats;

import std.stdio;
import std.algorithm;
import std.process : environment;
import std.datetime;

import mustache;
import serverino;

import sqlite;
import session;
import logger;

alias MustacheEngine!(string) Mustache;

@endpoint @route!(r => r.path == "/stats" && r.method == Request.Method.Post)
void stats(Request r, Output output) {
	int user_id = max(session_load(r, output), 0);
  long curr_time = Clock.currTime.toUnixTime;

  string device   = r.get.read("device", "");
  string referrer = r.get.read("referrer", "");
  
  scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
  Stmt stmt = db.prepare_bind!(long, int, string, string)("INSERT INTO statistic
    (timestamp, user_id, device, referrer)
    VALUES (?, ?, ?, ?)", curr_time, user_id, device, referrer);
  db.exec(stmt);

  output ~= "tracked";
}
