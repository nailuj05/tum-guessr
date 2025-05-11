module upload;

import std.file;
import std.conv;
import std.array;
import std.algorithm;
import serverino;
import session;

@endpoint @route!("/upload")
void upload(Request request, Output output) {
	Session session = Session(request, output, "test.db");
	int user_id = session.load();
  if (request.method == Request.Method.Get) {
		// TODO: Replace this with proper templating
		import std.experimental.logger;
		info(user_id);
		if(user_id >= 0) {
			output.serveFile("public/upload.html");
		} else {
			output.status = 302;
			output.addHeader("Location", "/");
			output ~= "No access!" ~ "\n" ~ "You are being redirected.";
		}
	} else {
		if (user_id == -1) {
			output.status = 302;
			output.addHeader("Location", "/");
			output ~= "No access!" ~ "\n" ~ "You are being redirected.";
			return;
		}
		
		import std.experimental.logger;
		import core.stdc.time;
		time_t unixTime = core.stdc.time.time(null);

		const Request.FormData fd = request.form.read("image");
		if(fd.isFile() && (fd.path.endsWith(".png") || fd.path.endsWith(".jpg"))) {
			info("File ", fd.filename, " uploaded at ", fd.path);
			
			// make sure file doesnt override (even if 2 files are uploaded the same second
			int i = 0;
			string target;
			string img = fd.path;
			do {
				// TODO: should preserve the file suffix properly here
				target = "photos/" ~ to!string(unixTime + i++) ~ "." ~ fd.filename[$-3..$];
			} while (exists(target));
			
			img.copy(target);
			info("copied file to: ", target);

			// TODO: Add to database here
			
			output ~= "image received\n";
		}
	}
}
