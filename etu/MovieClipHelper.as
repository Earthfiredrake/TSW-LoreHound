// Copyright 2015, eltorqiro
// Released under the terms of the MIT License
// https://github.com/eltorqiro/TSW-Utils
// Modified for EFD SWL Mod Framework:
//   Copyright 2017-2018, Earthfiredrake
//   Used and released under the terms of the MIT License
//   https://github.com/Earthfiredrake/SWL-FrameworkMod

/**
 *
 * Contains functions used to manipulate movieclip and class linkages
 * - e.g. create a clip+class without needing a symbol in the library for it, or create an instance of a symbol with a class specified at runtime
 *
 */

// Mod namespace qualified imports and class definition are #included from locally overriden file
#include "MovieClipHelper.lcl.as"
	/**
	 * static class only, cannot be instantiated
	 */
	private function MovieClipHelper() { }

	/**
	 * creates an empty movieclip from a class, without needing it to be linked to a symbol in the library
	 * - class definitions used by this method must have MovieClip in their inheritance chain, and contain a public static string __className which uniquely identifies the class, minus the "__Packages." prefix
	 * - instances created this way fully support duplicateMovieClip and are in all other ways treated the same as a regular attachMovie() would be
	 * - tip: the class can attach its own internal movieclips to display visual elements
	 *
	 * @param	classRef	the class to use, which must contain a static var __className containing the fully qualified path of the class
	 * @param	name		name that will be given to the created movieclip
	 * @param	parent		parent clip which will host the new clip
	 * @param	depth		depth within the parent the clip will be placed at
	 * @param	initObj		initObj which will be passed to the clip when it is created, same as regular MovieClip.attachMovie()
	 *
	 * @return	the created MovieClip instance; override the type on return to the same type as classRef
	 */
	public static function createMovieWithClass( classRef:Function, name:String, parent:MovieClip, depth:Number, initObj:Object ) : MovieClip {

		if ( parent == undefined || classRef.__className == undefined ) return;
		if ( depth == undefined ) depth = parent.getNextHighestDepth();
		if ( name == undefined || name == "" ) name = classRef.__className.split(".").join("_") + "_" + parent.getNextHighestDepth();

		Object.registerClass( "__Packages." + classRef.__className, classRef );
		return parent.attachMovie( "__Packages." + classRef.__className, name, depth, initObj );

	}

	/**
	 * creates an instance of a symbol from the library, and then links the instance to a class
	 * - class definitions used by this method must have MovieClip in their inheritance chain
	 * - instances created this way do not support duplicateMovieClip, which will instead duplicate an empty movieclip (or whatever class the symbol was originally linked to in the library)
	 * - the onLoad() event handler will be executed synchronously immediately after the constructor, instead of in the next frame
	 *
	 * @param	id			id of the symbol in the library
	 * @param	classRef	class to link to the instance
	 * @param	name		name that will be given to the created movieclip
	 * @param	parent		parent clip which will host the new clip
	 * @param	depth		depth within the parent the clip will be placed at
	 * @param	initObj		initObj which will be "passed" to the clip after it has been created but before the constructor runs; the effect should be the same as regular MovieClip.attachMovie()
	 *
	 * @return	the created MovieClip instance; override the type on return to the same type as classRef
	 */
	public static function attachMovieWithClass( id:String, classRef:Function, name:String, parent:MovieClip, depth:Number, initObj:Object ) : MovieClip {

		var mc:MovieClip = parent.attachMovie( id, name, depth, initObj );

		mc.__proto__ = classRef.prototype;

		for ( var s:String in initObj ) {
			mc[s] = initObj[s];
		}

		// trigger constructor
		classRef.apply(mc);

		// trigger onLoad, since the timeline has already called onLoad on the originally attached movieclip and won't do so again
		mc.onLoad();

		return mc;
	}

	/**
	 * temporarily registers a class with a symbol, then attaches an instance of the symbol, and finally clears the registration
	 * - class definitions used by this method must have MovieClip in their inheritance chain
	 * - instances created this way *may* not support duplicateMovieClip
	 * - instances are otherwise completely natively attached, the same as if the symbol had always been linked to the class
	 * - this is a good alternative for keeping symbol+className linkages unique per project
	 *
	 * @param	id			id of the symbol to create an instance of
	 * @param	classRef	class to use when creating the instance
	 * @param	name		name that will be given to the instance
	 * @param	parent		parent movieclip the instance will be created under
	 * @param	depth		depth within the parent the instance will be placed at
	 * @param	initObj		initObj which will be passed to the instance during creation, the same as regular MovieClip.attachMovie()
	 *
	 * @return	the created MovieClip instance; override the type on return to the same type as classRef
	 */
	public static function attachMovieWithRegister( id:String, classRef:Function, name:String, parent:MovieClip, depth:Number, initObj:Object ) : MovieClip {

		Object.registerClass( id, classRef );
		var mc:MovieClip = parent.attachMovie( id, name, depth, initObj );
		Object.registerClass( id, null );

		return mc;
	}

	/**
	 * changes the class prototype of an existing movieclip instance
	 * - instances modified this way do not support duplicateMovieClip; which will instead create an instance of whichever symbol+class was used when the clip was originally attached
	 * - it is best to only ever do this on clips that start off as raw MovieClip objects, as extended classes *may* have listeners or other behaviour which doesn't necessarily go out of scope
	 *
	 * - after the class is changed, the constructor will be called, immediately followed synchronously by onLoad()
	 *
	 * @param	clip		the movieclip to change class on
	 * @param	classRef	class to change the clip to
	 *
	 * @return	clip
	 */
	public static function changeMovieClass( clip:MovieClip, classRef:Function ) : MovieClip {

		clip.__proto__ = classRef.prototype;

		// trigger constructor
		classRef.apply( clip );

		// trigger onLoad, since the timeline won't call it again
		clip.onLoad();

		return clip;
	}

}
