module upload;
import std.file;
import std.conv;
import serverino;

@endpoint @route!("/upload")
void upload(Request request, Output output) {
	import std.experimental.logger;
	import core.stdc.time;
	time_t unixTime = core.stdc.time.time(null);

	if(!request.form.read("image").isFile()) {
		output ~= "Not a valid file";
		return;
	}
	
	const Request.FormData fd = request.form.read("image");
	if (fd.isFile) {
		info("File ", fd.filename, " uploaded at ", fd.path);
	}

	// Make sure file doesnt override (even if 2 files are uploaded the same second
	int i = 0;
	string target;
	string img = fd.path;
	do {
		target = "photos/" ~ to!string(unixTime + i++) ~ "." ~ fd.filename[$-3..$];
	} while (exists(target));

	img.copy(target);
	info("Copied file to: ", target);
	
	output ~= "received :)\n";
}
