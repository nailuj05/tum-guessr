module game;

import std.stdio;
import std.format;
import std.logger;
import std.conv;
import std.datetime;

import serverino;
import mustache;

import session;
import sqlite;
import std.process : environment;

alias MustacheEngine!(string) Mustache;
alias Request.Method.Get GET;
alias Request.Method.Post POST;

@endpoint @priority(10) @route!("/game")
void game(Request request, Output output) {
  if (request.method == GET) {
		int user_id = session_load(request, output);
		if (user_id < 0)
			user_id = 0;
		string location = request.get.read("location", "garching");
		long timestamp = Clock.currTime.toUnixTime;
		int game_id;

		scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
		try {
			db.exec_imm("BEGIN TRANSACTION");
			db.exec(db.prepare_bind!(int, string, long)("
			  INSERT INTO games (user_id, location, timestamp)
			  VALUES (?, ?, ?)
			", user_id, location, timestamp));
			game_id = db.query_imm!int("SELECT last_insert_rowid()")[0][0];
			db.exec(db.prepare_bind!(int, string)("
        INSERT INTO rounds (round_id, game_id, photo_id)
        SELECT
          ROW_NUMBER() OVER () AS round_id,
          ? AS game_id,
          photo_id
        FROM (
          SELECT photo_id
          FROM photos
          WHERE location=?
          ORDER BY RANDOM()
          LIMIT 5
        )
      ", game_id, location));
			auto created_rounds = db.query!(int, int, int, int)(db.prepare_bind!int("
        SELECT round_id, photo_id, score, finished
        FROM rounds
        WHERE game_id=?
      ", game_id));
			info(created_rounds);
			if (created_rounds.length != 5) {
				warning("Failed to create 5 rounds, rolling back");
				db.exec_imm("ROLLBACK");
				output.status = 500;
				return;
			}
			db.exec_imm("COMMIT");
		} catch (Database.DBException e) {
			warning("Failed to insert new game in db: " ~ e.msg);
			output.status = 400;
			output ~= "Failed to start game";
			return;
		}

		// TODO: set as cookie with hmac instead
		output.addHeader("tum-guessr-game-id", game_id.to!string);
		
		Mustache mustache;
		mustache.path("public");
		scope auto mustache_context = new Mustache.Context;
		
		if (user_id > 0) {
			mustache_context.useSection("logged_in");
		}
		output ~= mustache.render("game", mustache_context);
	}
}

@endpoint @route!"/game/round"
void round(Request request, Output output) {
	int user_id = session_load(request, output);
	if (user_id < 0)
		user_id = 0;
	
	if (request.method == GET) {
		if (!request.get.has("game_id")) {
			output.status = 400;
			output ~= "Missing argument game_id";
			return;
		}
		int game_id;
		try {
			game_id = request.get.read("game_id").to!int;
		} catch (Exception e) {
			output.status = 400;
			output ~= "Invalid argument format";
			return;
		}
		string photo_path;
		scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
		try {
			auto query_result = db.query!string(db.prepare_bind!(int, int)("
				SELECT p.path
				FROM games g
          JOIN rounds r
            ON g.game_id=r.game_id
          JOIN photos p
            ON r.photo_id=p.photo_id
				WHERE g.game_id=? AND g.user_id=? AND r.finished=FALSE
				ORDER BY r.round_id ASC
				LIMIT 1
			", game_id, user_id));
			if (query_result.length < 1) {
				output.status = 400;
				output ~= "No such unfinished game";
				return;
			}
			photo_path = query_result[0][0];
		} catch (Database.DBException e) {
			warning("An error occured while retrieving round data: " ~ e.msg);
			output.status = 500;
			return;
		}
		output.serveFile(photo_path);
		return;
	} else if (request.method == POST) {

		if (!request.post.has("game_id") || !request.post.has("longitude") || !request.post.has("latitude")) {
			output.status = 400;
			output ~= "Missing argument";
		  return;
		}

		int game_id;
		float guess_latitude;
		float guess_longitude;
		try {
		  game_id = request.post.read("game_id").to!int;
		  guess_latitude = request.post.read("latitude").to!float;
		  guess_longitude = request.post.read("longitude").to!float;
		} catch (Exception e) {
		  output.status = 400;
		  output ~= "Invalid argument format";
		  return;
		}
		double true_latitude;
		double true_longitude;
		int score;

		scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
		try {
			db.exec_imm("BEGIN TRANSACTION");
			auto round_id_query_result = db.query!int(db.prepare_bind!int("
				SELECT round_id
				FROM rounds
				WHERE game_id=? AND finished=FALSE
				ORDER BY round_id ASC
				LIMIT 1
			", game_id));
			if (round_id_query_result.length < 1) {
				db.exec_imm("ROLLBACK");
				output.status = 400;
				output ~= "No such unfinished game";
				return;
			}
			int round_id = round_id_query_result[0][0];
			auto coords_query_result = db.query!(double, double)(db.prepare_bind!(int, int)("
				SELECT p.latitude, p.longitude
				FROM games g JOIN rounds r ON g.game_id=r.game_id
        JOIN photos p ON r.photo_id=p.photo_id
        WHERE g.game_id=? AND r.round_id=?
			", game_id, round_id));
			true_latitude = coords_query_result[0][0];
			true_longitude = coords_query_result[0][1];
			// TODO: calculate score
			score = 69;
			db.exec(db.prepare_bind!(float, float, int, int, int)("
				UPDATE rounds
				SET guess_lat=?, guess_long=?, score=?, finished=TRUE
				WHERE game_id=? AND round_id=?
			", guess_latitude, guess_longitude, score, game_id, round_id));
			db.exec_imm("COMMIT");
		} catch (Database.DBException e) {
			warning("Failed to set finished round: " ~ e.msg);
			output.status = 500;
			return;
		}

		output ~= format(`{"latitude": %2.6f, "longitude": %2.6f, "score": %d}` ~ "\n", true_latitude, true_longitude, score);
		return;
	}
	output.status = 405;
}


