/// Publically imports bindbc SDL bindings, and adds some more that bindbc doesn't cover
module texed.sdl;

///
public import bindbc.sdl;

// things bindbc-sdl is missing
extern(C) {
	///
	struct SDL_FRect {
		float x, y, w, h;
	}
	///
	struct SDL_FPoint {
		float x, y;
	}
	///
	int SDL_RenderFillRectF(SDL_Renderer* renderer, const(SDL_FRect*) rect);
	///
	int SDL_RenderDrawRectF(SDL_Renderer* renderer, const(SDL_FRect*) rect);
	///
	int SDL_RenderCopyF(SDL_Renderer* renderer, SDL_Texture* texture, const(SDL_Rect*) srcrect, const(SDL_FRect*) dstrect);
	///
	int SDL_RenderDrawLineF(SDL_Renderer* renderer, float x1, float y1, float x2, float y2);
	///
	struct SDL_Locale {
		immutable(char)* language;
		immutable(char)* country;
	}
	///
	SDL_Locale* SDL_GetPreferredLocales();
}
