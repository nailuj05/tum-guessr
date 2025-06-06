module game;

import std.stdio;
import std.format;
import std.logger;
import std.conv;
import std.datetime;
import std.process : environment;
import std.typecons : Tuple;

import serverino;
import mustache;

import session;
import sqlite;
import logger;
import header;

alias MustacheEngine!(string) Mustache;
alias Request.Method.Get GET;
alias Request.Method.Post POST;

@endpoint @priority(10) @route!"/game"
void game(Request request, Output output) {
  string location;
  if (request.method == GET) {
		int user_id = session_load(request, output);
		if (user_id < 0)
			user_id = 0;

		location = request.get.read("location");
    if (location == "" || location == null) {
      location = request.cookie.read("location");
    }
    assert(location != "");
    
		long timestamp = Clock.currTime.toUnixTime;

		scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
		int game_id = get_game_id(request, output, db);
		int played_rounds;
		int remaining_rounds;
		int total_rounds;
		int next_round_duration_seconds;
    try {
      auto query_result = db.query!int(db.prepare_bind!(int, string, int, string)("
				SELECT count(*)
				FROM rounds r
        LEFT JOIN games g
        USING (game_id)
        WHERE r.game_id = ? AND g.location = ?
        UNION ALL
        SELECT count(*)
        FROM finished_rounds r
        LEFT JOIN games g
        USING (game_id)
        WHERE r.game_id = ? AND g.location = ?
		  ", game_id, location, game_id, location));
			total_rounds = query_result[0][0];
			played_rounds = query_result[1][0];
			remaining_rounds = total_rounds - played_rounds;
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
				int duration = 60;
        db.exec(db.prepare_bind!(int, int, string)("
					INSERT INTO rounds (round_id, game_id, photo_id, duration)
					SELECT
					  ROW_NUMBER() OVER () AS round_id,
					  ? AS game_id,
					  photo_id,
            ? AS duration
					FROM (
					  SELECT photo_id
					  FROM photos_with_acceptance
					  WHERE location=? AND is_accepted=TRUE
					  ORDER BY RANDOM()
					  LIMIT 5
					)
			  ", game_id, duration, location));
        // Check round creation
        int num_created_rounds = db.query!int(db.prepare_bind!int("
					SELECT count(*)
					FROM rounds
					WHERE game_id=?
			  ", game_id))[0][0];
        if (num_created_rounds != 5) {
          flogger.warning("Failed to create 5 rounds, rolling back");
          db.exec_imm("ROLLBACK");
          output.status = 500;
					output ~= "Failed to create game, not enough accepted photos for location";
          return;
        }
        db.exec_imm("COMMIT");
				total_rounds = num_created_rounds;
				remaining_rounds = num_created_rounds;
				played_rounds = 0;

        // Update Cookie for new game
        output.setCookie(Cookie("location", location.to!string));
			} catch (Database.DBException e) {
        flogger.warning("Failed to insert new game in db: " ~ e.msg);
        output.status = 400;
        output ~= "Failed to start game";
        return;
			}


			// TODO: set as cookie with hmac instead
			output.setCookie(Cookie("game_id", game_id.to!string));
		}

		auto duration_query_result = db.query!int(db.prepare_bind!int("
				SELECT
          COALESCE(
            (t.start_time + r.duration - CAST(strftime('%s', 'now') AS INTEGER)),
            r.duration
          )
				FROM unfinished_rounds r
        LEFT JOIN timing t
        USING (game_id, round_id)
				WHERE r.game_id = ?
				ORDER BY round_id ASC
				LIMIT 1
		", game_id));
		next_round_duration_seconds = duration_query_result[0][0];
		
		Mustache mustache;
		mustache.path("public");
		scope auto mustache_context = new Mustache.Context;
		
    set_header_context(mustache_context, request, output);
		mustache_context["current_round"] = played_rounds + 1;
		mustache_context["total_rounds"] = total_rounds;
		mustache_context["total_round_time"] = next_round_duration_seconds;
    mustache_context.addSubContext(location);
		output ~= mustache.render("game", mustache_context);
	}
}


@endpoint @route!"/game/round"
void round(Request request, Output output) {
	int user_id = session_load(request, output);
	if (user_id < 0)
		user_id = 0;
	
	if (request.method == GET) {
		scope Database db = new Database(environment["db_filename"], OpenFlags.READWRITE);
    int game_id = get_game_id(request, output, db);
    if (game_id < 0) {
			output.status = 400;
			output ~= "Missing or invalid game_id";
      return;
    }
    int photo_id;
		string photo_path;
		int round_id;
		try {
			// Get photo path of next unfinished round
			auto query_result = db.query!(int, string, int)(db.prepare_bind!(int, int)("
				SELECT p.photo_id, p.path, r.round_id
				FROM games g
				JOIN unfinished_rounds r
				USING (game_id)
				JOIN photos p
				USING (photo_id)
				WHERE g.game_id=? AND g.user_id=?
				ORDER BY r.round_id ASC
				LIMIT 1
			", game_id, user_id));
			if (query_result.length < 1) {
				output.status = 400;
				output ~= "No such unfinished game";
				return;
			}
      photo_id = query_result[0][0];
			photo_path = query_result[0][1];
			round_id = query_result[0][2];
			db.exec(db.prepare_bind!(int, int)("
        INSERT OR IGNORE INTO timing (round_id, game_id, start_time)
        VALUES (?, ?, CAST(strftime('%s', 'now') AS INTEGER))
      ", round_id, game_id));
		} catch (Database.DBException e) {
			flogger.warning("An error occured while retrieving round data: " ~ e.msg);
			output.status = 500;
			return;
		}
    output.setCookie(Cookie("photo_id", photo_id.to!string));
    output.setCookie(Cookie("round_id", round_id.to!string));
		output.serveFile(photo_path);
		return;
	} else if (request.method == POST) {

		if (!request.cookie.has("round_id") || !request.post.has("longitude") || !request.post.has("latitude")) {
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
		
		int given_round_id;
		float guess_latitude;
		float guess_longitude;
		try {
			given_round_id = request.cookie.read("round_id").to!int;
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
				FROM unfinished_rounds r
        JOIN photos p 
        USING (photo_id)
        WHERE r.game_id=?
        ORDER BY r.round_id ASC
        LIMIT 1
			", game_id));
			if (query_result.length < 1) {
				output.status = 400;
				output ~= "No such unfinished round";
				return;
			}
      int round_id = query_result[0][0];
			if (given_round_id != round_id) {
				info(given_round_id.to!string);
				info(round_id.to!string);
				output.status = 400;
				output ~= "Round already timed out";
				return;
			}
			double true_latitude = query_result[0][1];
			double true_longitude = query_result[0][2];
      double distance_meters = distance_between_coordinates_in_meters(guess_latitude, guess_longitude, true_latitude, true_longitude);
			import std.algorithm.comparison : max, min;
			import core.math : sqrt;
			int score = max(0, min(2000, (2000 / ((distance_meters + 45) * 0.02)))).to!int;
			// Insert guess
			db.exec(db.prepare_bind!(int, int, float, float, int)("
				INSERT INTO guesses (game_id, round_id, latitude, longitude, score)
				VALUES (?, ?, ?, ?, ?)
			", game_id, round_id, guess_latitude, guess_longitude, score));
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
	bool has_timed_out;
  int remaining_rounds;

  try {
    auto query_result = db.query!(int, double, double, double, double, int)(db.prepare_bind!(int)("
      SELECT r.score, g.latitude, g.longitude, p.latitude, p.longitude, r.has_timed_out
      FROM finished_rounds r
      LEFT JOIN guesses g
      USING (round_id, game_id)
      JOIN photos p
      USING (photo_id)
      WHERE r.game_id=?
      ORDER BY r.round_id DESC
      LIMIT 1
    ", game_id));
    if (query_result.length < 1) {
      output.status = 400;
      output ~= "No such finished round";
      return;
    }
    score							= query_result[0][0];
    guess_latitude		= query_result[0][1];
    guess_longitude		= query_result[0][2];
    true_latitude			= query_result[0][3];
    true_longitude		= query_result[0][4];
		has_timed_out			= query_result[0][5].to!bool;
    remaining_rounds	= db.query!int(db.prepare_bind!int("
      SELECT count(*)
      FROM unfinished_rounds
      WHERE game_id=? 
    ", game_id))[0][0];
  } catch (Database.DBException e) {
    flogger.warning("Failed to set finished round: " ~ e.msg);
    output.status = 500;
    return;
  }

  
  Mustache mustache;
  mustache.path("public");
  scope auto mustache_context = new Mustache.Context;
  set_header_context(mustache_context, request, output);
  mustache_context["score"]							= score;
  mustache_context["width"]							= cast(int)(score / 20);
	if (has_timed_out) {
		mustache_context.useSection("timeout");
	} else {
		int distance = cast(int)distance_between_coordinates_in_meters(guess_latitude, guess_longitude, true_latitude, true_longitude);
		mustache_context["distance"]					= distance;
		mustache_context["guess_latitude"]	= guess_latitude;
		mustache_context["guess_longitude"] = guess_longitude;
	}
  mustache_context["true_latitude"]			= true_latitude;
  mustache_context["true_longitude"]		= true_longitude;

  if (remaining_rounds < 1) {
    mustache_context.useSection("final_round");
  }

  output ~= mustache.render("round_result", mustache_context);
}

@endpoint @route!"/game/summary"
void game_summary(Request request, Output output) {
  if (request.method != GET) {
    output.status = 405;
    return;
  }
  scope Database db = new Database(environment["db_filename"], OpenFlags.READONLY);
  int game_id = get_game_id(request, output, db);
  if (game_id < 0) {
    output.status = 400;
    output ~= "Missing or invalid game_id";
    return;
  }
  Tuple!(int, double, double, double, double, int)[] round_results;
  try {
    int remaining_rounds = db.query!int(db.prepare_bind!int("
      SELECT count(*)
      FROM unfinished_rounds
      WHERE game_id=?
    ", game_id))[0][0];
    if (remaining_rounds > 0) {
      output.status = 400;
      output ~= "Game not finished, how did you get here?";
      return;
    }
    round_results = db.query!(int, double, double, double, double, int)(db.prepare_bind!int("
      SELECT r.score, g.latitude, g.longitude, p.latitude, p.longitude, r.has_timed_out
      FROM finished_rounds r
      LEFT JOIN guesses g
      USING (round_id, game_id)
      JOIN photos p
      USING (photo_id)
      WHERE r.game_id=?
      ORDER BY r.round_id ASC
    ", game_id));
  } catch (Database.DBException e) {
    flogger.error("Failed to retrieve game summary: " ~ e.msg);
    output.status = 500;
    return;
  }

  Mustache mustache;
  mustache.path("public");
  scope auto mustache_context = new Mustache.Context;
  set_header_context(mustache_context, request, output);
  
	int total_score = 0;
  foreach (i, result; round_results) {
		int score = result[0];
		bool has_timed_out = result[5].to!bool;
		total_score += score;
    auto mustache_subcontext = mustache_context.addSubContext("rounds");
    mustache_subcontext["score"]							= score;
    mustache_subcontext["num"]								= i + 1;
		if (has_timed_out) {
			mustache_subcontext.useSection("timeout");
		} else {
			mustache_subcontext["guess_latitude"]		= result[1];
			mustache_subcontext["guess_longitude"]	= result[2];
		}
    mustache_subcontext["true_latitude"]			= result[3];
    mustache_subcontext["true_longitude"]			= result[4];
		mustache_subcontext["has_timed_out"]			= has_timed_out;

  }
  string location = request.cookie.read("location", "garching");
	mustache_context["total_score"] = total_score;
	mustache_context["location"] = location;
  mustache_context.addSubContext(location);

  output ~= mustache.render("game_summary", mustache_context);
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

double degrees_to_radians(double degrees) {
  import std.math.constants : PI;
  return degrees * PI / 180;
}

double distance_between_coordinates_in_meters(double latitude_1, double longitude_1, double latitude_2, double longitude_2) {
  import std.math.exponential;
  import std.math.trigonometry : sin, cos, atan2;
  import core.math : sqrt;
  double earth_radius_km = 6371;
  double latitude_difference = degrees_to_radians(latitude_2 - latitude_1);
  double longitude_difference = degrees_to_radians(longitude_2 - longitude_1);
  latitude_1 = degrees_to_radians(latitude_1);
  latitude_2 = degrees_to_radians(latitude_2);
  double a = pow(sin(latitude_difference / 2), 2) + pow(sin(longitude_difference / 2), 2) * cos(latitude_1) * cos(latitude_2);
  double c = 2 * atan2(sqrt(a), sqrt(1-a));
  return earth_radius_km * c * 1000;
}
