/// Deals with project saving/loading
module texed.project;

import std.json, std.algorithm, std.array, std.file, std.path, std.conv;

import texed.misc, texed.event, texed.types, texed.app, texed.state;

enum int FORMAT_VERSION = 1; /// Current project format version

/// Exception thrown when loading or saving a project
class ProjectException : Exception {
	this(string msg) {
		super(msg);
	}
}

/// Serializes a color
JSONValue serialize(Color col) {
	return JSONValue([col.r, col.g, col.b, col.a]);
}

/// Deserializes a color
Color deserializeColor(JSONValue j) {
	return Color(j[0].get!ubyte, j[1].get!ubyte, j[2].get!ubyte, j[3].get!ubyte);
}

/// Deserializes a vector
Vector!T deserializeVector(T)(JSONValue j) {
	return Vector!T(j[0].get!T, j[1].get!T);
}

/// Serializes an event
JSONValue serialize(Event e) {
	JSONValue j;
	j["type"] = "unknown";
	j["start"] = e.start;
	j["end"] = e.end;
	if(auto te = cast(TextEvent)e) {
		j["type"] = "text";
		j["pos"] = te.pos.serialize();
		j["text"] = te.text;
		j["fontSize"] = te.fontSize;
		j["fg"] = te.fg.serialize();
		j["bg"] = te.bg.serialize();
	}
	if(auto ce = cast(CameraEvent)e) {
		j["type"] = "camera";
		j["anteTranslation"] = ce.ante.translation.serialize();
		j["anteZoom"] = ce.ante.zoom;
		j["postTranslation"] = ce.post.translation.serialize();
		j["postZoom"] = ce.post.zoom;
		j["easing"] = ce.easing;
	}
	if(auto ie = cast(ImageEvent)e) {
		j["type"] = "image";
		j["pos"] = ie.pos.serialize();
		j["scale"] = ie.scale;
		j["path"] = ie.path;
	}
	if(auto be = cast(BoxEvent)e) {
		j["type"] = "box";
		j["pos"] = be.pos.serialize();
		j["size"] = be.size.serialize();
		j["fontSize"] = be.fontSize;
		j["bg"] = be.bg.serialize();
		j["fg"] = be.fg.serialize();
	}
	return j;
}

/// Deserializes an event
Event deserializeEvent(JSONValue j) {
	string type = j["type"].get!string;
	float start = j["start"].get!float, end = j["end"].get!float;
	switch(type) {
		case "text":
			return new TextEvent(
				deserializeVector!float(j["pos"]),
				start, end,
				deserializeColor(j["fg"]),
				deserializeColor(j["bg"]),
				j["fontSize"].get!float,
				j["text"].get!string
			);
		case "camera":
			return new CameraEvent(
				start, end,
				j["easing"].get!string,
				deserializeVector!float(j["anteTranslation"]),
				j["anteZoom"].get!float,
				deserializeVector!float(j["postTranslation"]),
				j["postZoom"].get!float
			);
		case "image":
			return new ImageEvent(
				start, end,
				deserializeVector!float(j["pos"]),
				j["scale"].get!float,
				j["path"].get!string
			);
		case "box":
			return new BoxEvent(
				start, end,
				deserializeVector!float(j["pos"]),
				deserializeVector!int(j["size"]),
				j["fontSize"].get!float,
				deserializeColor(j["fg"]),
				deserializeColor(j["bg"])
			);
		default:
			return null;
	}
}

/// Saves the current project
void saveProject(State state) {
	state.sortAllChannels();
	try {
		JSONValue j;
		j["version"] = FORMAT_VERSION;
		j["name"] = state.name;
		j["audio"] = state.audioPath;
		JSONValue[][State.CHANNEL_COUNT] events;
		for(size_t i = 0; i < State.CHANNEL_COUNT; i++) {
			events[i] = state.events[i].map!(e => e.serialize()).array;
		}
		j["events"] = events;
		auto dir = projDir(state.name);
		if(!dir.exists)
			mkdir(dir);
		else if(!dir.isDir) {
			remove(dir);
			mkdir(dir);
		}
		write(buildPath(dir, "project.json"), j.toString(JSONOptions.specialFloatLiterals));
	} catch(ConvException e) {
		throw new ProjectException(e.msg);
	} catch(JSONException e) {
		throw new ProjectException(e.msg);
	} catch(FileException e) {
		throw new ProjectException(e.msg);
	}
}

/// Loads a project
void loadProject(string name, DesktopWindow window) {
	auto dir = projDir(name);
	if(!dir.exists || dir.isFile)
		throw new ProjectException("Project "~name~" does not exist.");
	State state;
	try {
		JSONValue j = parseJSON(readText(buildPath(dir, "project.json")), JSONOptions.specialFloatLiterals);
		int ver = j["version"].get!int;
		if(ver > FORMAT_VERSION)
			throw new ProjectException("Project was made in a newer version of Texed.");
		state = new State(window);
		state.name = j["name"].get!string;
		state.audioPath = j["audio"].get!string;
		auto events = j["events"];
		for(size_t i = 0; i < State.CHANNEL_COUNT; i++) {
			if(i >= events.array.length)
				break;
			state.events[i] = events[i].array.map!(e => deserializeEvent(e)).filter!"a !is null".array;
		}
		state.sortAllChannels();
		state.init();
		currentState = state;
	} catch(FileException e) {
		throw new ProjectException(e.msg);
	} catch(ConvException e) {
		throw new ProjectException(e.msg);
	} catch(JSONException e) {
		throw new ProjectException(e.msg);
	}
	// do post-initialization
	for(size_t i = 0; i < State.CHANNEL_COUNT; i++) {
		foreach(evt; state.events[i]) {
			try {
				evt.postInit(state);
			} catch(Exception e) {
				state.error(e);
			}
		}
	}

}
