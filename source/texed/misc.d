/// Miscellaneous helper functions and stuff
module texed.misc;

import std.file, std.path, std.process, std.string;

/// Gets the executable's directory
string exeDir() => dirName(thisExePath);
/// Gets the project directory
string projDir() => buildPath(exeDir, "projects");
/// Gets the project directory of a given project
string projDir(string name) => buildPath(exeDir, "projects", name);

/// Clamps a value to a given range
T clamp(T)(T value, T min, T max) {
	if(value < min)
		return min;
	if(value > max)
		return max;
	return value;
}

/// Clamps a value in-place
void clampInPlace(T)(T* ptr, T min, T max) {
	*ptr = clamp(*ptr, min, max);
}

/// Clips a string to a certain size
string clip(string str, size_t maxSize) {
	if(str.length >= maxSize) {
		if(maxSize < 3)
			return "";
		return str[0..maxSize-3]~"...";
	}
	return str;
}

/// Opens the default file manager at a given location
void openFileManager(string loc) {
	version(linux) {
		spawnProcess(["xdg-open", loc]);
	}
	else version(Windows) {
		spawnProcess(["explorer", loc]); // TODO: test this
	}
	else static assert(false, "OS not supported");
}

/// Linear interpolation
T lerp(T)(T a, T b, float t) => cast(T)((cast(float)b)*t+(cast(float)a)*(1-t));

/// Snap
T snap(T)(T x, T amount) => cast(int)(x/amount)*amount;


/// Loads a .cfg-formatted string
/// Namespaces are handled by prepending a dot before any keys under a namespace.
///
/// For example, a key `bar` under the namespace `foo` will result in the key
/// `foo.bar` being set.
string[string] loadCFG(string text) {
	string[] lines = text.splitLines();
	string[string] keys;
	string namespace = "";
	foreach(line; lines) {
		if(line.length > 0 && line[0] == '#')
			continue; // comment
		if(line.length > 2 && line[0] == '[' && line[$-1] == ']') {
			// namespace
			namespace = line[1..$-1];
			continue;
		}
		ulong eq = line.indexOf('=');
		if(eq == -1) {
			continue; // no equals, so skip
		}
		keys[(namespace == "" ? "" : namespace~".")~line[0..eq]] = line[eq+1..$]; // set key
	}
	return keys;
}

/// Ease a value given an easing from https://easings.net/ and also easeLinear (which returns the given value)
pure nothrow float ease(string easing, float x) {
	import std.math.trigonometry : sin, cos;
	import std.math.algebraic : sqrt;
	import std.math.constants	: PI;
	enum float c1 = 1.70158;
	enum float c2 = c1*1.525;
	enum float c3 = c1+1;
	enum float n1 = 7.5625;
	enum float d1 = 2.75;
	switch(easing) {
		default:
		case "easeLinear":
			return x;
		case "easeInSine":
			return 1-cos((x*PI)/2);
		case "easeOutSine":
			return sin((x*PI)/2);
		case "easeInOutSine":
			return -(cos(PI*x)-1)/2;
		case "easeInCubic":
			return x^^3;
		case "easeOutCubic":
			return 1-(1-x)^^3;
		case "easeInOutCubic":
			return x < 0.5 
				? 4*x^^3
				: 1-((-2*x+2)^^3)/2;
		case "easeInQuint":
			return x^^5;
		case "easeOutQuint":
			return 1-(1-x)^^5;
		case "easeInOutQuint":
			return x < 0.5 
				? 16*x^^5
				: 1-((-2*x+2)^^5)/2;
		case "easeInCirc":
			return 1-sqrt(1-x^^2);
		case "easeOutCirc":
			return sqrt(1-(x-1)^^2);
		case "easeInOutCirc":
			return x < 0.5
				? (1-sqrt(1-(2*x)^^2))/2
				: (sqrt(1-(-2*x+1)^^2)+1)/2;
		case "easeInQuad":
			return x^^2;
		case "easeOutQuad":
			return 1-(1-x)^^2;
		case "easeInOutQuad":
			return x < 0.5
				? 2*x^^2
				: 1-((-2*x+2)^^2)/2;
		case "easeInQuart":
			return x^^4;
		case "easeOutQuart":
			return 1-(1-x)^^4;
		case "easeInOutQuart":
			return x < 0.5
				? 8*x^^4
				: 1-((-2*x+2)^^4)/2;
		case "easeInExpo":
			return x == 0
				? 0
				: 2^^(10*x-10);
		case "easeOutExpo":
			return x == 1
				? 1
				: 1-2^^(-10*x);
		case "easeInOutExpo":
			return x == 0
				? 0
				: x == 1
					? 1
					: x < 0.5
						? 2^^(20*x-10)/2
						: (2-2^^(-20*x+10))/2;
		case "easeInBack":
			return (c3*x^^3)-(c1*x^^2);
		case "easeOutBack":
			return 1+c3*(x-1)^^3+c1*(x-1)^^2;
		case "easeInOutBack":
			return x < 0.5
				? ((2*x)^^2*((c2+1)*2*x-c2))/2
				: ((2*x-2)^^2*((c2+1)*(x*2-2)+c2)+2)/2;
		case "easeInBounce":
			return 1-ease("easeOutBounce", 1-x);
		case "easeOutBounce": {
			if(x < 1/d1)
				return n1*x^^2;
			else if(x < 2/d1)
				return n1*(x -= 1.5/d1)*x+0.75;
			else if(x < 2.5/d1)
				return n1*(x -= 2.25/d1)*x+0.9375;
			else
				return n1*(x-=2.625/d1)*x+0.984375;
		}
		case "easeInOutBounce":
			return x < 0.5
				? (1-ease("easeOutBounce", (1-2*x))/2)
				: (1+ease("easeOutBounce", (2*x-1)))/2;
	}
}
