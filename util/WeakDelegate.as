// Copyright 2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-FrameworkMod

import com.Utils.WeakPtr;

// Mod namespace qualified imports and class definition are #included from locally overriden file
#include "WeakDelegate.lcl.as"
	// Holds a weak reference to the object context used as 'this' by the wrapped function
	// Use to avoid circular references that keep objects alive past the destruction of their root
	// If the target object no longer exists, does not call wrapped function to avoid side effects
	public static function Create(obj:Object, func:Function):Function {
		var f = function() {
			var target:Object = arguments.callee.Target.Get();
			return target != undefined ? arguments.callee.Func.apply(target, arguments) : undefined;
		};
		f.Target = new WeakPtr(obj);
		f.Func = func;
		return f;
	}
}
