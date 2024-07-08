module texed.locale;

import std.file, std.path, std.string;

import texed.misc, texed.sdl;

private class Locale {
	string language; /// ISO 639-1 language code
	string country; /// Country code
	bool primary; /// Whether this is the primary version of this language

	string name; /// Locale name
	string[string] keys; /// Locale keys
	string fallback; /// Locale fallback
	
	///
	this(string language, string country, string[string] keys) {
		this.keys = keys;
		this.language = language;
		this.country = country;

		string safeGet(string x) {
			if(x in keys)
				return keys[x];
			return "";
		}

		name = safeGet("locale.name");
		primary = safeGet("locale.primary") == "true";
		fallback = safeGet("locale.fallback");	
	}
	
	/// Gets a key from the current locale
	string opIndex(string key) {
		if(key in keys)
			return keys[key];
		if(fallback == "")
			return localeState.fallback[key];
		Locale l = localeState.getLocale(fallback);
		if(l is null || l == this)
			return key;
		return l[key];
	}
}

/// State of the locale module
struct LocaleState {
	Locale current; /// Current locale
	Locale fallback; /// Fallback locale
	Locale[] locales; /// Installed locales

	Locale getLocale(string id) {
		foreach(l; locales) {
			if(l.language~"_"~l.country == id)
				return l;
		}
		return null;
	}
}

LocaleState localeState; /// State of the locale module

/// Gets current locale
@property Locale locale() => localeState.current;

/// Initializes locales. Should be done after SDL init
void initLocales() {
	{
		// load all locales
		string dir = exeDir~"/assets/locales/";
		foreach(filename; dirEntries(dir, SpanMode.shallow)) {
			if(filename.extension != ".cfg")
				continue; // not a locale
			string[string] keys = loadCFG(readText(filename));
			string[] splitName = filename.baseName.stripExtension.split("_");
			if(splitName.length != 2)
				throw new Exception("Locale filenames should be of the form <language>_<country>.cfg");
			Locale locale = new Locale(splitName[0], splitName[1], keys);
			localeState.locales ~= locale;
			// ultimate fallback is en_US
			if(locale.language~"_"~locale.country == "en_US")
				localeState.fallback = locale;
		}
	}
	{
		// set current locale
		SDL_Locale* sdlLocales = SDL_GetPreferredLocales();
		scope(exit)
			SDL_free(sdlLocales);
		size_t i = 0;
		while(true) {
			auto sdlLocale = sdlLocales[i];
			if(sdlLocale.language == null) {
				// end of list and no suitable locale was found
				localeState.current = localeState.fallback;
				break;
			}
			if(setLocale(sdlLocale.language.fromStringz, sdlLocale.country.fromStringz))
				break; // found locale
			i++;
		}
	}
}

/// Sets the current locale. Returns `true` if the locale exists, false otherwise.
bool setLocale(string language, string country) {
	Locale locale;
	foreach(l; localeState.locales) {
		if(l.language == language && l.country == country) {
			// exact match
			locale = l;
			break;
		}
		if(l.language == language) {
			if(locale !is null && locale.primary)
				continue; // already have the primary locale
			locale = l;
		}
	}
	localeState.current = locale;
	return locale !is null;
}
