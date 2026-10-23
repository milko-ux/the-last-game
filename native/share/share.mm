// ============================================================
// THE SHARE SHEET (roadmap step 5): the phone's own share sheet -- the
// panel Photos and Safari open: Messages, Instagram, Save Image, AirDrop
// -- with the run's share image and a line of text. Godot has no share
// call, so this is a GDExtension: native iPhone code Godot loads at
// start (share.gdextension), seen from GDScript as the engine singleton
// "NativeShare":
//
//   if Engine.has_singleton("NativeShare"):
//       Engine.get_singleton("NativeShare").share(text, absolute_image_path)
//
// share() returns false when there was nothing to show it with; the
// "closed" signal says how the sheet went away (completed = the player
// picked a target and it went through; activity = which one, e.g.
// "com.apple.UIKit.activity.Message"; "" when cancelled).
//
// Built by tools/build_share.sh (godot-cpp) for the iPhone and the Mac.
// The Mac build only exists so the Mac's headless tools load the project
// without an error: there share() returns false. The web has none: there
// the singleton does not exist.
// ============================================================

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

#include <TargetConditionals.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif

using namespace godot;

class NativeShare : public Object {
	GDCLASS(NativeShare, Object);

protected:
	static void _bind_methods() {
		ClassDB::bind_method(D_METHOD("share", "text", "image_path"), &NativeShare::share);
		ADD_SIGNAL(MethodInfo("closed", PropertyInfo(Variant::BOOL, "completed"), PropertyInfo(Variant::STRING, "activity")));
	}

public:
	bool share(const String &p_text, const String &p_image_path);
};

#if TARGET_OS_IOS
static NSString *ns(const String &p_s) {
	return [NSString stringWithUTF8String:p_s.utf8().get_data()];
}

// The controller on top: the sheet is presented from it.
static UIViewController *top_controller() {
	UIWindow *window = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) {
			continue;
		}
		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (w.isKeyWindow) {
				window = w;
				break;
			}
		}
		if (window == nil) {
			window = ((UIWindowScene *)scene).windows.firstObject;
		}
		if (window != nil) {
			break;
		}
	}
	UIViewController *vc = window.rootViewController;
	while (vc.presentedViewController != nil) {
		vc = vc.presentedViewController;
	}
	return vc;
}

bool NativeShare::share(const String &p_text, const String &p_image_path) {
	NSMutableArray *items = [NSMutableArray array];
	if (!p_image_path.is_empty()) {
		UIImage *image = [UIImage imageWithContentsOfFile:ns(p_image_path)];
		if (image != nil) {
			[items addObject:image];
		}
	}
	if (!p_text.is_empty()) {
		[items addObject:ns(p_text)];
	}
	UIViewController *host = top_controller();
	if (items.count == 0 || host == nil) {
		return false;
	}
	UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
	// An iPad shows the sheet as a popover, which needs somewhere to point.
	sheet.popoverPresentationController.sourceView = host.view;
	sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds), CGRectGetMidY(host.view.bounds), 0, 0);
	sheet.popoverPresentationController.permittedArrowDirections = 0;
	NativeShare *self_ = this;
	sheet.completionWithItemsHandler = ^(UIActivityType activity, BOOL completed, NSArray *returned, NSError *error) {
		String name = activity != nil ? String::utf8(activity.UTF8String) : String();
		// Deferred: the signal reaches GDScript on Godot's own next frame.
		self_->call_deferred("emit_signal", "closed", (bool)completed, name);
	};
	[host presentViewController:sheet animated:YES completion:nil];
	return true;
}
#else
bool NativeShare::share(const String &p_text, const String &p_image_path) {
	return false;
}
#endif

static NativeShare *singleton = nullptr;

static void initialize_share(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(NativeShare);
	singleton = memnew(NativeShare);
	Engine::get_singleton()->register_singleton("NativeShare", singleton);
}

static void uninitialize_share(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	Engine::get_singleton()->unregister_singleton("NativeShare");
	memdelete(singleton);
	singleton = nullptr;
}

extern "C" GDExtensionBool GDE_EXPORT share_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init(p_get_proc_address, p_library, r_initialization);
	init.register_initializer(initialize_share);
	init.register_terminator(uninitialize_share);
	init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init.init();
}
