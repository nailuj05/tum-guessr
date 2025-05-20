module game;

import std.stdio;
import std.format;
import std.logger;
import std.conv;
import std.datetime;
import std.process : environment;

import serverino;
import mustache;

import session;
import sqlite;
import logger;

alias MustacheEngine!(string) Mustache;
alias Request.Method.Get GET;
alias Request.Method.Post POST;

@endpoint @priority(10) @route!"/game"
void game(Request request, Output output) {
  if (request.method == GET) {
		int user_id = session_load(request, output);
		if (user_id < 0)
			user_id = 0;
		string location = request.get.read("location", "garching");
		long timestamp = Clock.currTime.toUnixTime;

		scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
		int game_id = get_game_id(request, output, db);
    try {
      int remaining_rounds = db.query!int(db.prepare_bind!int("
      SELECT count(*)
      FROM rounds
      WHERE game_id=? AND finished=FALSE
    ", game_id))[0][0];
      if (remaining_rounds < 1) {
        game_id = -1;
      }
    } catch (Database.DBException e) {
      flogger.warning("Failed to check whether game is finished: " ~ e.msg);
      output.status = 400;
      output ~= "Failed to start game";
      return;
    }

		if (game_id < 0) {
			try {
        db.exec_imm("BEGIN TRANSACTION");
        // Create game in db
        db.exec(db.prepare_bind!(int, string, long)("
					INSERT INTO games (user_id, location, timestamp)
					VALUES (?, ?, ?)
			", user_id, location, timestamp));
        // Get game_id
        game_id = db.query_imm!int("SELECT last_insert_rowid()")[0][0];
        // Create 5 rounds with random photos
        db.exec(db.prepare_bind!(int, string)("
					INSERT INTO rounds (round_id, game_id, photo_id)
					SELECT
					  ROW_NUMBER() OVER () AS round_id,
					  ? AS game_id,
					  photo_id
					FROM (
					  SELECT photo_id
					  FROM photos
					  WHERE location=? AND is_accepted=TRUE
					  ORDER BY RANDOM()
					  LIMIT 5
					)
			  ", game_id, location));
        // Check round creation
        int num_created_rounds = db.query!int(db.prepare_bind!int("
					SELECT count(*)
					FROM rounds
					WHERE game_id=?
			  ", game_id))[0][0];
        info(to!string(num_created_rounds));
        if (num_created_rounds != 5) {
          flogger.warning("Failed to create 5 rounds, rolling back");
          db.exec_imm("ROLLBACK");
          output.status = 500;
          return;
        }
        db.exec_imm("COMMIT");
			} catch (Database.DBException e) {
        flogger.warning("Failed to insert new game in db: " ~ e.msg);
        output.status = 400;
        output ~= "Failed to start game";
        return;
			}

			// TODO: set as cookie with hmac instead
			output.setCookie(Cookie("game_id", game_id.to!string));
		}
		
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
		scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
    int game_id = get_game_id(request, output, db);
    if (game_id < 0) {
			output.status = 400;
			output ~= "Missing or invalid game_id";
      return;
    }
		string photo_path;
		try {
			// Get photo path of next unfinished round
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
			flogger.warning("An error occured while retrieving round data: " ~ e.msg);
			output.status = 500;
			return;
		}
		output.serveFile(photo_path);
		return;
	} else if (request.method == POST) {

		if (!request.post.has("longitude") || !request.post.has("latitude")) {
			output.status = 400;
			output ~= "Missing argument";
		  return;
		}

		scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
		int game_id = get_game_id(request, output, db);
    if (game_id < 0) {
			output.status = 400;
			output ~= "Missing or invalid game_id";
      return;
    }
		
		float guess_latitude;
		float guess_longitude;
		try {
		  guess_latitude = request.post.read("latitude").to!float;
		  guess_longitude = request.post.read("longitude").to!float;
		} catch (Exception e) {
		  output.status = 400;
		  output ~= "Invalid argument format";
		  return;
		}
    
		try {
			// Get coords of next unfinshed round of the game
			auto query_result = db.query!(int, double, double)(db.prepare_bind!(int)("
				SELECT r.round_id, p.latitude, p.longitude
				FROM rounds r
        JOIN photos p ON r.photo_id=p.photo_id
        WHERE r.game_id=? AND r.finished=FALSE
        ORDER BY r.round_id ASC
        LIMIT 1
			", game_id));
			if (query_result.length < 1) {
				output.status = 400;
				output ~= "No such unfinished game";
				return;
			}
      int round_id = query_result[0][0];
			double true_latitude = query_result[0][1];
			double true_longitude = query_result[0][2];
			// TODO: calculate score
			int score = 69;
			// Insert round info
			db.exec(db.prepare_bind!(float, float, int, int, int)("
				UPDATE rounds
				SET guess_lat=?, guess_long=?, score=?, finished=TRUE
				WHERE game_id=? AND round_id=?
			", guess_latitude, guess_longitude, score, game_id, round_id));
		} catch (Database.DBException e) {
			flogger.warning("Failed to set finished round: " ~ e.msg);
			output.status = 500;
			return;
		}
    output.status = 200;
    return;
  }
	output.status = 405;
}

@endpoint @route!"/game/result"
void game_result(Request request, Output output) {
  if (request.method != GET) {
    output.status = 400;
    return;
  }

  scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
  int game_id = get_game_id(request, output, db);
  if (game_id < 0) {
    output.status = 400;
    output ~= "Missing or invalid game_id";
    return;
  }

  double guess_latitude;
  double guess_longitude;
  double true_latitude;
  double true_longitude;
  int score;
  int remaining_rounds;

  try {
    auto query_result = db.query!(int, double, double, double, double)(db.prepare_bind!(int)("
      SELECT r.score, r.guess_lat, r.guess_long, p.latitude, p.longitude
      FROM rounds r
      JOIN photos p ON r.photo_id=p.photo_id
      WHERE r.game_id=? AND r.finished=TRUE
      ORDER BY r.round_id DESC
      LIMIT 1
    ", game_id));
    if (query_result.length < 1) {
      output.status = 400;
      output ~= "No such finished round";
      return;
    }
    score = query_result[0][0];
    guess_latitude = query_result[0][1];
    guess_longitude = query_result[0][2];
    true_latitude = query_result[0][3];
    true_longitude = query_result[0][4];
    remaining_rounds = db.query!int(db.prepare_bind!int("
      SELECT count(*)
      FROM rounds
      WHERE game_id=? AND finished=FALSE
    ", game_id))[0][0];
  } catch (Database.DBException e) {
    flogger.warning("Failed to set finished round: " ~ e.msg);
    output.status = 500;
    return;
  }

  Mustache mustache;
  mustache.path("public");
  scope auto mustache_context = new Mustache.Context;
  mustache_context["score"] = score;
  mustache_context["guess_latitude"] = guess_latitude;
  mustache_context["guess_longitude"] = guess_longitude;
  mustache_context["true_latitude"] = true_latitude;
  mustache_context["true_longitude"] = true_longitude;

  if (remaining_rounds < 1) {
    mustache_context.useSection("final_round");
  }

  output ~= mustache.render("round_result", mustache_context);
}

int get_game_id(Request request, Output output, Database db) {
  if (!request.cookie.has("game_id")) {
    return -1;
  }
  int game_id;
  try {
    game_id = request.cookie.read("game_id").to!int;
  } catch (Exception e) {
    output.setCookie(Cookie("game_id", "invalid").invalidate()); 
    return -2;
  }
  int user_id = session_load(request, output);
  if (user_id < 0) {
    user_id = 0;
  }
  int is_valid;
  try {
    is_valid = db.query!int(db.prepare_bind!(int, int)("
        SELECT count(*)
        FROM users u JOIN games g ON u.user_id=g.user_id
        WHERE u.user_id=? AND g.game_id=?
      ", user_id, game_id))[0][0];
  } catch (Database.DBException e) {
    flogger.warning("Something went wrong during game_id validation of user_id " ~ user_id.to!string ~ " and game_id " ~ game_id.to!string ~ ": " ~ e.msg);
    output.setCookie(Cookie("game_id", "invalid").invalidate()); 
    return -3;
  }
  if (is_valid <= 0) {
    flogger.warning("User " ~ user_id.to!string ~ " tried to use invalid game_id " ~ game_id.to!string);
    output.setCookie(Cookie("game_id", "invalid").invalidate()); 
    return -4;
  }
  return game_id;
}

@endpoint @route!"/game/summary"
void game_summary(Request request, Output output) {
  output ~= "Game summary goes here";
}
