module sqlite;
pragma(lib, "sqlite3");

import logger;

// Database Module Overview:
// RAII-style sqlite3 database management
// Simple interface to execute raw and parameterized SQL statements.
// Type-safe variadic bindings (int, float, double, strings)

public struct Stmt {
	import etc.c.sqlite3 : sqlite3_stmt;
	sqlite3_stmt* stmt;
}

enum OpenFlags : int {
  READONLY  = 0x00000001,
  READWRITE = 0x00000002,
  CREATE    = 0x00000004,
}

class Database {
	import std.format;
	import std.string;
	import std.stdio;
	import std.logger;
	import std.conv : to;
	import etc.c.sqlite3;
	import core.stdc.stdio;
	import core.stdc.stdlib;
	import std.typecons : Tuple;
	import std.meta : allSatisfy;
	import std.traits : isSomeString;

	class DBException : Exception {
		this(string msg, string file = __FILE__, size_t line = __LINE__) {
      super(msg, file, line);
    }
	}
	
	private {
		sqlite3* handle;
	}

	private enum allowedBind(T) = (is(T == int) || is(T == long) || is(T == float) || is(T == double) || isSomeString!T);
	
  private void log_stmt(Stmt stmt) {
    // this replacement is crude but I dont want to regex here...
    string retrieved_sql = to!string(sqlite3_sql(stmt.stmt)).replace("\n", " ").replace("\t", " ").replace("  ", "").strip;
    flogger.log("SQL: ", retrieved_sql);
  }

  private void log_stmt(string sql) {
    sql = sql.replace("\n", " ").replace("\t", " ").replace("  ", "").strip;
    flogger.log("SQL: ", sql);
  }
  
public:

	// Constructor to open db file
  this(string filename, OpenFlags flags = OpenFlags.READWRITE | OpenFlags.CREATE) {
		int rc = sqlite3_open_v2(toStringz(filename), &handle, flags, null);
		if (rc) {
			printf("Can't open database: %s\n", sqlite3_errmsg(handle));
			throw new DBException("Database opening failed");
		}
		// flogger.info("Database opened");
		if (flags & (OpenFlags.READWRITE | OpenFlags.CREATE))
			exec_imm("PRAGMA foreign_keys = ON");
	}

	// Destructor closes db
	~this() {
		sqlite3_close(handle);
		// flogger.info("Database closed");
	}
 
	// Execute a plain string SQL Query on the database
	void exec_imm(string sql) {
    log_stmt(sql);
		char *err;
		int rc = sqlite3_exec(handle, toStringz(sql), null, null, &err);
		if (rc != SQLITE_OK) {
			string em = format("SQL exec error: %s\n", to!string(err));
			sqlite3_free(err);
			err = null;
			throw new DBException(em);
		}
	}

	// Binds values to sql string to create request to be executed or queried
	Stmt prepare_bind(T...)(string sql, T binds) if (allSatisfy!(allowedBind, T)) {
		Stmt r;
		
		int rc = sqlite3_prepare_v2(handle, toStringz(sql), -1, &r.stmt, null);
		if (rc != SQLITE_OK) {
			string em = format("Failed to prepare statement: %s\n", to!string(sqlite3_errmsg(handle)));
			throw new DBException(em);
		}

		foreach (i, bind; binds) {
			static if (is(T[i] == float) || is(T[i] == double))
				rc = sqlite3_bind_double(r.stmt, i + 1, cast(double)bind);
			else static if (is(T[i] == int))
				rc = sqlite3_bind_int(r.stmt, i + 1, bind);
			else static if (is(T[i] == long))
				rc = sqlite3_bind_int64(r.stmt, i + 1, bind);
			else static if (isSomeString!(T[i]))
				rc = sqlite3_bind_text(r.stmt, i + 1, toStringz(bind), -1, SQLITE_TRANSIENT);
			
			if (rc != SQLITE_OK) {
				string em = format("Failed to bind parameter: %s\n", to!string(sqlite3_errmsg(handle)));
				sqlite3_finalize(r.stmt);
				throw new DBException(em);
			}
		}
		
		return r;
	}

	// Executes Stmt (no return)
	void exec(Stmt r) {
    log_stmt(r);
		int rc = sqlite3_step(r.stmt);
		scope(exit) sqlite3_finalize(r.stmt);
		
		if (rc != SQLITE_DONE) {
			string em = format("Execution failed: %s\n", to!string(sqlite3_errmsg(handle)));
			throw new DBException(em);
		}
	}

	// Query plain string SQL
	auto query_imm(RetTypes...)(string sql) if(allSatisfy!(allowedBind, RetTypes)) {
		Stmt r = prepare_bind(sql);
		return query!RetTypes(r);
	}

	// Queries Stmt
	auto query(RetTypes...)(Stmt r) if(allSatisfy!(allowedBind, RetTypes)) {
		enum N = RetTypes.length;	
		assert(N == sqlite3_column_count(r.stmt), "Column count mismatch");

    log_stmt(r);
    
		Tuple!RetTypes[] results;
 
		int rc;
		scope(exit) sqlite3_finalize(r.stmt);
		while ((rc = sqlite3_step(r.stmt)) == SQLITE_ROW) {
			Tuple!RetTypes row;
			
      const(char)* ptr;
			static foreach (i; 0..N) {
				static if (is(RetTypes[i] == int))
					row[i] = sqlite3_column_int(r.stmt, i);
				else static if (is(RetTypes[i] == long))
				  row[i] = sqlite3_column_int64(r.stmt, i);
				else static if (is(RetTypes[i] == double))
					row[i] = sqlite3_column_double(r.stmt, i);
				else static if (isSomeString!(RetTypes[i])) {
					ptr = cast(const(char)*)sqlite3_column_text(r.stmt, i);
					row[i] = ptr ? to!string(ptr) : "";
				}
				else static assert(0, "Unsupported return type");
			}
			results ~= row;
		}
		
		if (rc != SQLITE_DONE) {
			throw new DBException("Query execution failed");
		}
		
		return results;
	}	
}
