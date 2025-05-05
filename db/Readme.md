Lightweight SQLite wrapper for D.

Overview:
	Provides a minimal and type-safe interface to interact with SQLite using D.
    Supports executing SQL statements, binding parameters, and retrieving typed results.

Usage:
```D
auto db = new Database("my.db");
db.exec_imm("CREATE TABLE test (id INT, name TEXT)");
		
// Insert with bind parameters
auto req = db.prepare_bind("INSERT INTO test VALUES (?, ?)", 1, "Alice");
db.exec(req);

// Query with typed return
auto results = db.query_imm!(int, string)("SELECT id, name FROM test");
foreach (row; results)
writeln(row[0], " ", row[1]);
```

API:
	
class Database
	this(string filename)
		Opens a connection to the SQLite database at the given path.

	~this()
		Closes the database connection.

	void exec_imm(string sql)
		Executes a raw SQL statement without any bound parameters.
		Throws DBException on error.

    Request prepare_bind(T...)(string sql, T binds)
        Prepares a SQL statement and binds parameters.
        T must be int, float, double, or string.
        Returns a Request object for later execution or querying.

    void exec(Request r)
        Executes a prepared Request (no result expected).
        Finalizes the statement afterward.

    auto query_imm(RetTypes...)(string sql)
        Prepares and executes a SQL query with no bind parameters.
        Returns an array of Tuple!RetTypes representing the result rows.

    auto query(RetTypes...)(Request r)
        Executes a prepared query Request and reads the result set into
        an array of Tuple!RetTypes.
        Finalizes the statement afterward.

struct Request
	Internal wrapper around `sqlite3_stmt*` for prepared statements.
