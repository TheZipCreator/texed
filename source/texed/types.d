/// Contains various useful types
module texed.types;

import std.string, std.conv, std.json, std.file, std.bitmanip, std.array, std.format;
import std.math : isNaN, atan2;

import texed.sdl, texed.state, texed.misc, texed.locale;


/// An exception caused by SDL
class SDLException : Exception {
	this(string msg = SDL_GetError().to!string) {
		super(msg);
	}
}

/// A 2D vector
struct Vector(Scalar) {
	alias This = typeof(this);

	static assert(is(Scalar : int) || is(Scalar : float));
	Scalar x, y; /// Coordinates
	
	/// Binary operation on two vectors
	This opBinary(string op)(This rhs) {
		static assert(op == "+" || op == "-" || op == "*" || op == "/" || op == "%");
		mixin(`return This(x`~op~`rhs.x, y`~op~`rhs.y);`);
	}

	/// Binary operation on a scalar and a vector (+, -, *, /, or %)
	This opBinary(string op)(Scalar rhs) {
		static assert(op == "+" || op == "-" || op == "*" || op == "/" || op == "%");
		mixin(`return This(x`~op~`rhs, y`~op~`rhs);`);
	}

	/// Unary operators (-, +, ~, ++, --)
	This opUnary(string op)() {
		static assert(op == "-" || op == "+" || op == "~" || op == "++" || op == "--");
		mixin(`return This(`~op~`x, `~op~`y);`);
	}

	/// Operator assignment with vector overloading
	void opOpAssign(string op)(This rhs) {
		static assert(op == "+" || op == "-" || op == "*" || op == "/" || op == "%");
		mixin(`x = x`~op~`rhs.x;`);
		mixin(`y = y`~op~`rhs.y;`);
	}
	
	/// Operator assignment with scalar overloading
	void opOpAssign(string op)(Scalar rhs) {
		static assert(op == "+" || op == "-" || op == "*" || op == "/" || op == "%");
		mixin(`x = x`~op~`rhs;`);
		mixin(`y = y`~op~`rhs;`);
	}
	
	/// Converts to an SDL vector
	auto toSDL() {
		static if(is(Scalar : int)) {
			return SDL_Point(x, y);
		}
		else static if(is(Scalar : float)) {
			return SDL_FPoint(x, y);
		}
		else static assert(false);
	}

	/// Converts to a vector of a different type
	Vector!T to(T)() => Vector!T(cast(T)x, cast(T)y);
	
	/// Lerps a vector with another vector
	This lerp(This other, float t) => (other.to!float*t+this.to!float*(1-t)).to!Scalar;

	/// Snaps to a grid
	This snap(Scalar amount) => This(
		cast(int)(x/amount-amount/2)*amount,
		cast(int)(y/amount-amount/2)*amount
	);
	
	/// Returns the angle of a vector.
	float angle() => atan2(cast(float)y, cast(float)x);

	/// Serializes a vector. I would prefer for this to be `texed.project`, but since this is templated it's just easier to put it here
	JSONValue serialize() {
		return JSONValue([x, y]);
	}

}

/// A rectangle
struct Rect(Scalar) {
	static assert(is(Scalar : int) || is(Scalar : float));

	private alias This = Rect!Scalar;
	private alias Vect = Vector!Scalar;
	
	Vect pos; /// Position of the rect
	Vect size; /// Size of the rect
	
	// create from scalars directly
	this(Scalar posx, Scalar posy, Scalar sizex, Scalar sizey) {
		pos = Vect(posx, posy);
		size = Vect(sizex, sizey);
	}

	// create from vectors
	this(Vect pos, Vect size) {
		this.pos = pos;
		this.size = size;
	}
	
	/// Converts to an SDL rect
	auto toSDL() {
		static if(is(Scalar : int)) {
			return SDL_Rect(pos.x, pos.y, size.x, size.y);
		}
		else static if(is(Scalar : float)) {
			return SDL_FRect(pos.x, pos.y, size.x, size.y);
		}
		else static assert(false);
	}

	/// Returns whether a vector is inside the rect
	bool contains(Vect vect) {
		return vect.x >= pos.x && vect.x <= pos.x+size.x && vect.y >= pos.y && vect.y <= pos.y+size.y;
	}

	/// Converts to a rect of a different type
	Rect!T to(T)() => Rect!T(pos.to!T, size.to!T);

	/// Creates a [Rect] from the top-left and bottom-right points
	static This fromPoints(Vect a, Vect b) => This(a, b-a);

	/// Returns true if this rectangle collides with another rectangle
	bool collides(This other) => pos.x + size.x >= other.pos.x && pos.x <= other.pos.x + other.size.x && pos.y + size.y >= other.pos.y && pos.y <= other.pos.y + other.size.y;
}

/// A region comprised of rectangles
struct Region(Scalar) {
	static assert(is(Scalar : int) || is(Scalar : float));
	private alias This = Region!Scalar;
	
	Rect!Scalar[] rects; /// Rectangles comprising this region
	
	/// Returns whether a vector is inside the region
	bool contains(Vector!Scalar vect) {
		foreach(r; rects)
			if(r.contains(vect))
				return true;
		return false;
	}

	/// Joins this region with another
	This join(This other) => Region(rects~other.rects);
	
	/// Joins this region with a rect
	This join(Rect!Scalar other) => Region(rects~other);

	/// Converts to a region of a different type
	Region!T to(T)() => Region!T(rects.map!(x => x.to!T()).array);
}

/// A translation and zoom
class View {
	enum DEFAULT_TRANSLATION = Vector!float(0, 0); /// Default translation
	enum DEFAULT_ZOOM = 32f; /// Default zoom

	Vector!float screenSize; /// Screen size
	Vector!float translation; /// Translation
	float zoom; /// Zoom
	
	///
	this(Vector!float screenSize, Vector!float translation = DEFAULT_TRANSLATION, float zoom = DEFAULT_ZOOM) {
		this.screenSize = screenSize;
		this.translation = translation;
		this.zoom = zoom;
	}
	
	/// The visible rect, in scene-space
	Rect!float visible() => Rect!float(translation-screenSize/(2*zoom), screenSize/zoom);

	/// Transforms scene coordinates to screen coordinates
	Vector!float transform(Vector!float vec) => (vec-translation)*zoom+screenSize/2;
	/// Transforms screen coordinates to scene coordinates
	Vector!float invTransform(Vector!float vec) => (vec-screenSize/2)/zoom+translation;
	/// Transforms scene coordinates to screen coordinates
	Rect!float transform(Rect!float rect) => Rect!float(transform(rect.pos), rect.size*zoom);
	/// Transforms screen coordinates to scene coordinates
	Rect!float invTransform(Rect!float rect) => Rect!float(invTransform(rect.pos), rect.size/zoom);
}

/// A color
struct Color {
	ubyte r = 0, g = 0, b = 0, a = 255;

	enum TRANSPARENT = Color(0, 0, 0, 0);
	
	/// Converts to an SDL_Color
	SDL_Color toSDL() {
		return SDL_Color(r, g, b, a);
	}
	
	/// Sets to the draw color of the window
	void draw(SDL_Renderer* rend) {
		SDL_SetRenderDrawColor(rend, r, g, b, a);
	}

	/// Creates a new color with the given alpha
	Color withAlpha(ubyte alpha) {
		return Color(r, g, b, alpha);
	}

	/// Interpolates to another color
	static Color interp(Color a, Color b, float t) {
		// LERP isn't the greatest for colors but I don't feel like doing something more fancy right now
		ubyte lerp(ubyte x, ubyte y, float s) => cast(ubyte)((cast(float)x)*(1-s)+(cast(float)y)*s);
		return Color(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t), lerp(a.a, b.a, t));
	}
}

/// A window
class DesktopWindow {
	SDL_Renderer* rend; /// The renderer
	SDL_Window* win; /// The window

	this(SDL_Renderer* rend, SDL_Window* win) {
		this.rend = rend;
		this.win = win;
	}

	~this() {
		SDL_DestroyRenderer(rend);
		SDL_DestroyWindow(win);
	}
}

/// An image, backed by an SDL surface
class Image {
	SDL_Texture* texture; /// A texture backing this image
	SDL_Surface* surface; /// The surface backing this image

	/// Creates from an SDL surface. Note that you should only handle the texture thru this class after creating it (since the texture is deleted when the GC frees the instance)
	this(DesktopWindow window, SDL_Surface *surf) {
		surface = surf;
		texture = SDL_CreateTextureFromSurface(window.rend, surf);
	}

	/// Loads an image from a file
	static Image load(DesktopWindow window, string file) {
		SDL_Surface* loaded = IMG_Load(file.toStringz);
		if(loaded == null)
			throw new SDLException(format(locale["error.bad-image"], file, SDL_GetError().to!string));
		scope(exit)
			SDL_FreeSurface(loaded);
		SDL_Surface* converted = SDL_ConvertSurfaceFormat(loaded, SDL_PIXELFORMAT_RGBA8888, 0);
		return new Image(window, converted);
	}

	/// Gets width
	@property int width() => surface.w;
	/// Gets height
	@property int height() => surface.h;
	/// Gets the pixels of this image
	@property Color[] pixels() {
		import std.algorithm, std.range, std.array;
		return (cast(ubyte*)surface.pixels)[0..surface.w*surface.h*4].chunks(4).map!(c => Color(c[1], c[2], c[3], c[0])).array;
	}

	/// Frees the texture
	~this() {
		SDL_FreeSurface(surface);
		SDL_DestroyTexture(texture);
	}
}


/// A font
final class Font {
	bool[][][size_t] bitmap; /// Bitmap of the font
	int charSize; /// Character size of the font
	
	/// The backup font to use when the current font doesn't have a character for something
	static Font backupFont;
	
	/// Creates a font from an image. Upon reading a character that is all white, the loading is terminated. (this should only be done on the last image read)
	/// Params:
	/// images = Images to load, indexed by which group of imgSize^2 codepoints it represents
	/// charSize = Size of each individual character
	/// imgSize = Size of the image (image should be square)
	this(Image[size_t] images, int charSize, int imgSize = 16) {
		this.charSize = charSize;
		foreach(imgIndex, img; images) {
			size_t baseIndex = imgSize*imgSize*imgIndex;
			int w = img.width, h = img.height;
			if(w != charSize*imgSize && h != charSize*imgSize)
				throw new Exception(format(locale["error.bad-charmap"], 16*charSize, 16*charSize, w, h));
			Color[] pixels = img.pixels;
			// probably could be more efficient but eh
			outer: for(int i = 0; i < imgSize; i++) {
				for(int j = 0; j < imgSize; j++) {
					bool[][] ch = new bool[][](charSize);
					bool allWhite = true;
					for(int k = 0; k < charSize; k++) {
						ch[k] = new bool[](charSize);
						for(int l = 0; l < charSize; l++) {
							bool white = pixels[(i*charSize*w+j*charSize+l*w+k)].r != 0;
							ch[k][l] = white;
							if(!white)
								allWhite = false;
						}
					}
					if(allWhite)
						continue;
					bitmap[baseIndex+i*imgSize+j] = ch;
				}
			}
		}
	}
	
	/// Loads the backup font.
	static void loadBackupFont(DesktopWindow window) {
		backupFont = new Font([0: Image.load(window, exeDir~"/assets/unifont.png")], 16, 256);	
	}	
	
	/// Renders a character at a position, with a given view. View may be set to null if not desired. Returns the rectangle the char took up
	Rect!float render(SDL_Renderer* rend, Color fg, Color bg, View view, Vector!float pos, float fontSize, dchar ch, bool transform = true) {
		if(ch !in bitmap) {
			if(backupFont !is null && this != backupFont)
				return backupFont.render(rend, fg, bg, view, pos, fontSize, ch, transform);
		}
		// draw character background
		auto rect = Rect!float(pos, Vector!float(fontSize, fontSize));
		if(view !is null) {
			// culling
			if(!view.visible.collides(rect))
				return view.transform(rect);
			rect = view.transform(rect);
		}
		if(bg.a != 0) {
			bg.draw(rend);
			{
				auto sdlrect = rect.toSDL;
				SDL_RenderFillRectF(rend, &sdlrect);
			}
		}
		if(ch !in bitmap)
			return rect;
		// draw each pixel
		auto map = bitmap[ch];
		float scale = fontSize/charSize;
		fg.draw(rend);
		for(int i = 0; i < charSize; i++) {
			for(int j = 0; j < charSize; j++) {
				if(!bitmap[ch][i][j])
					continue;
				auto crect = Rect!float(pos+Vector!float(i*scale, j*scale), Vector!float(scale, scale));
				if(view !is null)
					crect = view.transform(crect);
				auto sdlrect = crect.toSDL;
				SDL_RenderFillRectF(rend, &sdlrect);
			}
		}
		return rect;
	}

	/// Renders a string at a given position. View may be set to null if not desired. Returns the rectangle on which the string was drawn
	Rect!float render(SDL_Renderer* rend, Color fg, Color bg, View view, Vector!float pos, float fontSize, string text, size_t cursor = size_t.max) {
		auto currPos = pos;
		Rect!float rect;
		// renders the cursor at the current position
		void renderCursor() {
			fg.draw(rend);
			auto pos1 = currPos;
			auto pos2 = currPos+Vector!float(0, fontSize);
			if(view !is null) {
				pos1 = view.transform(pos1);
				pos2 = view.transform(pos2);
			}
			SDL_RenderDrawLineF(rend, pos1.x, pos1.y, pos2.x, pos2.y);
		}
		size_t i = 0;
		foreach(dchar ch; text) {
			// render cursor
			if(cursor == i)
				renderCursor();
			switch(ch) {
				// control characters
				case '\n':
					currPos.x = pos.x;
					currPos.y += fontSize;
					break;
				case '\r':
					currPos.x = pos.x;
					break;
				// normal rendering
				default: {
					auto crect = render(rend, fg, bg, view, currPos, fontSize, ch);
					if(isNaN(rect.pos.x))
						rect = crect;
					else {
						// expand rect
						auto v = crect.pos+crect.size-rect.pos;
						if(v.x > rect.size.x)
							rect.size.x = v.x;
						if(v.y > rect.size.y)
							rect.size.y = v.y;
					}
					currPos.x += fontSize;
				}
			}
			i++;
		}
		// render cursor if past bound
		if(cursor == i)
			renderCursor();
		return rect;
	}
}

/// Something that can be placed down onto the scene and removed from it.
interface Placeable {
	void preview(State state); /// Should preview the object
	void placeMove(State state, Vector!int mouse); /// Called when the mouse is moved
	void place(State state); /// Should place the object into the scene. `select` determines if the object should be selected after.
	void remove(State state); /// Should remove the object from the scene.
}

class AudioNotFoundException : Exception {
	this(string msg) {
		super(msg);
	}
}

/// An audio file. IMPORTANT: Only one instance of [Audio] should be held at a time.
class Audio {
	Mix_Music* handle; /// SDL handle
	float duration; /// Music duration

	private enum LOOP_AMT = 1000; // amount of times to loop. I don't think anyone will end up playing the track over 1000 times lol
	
	///
	this(string filename) {
		if(!filename.exists || filename.isDir)
			throw new AudioNotFoundException(format(locale["error.audio-doesnt-exist"], filename));
		// SDL2 mixer doesn't provide the ability to get the duration of the audio file, so I have to do it manually here:
		{
			// solution taken from https://stackoverflow.com/questions/20794204/how-to-determine-length-of-ogg-file and translated to D
			int length = -1, rate = -1;
			auto data = cast(ubyte[])(read(filename));
			for(long i = data.length-15; i >= 0; i--) {
				if(data[i..i+4] != "OggS")
					continue;
				length = littleEndianToNative!int(data[i+6..i+10].staticArray!4);
				break;
			}
			for(long i = 0; i < data.length-14; i++) {
				if(data[i..i+6] != "vorbis")
					continue;
				rate = littleEndianToNative!int(data[i+11..i+15].staticArray!4);
				break;
			}
			// technically not an sdl exception but I don't want to make a whole exception type just for audio.
			// maybe I should
			if(length == -1 || rate == -1)
				throw new SDLException("Could not get length of audio. (is it an OGG Vorbis file?)");
			duration = cast(float)(length) / cast(float)(rate);
		}
		handle = Mix_LoadMUS(filename.toStringz);
		if(handle == null)
			throw new SDLException();
		Mix_PlayMusic(handle, LOOP_AMT);
		Mix_PauseMusic();
	}
	
	///
	~this() {
		Mix_FreeMusic(handle);
	}
	
	/// Seeks the audio to some location
	void seek(float loc) {
		Mix_SetMusicPosition(loc);
	}
	
	/// Plays the audio
	void play() {
		Mix_ResumeMusic();
	}

	/// Pauses the audio
	void pause() {
		Mix_PauseMusic();
	}
}

/// Struct containing nothing. Used when no data is wanted in a [ScriptableWidget].
struct Nothing {}

/// Template mixin for text editing
mixin template TextEditor(bool allowNewline) {
	string text; /// Text to edit
	size_t cursorPos; /// Current cursor position
	/// Handles an input event
	void editText(State state, InputEvent evt) {
		dstring str = text.toUTF32;
		scope(exit) {
			text = str.toUTF8;
		}
		if(auto ce = cast(CharacterEvent)evt) {
			// insert
			str = str[0..cursorPos]~ce.which~str[cursorPos..$];
			cursorPos++;
		}
		else if(auto ke = cast(KeyEvent)evt) {
			switch(ke.keysym.sym) {
				case SDLK_LEFT:
					// move to the left
					if(cursorPos != 0)
						cursorPos--;
					break;
				case SDLK_RIGHT:
					// move to the right
					if(cursorPos < str.length)
						cursorPos++;
					break;
				case SDLK_BACKSPACE:
					// ~~criss cross~~ delete
					if(cursorPos > 0) {
						str = str[0..cursorPos-1]~str[cursorPos..$];
						cursorPos--;
					}
					break;
				case SDLK_RETURN:
					// insert newline if applicable
					if(!allowNewline) {
						if(state.selected == this)
							state.selected = null;
						break;
					}
					str = str[0..cursorPos]~'\n'~str[cursorPos..$];
					cursorPos++;
					break;
				case SDLK_v:
						if(ke.keysym.mod & KMOD_CTRL) {
							char* text = SDL_GetClipboardText();
							scope(exit)
								SDL_free(text);
							size_t prevLen = str.length;
							str ~= text.to!string.toUTF32;
							cursorPos += str.length-prevLen;
						}
						break;
				default:
					break;
			}
		}

	}
}
