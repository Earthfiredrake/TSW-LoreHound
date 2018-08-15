// Copyright 2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-LoreHound

import com.Utils.WeakPtr;

class efd.LoreHound.lib.util.WeakDelegate {
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
